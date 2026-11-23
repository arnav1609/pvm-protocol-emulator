`timescale 1ns/1ps
`default_nettype none

// The retained SPI frame is immutable from reception through authorization
// and bus retirement. One hash engine serves the MAC and image-chain checks.
module pvm_auth (
    input wire clk, rst_n,
    input wire trust_valid, challenge_valid,
    input wire [255:0] master_key,
    input wire [63:0] device_id,
    input wire [127:0] challenge,
    output wire challenge_ready, challenge_retired,
    input wire frame_start, frame_end, frame_byte_aligned, rx_valid,
    input wire [7:0] rx_byte,
    input wire safe_read,
    input wire [15:0] safe_addr,
    output wire safe_read_grant,
    output wire [591:0] info,
    input wire [2:0] pvm_state, tx_level, rx_level,
    input wire [7:0] bus_rdata,
    output wire [15:0] bus_addr,
    output wire [7:0] bus_wdata,
    output wire bus_we, bus_re, bus_rack
);
    localparam [7:0] OPEN=1, CHUNK=2, FINISH=3, START=4, CANCEL=5,
                     TX_PUSH=6, RX_POP=7, CLEAR_FLAGS=8;
    localparam [4:0] IDLE=0, HEADER=1, META=2, MAC_START=3, MAC_WAIT=4,
                     PREFLIGHT=5, CHAIN_BEGIN=6, CHAIN_SEND=7, CHAIN_COMPARE=8,
                     SCAN_BEGIN=9, SCAN_WAIT=10, CRC_LO=11, CRC_LO_DATA=12,
                     CRC_HI=13, CRC_HI_DATA=14, ISSUE=15, BUS_WAIT=16,
                     STORE_OPEN=17, STORE_LINK=18, RELEASE=19;
    localparam [7:0] OK=0, REJECT=1, RETRY=2, VALIDATION_FAULT=3, UNAVAILABLE=4;

    reg [4:0] state;
    reg [7:0] cursor, op, identity, result;
    reg [31:0] seq;
    reg header_bad, digest_bad, crc_bad;
    reg [127:0] active_challenge;
    reg challenge_live, challenge_seen, prior_trust;
    reg [255:0] root, link;
    reg [71:0] candidate_meta, meta;
    reg [7:0] chunk_index;
    reg [31:0] cached_rx;
    reg [2:0] cached_rx_len;

    wire auth_reset_n = rst_n && trust_valid;
    wire abort_session = prior_trust && !trust_valid;
    wire retire;
    assign challenge_ready = auth_reset_n && !challenge_live && !retire && state==IDLE &&
                             (!challenge_seen || active_challenge!=challenge);
    wire challenge_take = challenge_ready && challenge_valid;
    assign challenge_retired = retire || (abort_session && challenge_live);
    wire active = auth_reset_n && challenge_live;
    wire busy = state!=IDLE || frame_valid || effect_busy;

    always @(posedge clk) begin
        if (!rst_n) begin
            prior_trust <= 0;
            challenge_seen <= 0;
            challenge_live <= 0;
            active_challenge <= 0;
        end else begin
            prior_trust <= trust_valid;
            if (!trust_valid || retire)
                challenge_live <= 0;
            else if (challenge_take) begin
                active_challenge <= challenge;
                challenge_seen <= 1;
                challenge_live <= 1;
            end
        end
    end

    wire frame_valid;
    wire [7:0] body_length, frame_byte;
    wire [7:0] mac_frame_index, scan_frame_index, effect_frame_index;
    wire [7:0] payload_len = body_length - 8'd64;
    wire [7:0] preload_len = meta[39:32];
    wire [15:0] expected_crc = {meta[23:16],meta[31:24]};
    wire [7:0] chunk_count = meta[15:8];
    wire [3:0] record_count = records_for(payload_len);
    wire [7:0] link_start = 8'd65 + payload_len - 8'd32;

    function [3:0] records_for;
        input [7:0] length;
        begin
            case (length)
                35: records_for=1;
                38: records_for=2;
                41: records_for=3;
                44: records_for=4;
                47: records_for=5;
                50: records_for=6;
                53: records_for=7;
                56: records_for=8;
                default: records_for=0;
            endcase
        end
    endfunction

    wire chain_job = state==CHAIN_BEGIN || state==CHAIN_SEND || state==CHAIN_COMPARE;
    wire mac_job = state==MAC_START || state==MAC_WAIT;
    wire [7:0] frame_index = mac_job ? mac_frame_index :
                            state==BUS_WAIT ? effect_frame_index :
                            state==SCAN_WAIT ? scan_frame_index :
                            state==CHAIN_SEND ? 8'd65+cursor-8'd11 :
                            state==STORE_OPEN ? 8'd32+cursor :
                            state==STORE_LINK ? link_start+cursor : cursor;
    pvm_auth_rx receiver (
        .clk(clk),.rst_n(auth_reset_n),.frame_start(frame_start),.frame_end(frame_end),
        .frame_byte_aligned(frame_byte_aligned),.rx_valid(rx_valid),.rx_byte(rx_byte),
        .accept_submit(active && !busy),.release_frame(state==RELEASE),.frame_valid(frame_valid),
        .body_length(body_length),.read_index(frame_index),.read_byte(frame_byte)
    );

    wire mac_start, mac_release, mac_data_valid, mac_done, authenticated;
    wire [1:0] mac_mode;
    wire [255:0] mac_key;
    wire [15:0] mac_length;
    wire [7:0] mac_data, digest;
    wire [4:0] mac_digest_index;
    wire hash_ready, hash_valid, hash_idle;
    pvm_auth_mac mac (
        .clk(clk),.rst_n(auth_reset_n),.start(state==MAC_START),.trust_valid(active),
        .master_key(master_key),.device_id(device_id),.identity(identity),.body_length(body_length),
        .frame_read_index(mac_frame_index),.frame_read_byte(frame_byte),
        .hash_start(mac_start),.hash_release(mac_release),.hash_mode(mac_mode),.hash_key(mac_key),
        .hash_length(mac_length),.hash_data(mac_data),.hash_data_valid(mac_data_valid),
        .hash_idle(hash_idle && mac_job),.hash_ready(hash_ready && mac_job),
        .hash_valid(hash_valid && mac_job),.hash_read_index(mac_digest_index),
        .hash_read_byte(digest),.done(mac_done),.authenticated(authenticated)
    );

    wire [7:0] chain_length = op==CHUNK ? payload_len+8'd11 : preload_len+8'd13;
    wire [63:0] domain = op==CHUNK ? 64'h314b4c422d4d5650 : 64'h31444e452d4d5650;
    reg [7:0] chain_data;
    always @* begin
        if (cursor<8)
            chain_data=domain[8*cursor[2:0]+:8];
        else if (op==FINISH)
            chain_data=meta[8*(cursor-8'd8)+:8];
        else case (cursor)
            8: chain_data=0;
            9: chain_data=chunk_index;
            10: chain_data={4'b0,record_count};
            default: chain_data=frame_byte;
        endcase
    end

    pvm_auth_hash shared_hash (
        .clk(clk),.rst_n(auth_reset_n),.start(chain_job ? state==CHAIN_BEGIN && hash_idle : mac_start),
        .release_result(chain_job ? state==CHAIN_COMPARE && hash_valid && cursor==31 : mac_release),
        .mode(chain_job ? 2'd0 : mac_mode),.key(mac_key),
        .length(chain_job ? {8'b0,chain_length} : mac_length),
        .data(chain_job ? chain_data : mac_data),
        .data_valid(chain_job ? state==CHAIN_SEND : mac_data_valid),.data_ready(hash_ready),
        .idle(hash_idle),.result_valid(hash_valid),
        .result_index(chain_job ? cursor[4:0] : mac_digest_index),.result_byte(digest)
    );

    wire scan_done, scan_ok, image_complete;
    wire [7:0] image_version;
    wire issue;
    wire effect_busy, effect_done, effect_ok;
    wire [31:0] effect_rx;
    wire [2:0] effect_rx_len;
    pvm_auth_records canonical (
        .clk(clk),.rst_n(auth_reset_n),.open_session(issue && op==OPEN),
        .begin_scan(state==SCAN_BEGIN),.commit_scan(state==BUS_WAIT && effect_done && effect_ok && op==CHUNK),
        .discard_scan(state==RELEASE),.record_count(record_count),.read_index(scan_frame_index),
        .read_byte(frame_byte),.scan_done(scan_done),.scan_ok(scan_ok),
        .image_complete(image_complete),.image_version(image_version)
    );

    wire stopped = pvm_state==0;
    wire ready = pvm_state==2;
    wire running = pvm_state==3;
    wire terminal = pvm_state==4 || pvm_state==5;
    wire [7:0] owner;
    wire [2:0] phase;
    wire [31:0] next_seq, last_committed;
    wire [2:0] fifo_count = op==FINISH ? preload_len[2:0] :
                            op==RX_POP ? candidate_meta[2:0] : payload_len[2:0];
    wire fifo_short = (op==TX_PUSH && fifo_count > 3'd4-tx_level) ||
                      (op==RX_POP && fifo_count > rx_level);
    wire retry_authorized = fifo_short && owner!=0 && owner==identity &&
        phase==3 && seq==next_seq && next_seq!=32'hffffffff &&
        (running || (op==RX_POP && terminal));

    pvm_auth_policy ownership (
        .clk(clk),.rst_n(auth_reset_n),.trust_valid(trust_valid),.req(state==ISSUE && !fifo_short),
        .mac_ok(1'b1),.context_ok(1'b1),.grammar_ok(1'b1),.identity(identity),.op(op),
        .sequence_number(seq),.pvm_stopped(stopped),.pvm_ready(ready),.pvm_running(running),
        .pvm_terminal(terminal),.complete(effect_done),.effect_success(effect_ok),
        .fresh_challenge(challenge_take),.issue(issue),.pending(),.retire(retire),
        .owner(owner),.phase(phase),.next_seq(next_seq),.last_committed(last_committed)
    );

    wire effect_we, effect_re, effect_rack;
    wire [15:0] effect_addr;
    pvm_auth_bus effects (
        .clk(clk),.rst_n(rst_n),.abort_session(abort_session),.issue(issue),.finish_crc_bad(crc_bad),
        .op(op),.pvm_state(pvm_state),.record_count(record_count),.fifo_count(fifo_count),
        .expected_crc(expected_crc),.image_version(image_version),.preload(meta[71:40]),
        .frame_index(effect_frame_index),.frame_byte(frame_byte),.bus_rdata(bus_rdata),
        .bus_addr(effect_addr),.bus_wdata(bus_wdata),.bus_we(effect_we),.bus_re(effect_re),
        .bus_rack(effect_rack),.complete(effect_done),.success(effect_ok),.busy(effect_busy),
        .rx_result(effect_rx),.rx_length(effect_rx_len)
    );

    wire crc_read = state==CRC_LO || state==CRC_HI;
    wire reserve_bus = crc_read || state==CRC_LO_DATA || state==CRC_HI_DATA ||
                       state==ISSUE || state==BUS_WAIT || effect_busy || effect_we;
    assign safe_read_grant = rst_n && safe_read && !reserve_bus;
    assign bus_addr = effect_we || effect_re || effect_rack ? effect_addr :
                      crc_read ? (state==CRC_LO ? 16'h0f06 : 16'h0f07) : safe_addr;
    assign bus_we = rst_n && effect_we && (active || abort_session);
    assign bus_re = rst_n && (safe_read_grant || (active && (crc_read || effect_re)));
    assign bus_rack = rst_n && active && effect_rack;

    function [31:0] big_endian;
        input [31:0] value;
        begin
            big_endian={value[7:0],value[15:8],value[23:16],value[31:24]};
        end
    endfunction

    assign info = {cached_rx,5'd0,cached_rx_len,
                   owner!=0 && state!=STORE_OPEN ? root : 256'd0,
                   big_endian(last_committed),big_endian(next_seq),
                   active ? active_challenge : 128'd0,device_id,owner,
                   active ? result : (retire || trust_valid && result==OK ? OK : UNAVAILABLE),
                   7'd0,busy,5'd0,phase,8'd1};
    wire open_meta_ok = candidate_meta[7:0]==0 && candidate_meta[15:8]!=0 &&
                        candidate_meta[39:32]<=4 &&
                        payload_len==8'd5+candidate_meta[39:32];
    wire chain_byte_ok = digest==link[8*cursor[4:0]+:8];
    wire [2:0] device_offset = cursor[2:0]-3'd4;
    wire [3:0] challenge_offset = cursor[3:0]-4'd12;

    always @(posedge clk) begin
        if (!auth_reset_n) begin
            state<=IDLE; cursor<=0; op<=0; identity<=0; seq<=0; result<=UNAVAILABLE;
            header_bad<=0; digest_bad<=0; crc_bad<=0;
            root<=0; link<=0; meta<=0; candidate_meta<=0; chunk_index<=0;
            cached_rx<=0; cached_rx_len<=0;
        end else begin
            if (challenge_take)
                result<=OK;
            case (state)
                IDLE: if (frame_valid) begin
                    cursor<=1; seq<=0; header_bad<=0; crc_bad<=0;
                    candidate_meta<=0; state<=HEADER;
                end
                HEADER: begin
                    if (cursor==1) header_bad<=frame_byte!=1;
                    else if (cursor==2) op<=frame_byte;
                    else if (cursor==3) identity<=frame_byte;
                    else if (cursor<12)
                        header_bad<=header_bad || frame_byte!=device_id[8*device_offset+:8];
                    else if (cursor<28)
                        header_bad<=header_bad || frame_byte!=active_challenge[8*challenge_offset+:8];
                    else if (cursor<32)
                        seq<={seq[23:0],frame_byte};
                    else if (cursor<64)
                        header_bad<=header_bad || (op!=OPEN && frame_byte!=root[8*cursor[4:0]+:8]);
                    if (cursor==64) begin
                        if (header_bad || seq!=next_seq || next_seq==32'hffffffff) begin
                            result<=REJECT; state<=RELEASE;
                        end else if ((op==OPEN && payload_len>=5 && payload_len<=9) ||
                                    (op==RX_POP && payload_len==1)) begin
                            cursor<=65; state<=META;
                        end else state<=MAC_START;
                    end else cursor<=cursor+1'b1;
                end
                META: begin
                    candidate_meta[8*(cursor-8'd65)+:8]<=frame_byte;
                    cursor<=cursor+1'b1;
                    if (cursor==8'd64+payload_len)
                        state<=MAC_START;
                end
                MAC_START: state<=MAC_WAIT;
                MAC_WAIT: if (mac_done) begin
                    if (authenticated) state<=PREFLIGHT;
                    else begin result<=REJECT; state<=RELEASE; end
                end
                PREFLIGHT: begin
                    state<=RELEASE; result<=REJECT;
                    case (op)
                        OPEN: if (open_meta_ok && owner==0 && stopped && seq==0) state<=ISSUE;
                        CHUNK: if (owner==identity && phase==1 && stopped && record_count!=0 &&
                                  chunk_index<chunk_count &&
                                  (chunk_index+8'd1==chunk_count || record_count==8))
                            state<=CHAIN_BEGIN;
                        FINISH: if (owner==identity && phase==1 && stopped && payload_len==0 &&
                                   chunk_index==chunk_count && image_complete)
                            state<=CHAIN_BEGIN;
                        START,CANCEL,CLEAR_FLAGS: if (payload_len==0) state<=ISSUE;
                        TX_PUSH: if (payload_len>=1 && payload_len<=4) state<=ISSUE;
                        RX_POP: if (payload_len==1 && candidate_meta[7:0]>=1 &&
                                    candidate_meta[7:0]<=4) state<=ISSUE;
                        default: ;
                    endcase
                end
                CHAIN_BEGIN: if (hash_idle) begin
                    cursor<=0; digest_bad<=0; state<=CHAIN_SEND;
                end
                CHAIN_SEND: if (hash_ready) begin
                    cursor<=cursor+1'b1;
                    if (cursor+8'd1==chain_length) begin cursor<=0; state<=CHAIN_COMPARE; end
                end
                CHAIN_COMPARE: if (hash_valid) begin
                    digest_bad<=digest_bad || !chain_byte_ok;
                    cursor<=cursor+1'b1;
                    if (cursor==31) begin
                        if (digest_bad || !chain_byte_ok) state<=RELEASE;
                        else state<=op==CHUNK ? SCAN_BEGIN : CRC_LO;
                    end
                end
                SCAN_BEGIN: state<=SCAN_WAIT;
                SCAN_WAIT: if (scan_done) state<=scan_ok ? ISSUE : RELEASE;
                CRC_LO: state<=CRC_LO_DATA;
                CRC_LO_DATA: begin crc_bad<=bus_rdata!=expected_crc[7:0]; state<=CRC_HI; end
                CRC_HI: state<=CRC_HI_DATA;
                CRC_HI_DATA: begin crc_bad<=crc_bad || bus_rdata!=expected_crc[15:8]; state<=ISSUE; end
                ISSUE: begin
                    if (issue) state<=BUS_WAIT;
                    else begin result<=retry_authorized ? RETRY : REJECT; state<=RELEASE; end
                end
                BUS_WAIT: if (effect_done) begin
                    state<=RELEASE;
                    result<=effect_ok ? OK : VALIDATION_FAULT;
                    if (effect_ok) begin
                        case (op)
                            OPEN: begin
                                cursor<=0; meta<=candidate_meta; chunk_index<=0;
                                cached_rx<=0; cached_rx_len<=0; state<=STORE_OPEN;
                            end
                            CHUNK: begin cursor<=0; chunk_index<=chunk_index+1'b1; state<=STORE_LINK; end
                            CANCEL: begin root<=0; link<=0; meta<=0; cached_rx<=0; cached_rx_len<=0; end
                            RX_POP: begin cached_rx<=effect_rx; cached_rx_len<=effect_rx_len; end
                            default: ;
                        endcase
                    end
                end
                STORE_OPEN: begin
                    root[8*cursor[4:0]+:8]<=frame_byte;
                    link[8*cursor[4:0]+:8]<=frame_byte;
                    cursor<=cursor+1'b1;
                    if (cursor==31) state<=RELEASE;
                end
                STORE_LINK: begin
                    link[8*cursor[4:0]+:8]<=frame_byte;
                    cursor<=cursor+1'b1;
                    if (cursor==31) state<=RELEASE;
                end
                RELEASE: state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
