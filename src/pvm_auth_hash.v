`timescale 1ns/1ps
`default_nettype none

// Fixed PVM SPA domains. Load key as bytes [7:0] first and stream exactly length bytes.
// Result bytes remain readable until release_result. Only the trusted controller uses this port.
module pvm_auth_hash (
    input wire clk, rst_n,
    input wire start, release_result,
    input wire [1:0] mode, // 0 SHA3-256, 1 KMAC key derivation, 2 KMAC command
    input wire [255:0] key,
    input wire [15:0] length,
    input wire [7:0] data,
    input wire data_valid,
    output wire data_ready, idle, result_valid,
    input wire [4:0] result_index,
    output wire [7:0] result_byte
);
    localparam WAIT_JOB=0, INIT=1, PREFIX=2, KEY_BLOCK=3, MESSAGE=4,
               ENCODE=5, PAD=6, LAUNCH=7, WAIT_PERM=8, RESULT=9, ERASE=10;
    reg [3:0] phase, resume_phase;
    reg [1:0] domain, encode_pos;
    reg [255:0] key_shift;
    reg [15:0] remaining;
    reg [7:0] index;
    reg [7:0] value;
    reg absorb;
    reg [3:0] after_absorb;
    wire core_busy, core_done, core_absorb_ready;
    wire [7:0] digest_byte;
    assign idle = rst_n && phase == WAIT_JOB && !core_busy;
    assign data_ready = rst_n && phase == MESSAGE && !core_busy;
    assign result_valid = rst_n && phase == RESULT;
    assign result_byte = result_valid ? digest_byte : 8'd0;

    pvm_keccak core (
        .clk(clk), .rst_n(rst_n),
        .clear((idle && start && mode != 3) || (result_valid && release_result)),
        .permute(phase == LAUNCH), .squeeze(resume_phase == RESULT), .absorb(absorb),
        .absorb_index(index), .absorb_byte(value), .read_index({3'b0,result_index}),
        .read_byte(digest_byte), .busy(core_busy), .absorb_ready(core_absorb_ready), .done(core_done)
    );

    always @* begin
        absorb = 1'b0;
        value = 0;
        after_absorb = phase;
        case (phase)
            PREFIX: begin
                absorb = 1;
                after_absorb = index == 135 ? KEY_BLOCK : PREFIX;
                case (index)
                    0: value=8'h01; 1: value=8'h88; 2: value=8'h01; 3: value=8'h20;
                    4: value="K"; 5: value="M"; 6: value="A"; 7: value="C";
                    8: value=8'h01; 9: value=8'h40;
                    10: value="P"; 11: value="V"; 12: value="M"; 13: value="-";
                    14: value=domain==1 ? "K":"C";
                    15: value=domain==1 ? "E":"M";
                    16: value=domain==1 ? "Y":"D";
                    17: value="1";
                    default: ;
                endcase
            end
            KEY_BLOCK: begin
                absorb = 1;
                after_absorb = index == 135 ? (remaining == 0 ? ENCODE : MESSAGE) : KEY_BLOCK;
                case (index)
                    0: value=8'h01; 1: value=8'h88; 2: value=8'h02;
                    3: value=8'h01; 4: value=8'h00;
                    default: if (index >= 5 && index < 37) value=key_shift[7:0];
                endcase
            end
            MESSAGE: begin
                absorb = data_valid && data_ready;
                value = data;
                if (remaining == 1) after_absorb = domain == 0 ? PAD : ENCODE;
            end
            ENCODE: begin
                absorb = 1;
                value = encode_pos == 0 ? 8'h01 : encode_pos == 1 ? 8'h00 : 8'h02;
                if (encode_pos == 2) after_absorb = PAD;
            end
            PAD: begin
                // First delimiter and final rate byte can coincide at offset 135.
                absorb = 1;
                value = (index == 135 ? 8'h80 : 8'h00) |
                        (encode_pos != 3 ? (domain==0 ? 8'h06 : 8'h04) : 8'h00);
                if (index == 135) after_absorb = RESULT;
            end
            default: ;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            phase <= WAIT_JOB;
            resume_phase <= WAIT_JOB;
            key_shift <= 0;
            domain <= 0;
            index <= 0;
            remaining <= 0;
            encode_pos <= 0;
        end else begin
            case (phase)
                WAIT_JOB: if (idle && start && mode != 3) begin
                    phase <= INIT;
                    domain <= mode;
                    index <= 0;
                    remaining <= length;
                    key_shift <= mode == 0 ? 256'd0 : key;
                    encode_pos <= 0;
                end
                INIT: if (!core_busy)
                    phase <= domain == 0 ? (remaining == 0 ? PAD : MESSAGE) : PREFIX;
                LAUNCH: if (!core_busy) phase <= WAIT_PERM;
                WAIT_PERM: if (core_done) phase <= resume_phase;
                RESULT: if (release_result) phase <= ERASE;
                ERASE: if (!core_busy) phase <= WAIT_JOB;
                default: ;
            endcase
            if (absorb && core_absorb_ready) begin
                if (phase == KEY_BLOCK && index >= 5 && index < 37)
                    key_shift <= key_shift >> 8;
                if (phase == MESSAGE) remaining <= remaining - 1'b1;
                if (phase == ENCODE) encode_pos <= encode_pos == 2 ? 2'd0 : encode_pos + 1'b1;
                if (phase == PAD) encode_pos <= 3;
                if (index == 135) begin
                    index <= 0;
                    resume_phase <= after_absorb;
                    phase <= LAUNCH;
                end else begin
                    index <= index + 1'b1;
                    phase <= after_absorb;
                end
            end
        end
    end
endmodule
`default_nettype wire
