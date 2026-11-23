`timescale 1ns/1ps
`default_nettype none
// Canonical record preflight. Freeze input frame until commit/discard.
// scan_ok permits issuing writes only after the independent image-link check.
// A rejected candidate never alters the committed cursor.
module pvm_auth_records(
    input wire clk, rst_n, open_session,
    input wire begin_scan, commit_scan, discard_scan,
    input wire [3:0] record_count,
    output wire [7:0] read_index,
    input wire [7:0] read_byte,
    output wire scan_done, scan_ok, image_complete,
    output reg [7:0] image_version
);
    localparam IDLE=0, HIGH=1, LOW=2, BYTE_DATA=3, APPROVED=4, REJECTED=5;
    reg [2:0] state;
    reg [3:0] record, count;
    reg [15:0] addr, cfg_addr;
    reg [7:0] cfg_mask, staged_version;
    reg [6:0] committed_min, staged_min, committed_config, staged_config;
    reg committed_half, staged_half, committed_end, staged_end;
    wire [7:0] offset = 8'd65 + {4'd0,record} + {3'd0,record,1'b0};
    assign read_index = state==HIGH ? offset : state==LOW ? offset+1'b1 : offset+2'd2;
    assign scan_done = state==APPROVED || state==REJECTED;
    assign scan_ok = state==APPROVED;
    assign image_complete = committed_end;
    wire instruction_ok = addr < 16'h0040 && staged_config==0 &&
        (staged_half ? addr[6:0]==staged_min : (!addr[0] && addr[6:0]>=staged_min));
    wire config_ok = staged_min!=0 && !staged_half && staged_config<100 &&
                      addr==cfg_addr && (read_byte & ~cfg_mask)==0;
    wire version_ok = staged_config==100 && addr==16'h0f0a;
    always @* begin
        {cfg_addr,cfg_mask}=0;
        case(staged_config)
            7'd0: {cfg_addr,cfg_mask} = 24'h0100ff;
            7'd1: {cfg_addr,cfg_mask} = 24'h0101ff;
            7'd2: {cfg_addr,cfg_mask} = 24'h01021f;
            7'd3: {cfg_addr,cfg_mask} = 24'h01031f;
            7'd4: {cfg_addr,cfg_mask} = 24'h01041f;
            7'd5: {cfg_addr,cfg_mask} = 24'h010507;
            7'd6: {cfg_addr,cfg_mask} = 24'h01061f;
            7'd7: {cfg_addr,cfg_mask} = 24'h01071f;
            7'd8: {cfg_addr,cfg_mask} = 24'h010803;
            7'd9: {cfg_addr,cfg_mask} = 24'h01091f;
            7'd10: {cfg_addr,cfg_mask} = 24'h010a1f;
            7'd11: {cfg_addr,cfg_mask} = 24'h010b1f;
            7'd12: {cfg_addr,cfg_mask} = 24'h010c1f;
            7'd13: {cfg_addr,cfg_mask} = 24'h010d1f;
            7'd14: {cfg_addr,cfg_mask} = 24'h010e1f;
            7'd15: {cfg_addr,cfg_mask} = 24'h010f1f;
            7'd16: {cfg_addr,cfg_mask} = 24'h0110ff;
            7'd17: {cfg_addr,cfg_mask} = 24'h0111ff;
            7'd18: {cfg_addr,cfg_mask} = 24'h011203;
            7'd19: {cfg_addr,cfg_mask} = 24'h0200ff;
            7'd20: {cfg_addr,cfg_mask} = 24'h0201ff;
            7'd21: {cfg_addr,cfg_mask} = 24'h0202ff;
            7'd22: {cfg_addr,cfg_mask} = 24'h0203ff;
            7'd23: {cfg_addr,cfg_mask} = 24'h020407;
            7'd24: {cfg_addr,cfg_mask} = 24'h0208ff;
            7'd25: {cfg_addr,cfg_mask} = 24'h0209ff;
            7'd26: {cfg_addr,cfg_mask} = 24'h020aff;
            7'd27: {cfg_addr,cfg_mask} = 24'h020bff;
            7'd28: {cfg_addr,cfg_mask} = 24'h020c07;
            7'd29: {cfg_addr,cfg_mask} = 24'h0210ff;
            7'd30: {cfg_addr,cfg_mask} = 24'h0211ff;
            7'd31: {cfg_addr,cfg_mask} = 24'h0212ff;
            7'd32: {cfg_addr,cfg_mask} = 24'h0213ff;
            7'd33: {cfg_addr,cfg_mask} = 24'h021407;
            7'd34: {cfg_addr,cfg_mask} = 24'h0218ff;
            7'd35: {cfg_addr,cfg_mask} = 24'h0219ff;
            7'd36: {cfg_addr,cfg_mask} = 24'h021aff;
            7'd37: {cfg_addr,cfg_mask} = 24'h021bff;
            7'd38: {cfg_addr,cfg_mask} = 24'h021c07;
            7'd39: {cfg_addr,cfg_mask} = 24'h0220ff;
            7'd40: {cfg_addr,cfg_mask} = 24'h022103;
            7'd41: {cfg_addr,cfg_mask} = 24'h022207;
            7'd42: {cfg_addr,cfg_mask} = 24'h0224f1;
            7'd43: {cfg_addr,cfg_mask} = 24'h02251f;
            7'd44: {cfg_addr,cfg_mask} = 24'h02261f;
            7'd45: {cfg_addr,cfg_mask} = 24'h0300ff;
            7'd46: {cfg_addr,cfg_mask} = 24'h0301ff;
            7'd47: {cfg_addr,cfg_mask} = 24'h03021f;
            7'd48: {cfg_addr,cfg_mask} = 24'h0304ff;
            7'd49: {cfg_addr,cfg_mask} = 24'h0305ff;
            7'd50: {cfg_addr,cfg_mask} = 24'h03061f;
            7'd51: {cfg_addr,cfg_mask} = 24'h0308ff;
            7'd52: {cfg_addr,cfg_mask} = 24'h0309ff;
            7'd53: {cfg_addr,cfg_mask} = 24'h030a1f;
            7'd54: {cfg_addr,cfg_mask} = 24'h030cff;
            7'd55: {cfg_addr,cfg_mask} = 24'h030dff;
            7'd56: {cfg_addr,cfg_mask} = 24'h030e1f;
            7'd57: {cfg_addr,cfg_mask} = 24'h0310ff;
            7'd58: {cfg_addr,cfg_mask} = 24'h0311ff;
            7'd59: {cfg_addr,cfg_mask} = 24'h03121f;
            7'd60: {cfg_addr,cfg_mask} = 24'h0314ff;
            7'd61: {cfg_addr,cfg_mask} = 24'h0315ff;
            7'd62: {cfg_addr,cfg_mask} = 24'h03161f;
            7'd63: {cfg_addr,cfg_mask} = 24'h0318ff;
            7'd64: {cfg_addr,cfg_mask} = 24'h0319ff;
            7'd65: {cfg_addr,cfg_mask} = 24'h031a1f;
            7'd66: {cfg_addr,cfg_mask} = 24'h031cff;
            7'd67: {cfg_addr,cfg_mask} = 24'h031dff;
            7'd68: {cfg_addr,cfg_mask} = 24'h031e1f;
            7'd69: {cfg_addr,cfg_mask} = 24'h0320ff;
            7'd70: {cfg_addr,cfg_mask} = 24'h0321ff;
            7'd71: {cfg_addr,cfg_mask} = 24'h0322ff;
            7'd72: {cfg_addr,cfg_mask} = 24'h0323ff;
            7'd73: {cfg_addr,cfg_mask} = 24'h0324ff;
            7'd74: {cfg_addr,cfg_mask} = 24'h0325ff;
            7'd75: {cfg_addr,cfg_mask} = 24'h0326ff;
            7'd76: {cfg_addr,cfg_mask} = 24'h0327ff;
            7'd77: {cfg_addr,cfg_mask} = 24'h0328ff;
            7'd78: {cfg_addr,cfg_mask} = 24'h0329ff;
            7'd79: {cfg_addr,cfg_mask} = 24'h032a07;
            7'd80: {cfg_addr,cfg_mask} = 24'h04007f;
            7'd81: {cfg_addr,cfg_mask} = 24'h04017f;
            7'd82: {cfg_addr,cfg_mask} = 24'h04027f;
            7'd83: {cfg_addr,cfg_mask} = 24'h04037f;
            7'd84: {cfg_addr,cfg_mask} = 24'h04047f;
            7'd85: {cfg_addr,cfg_mask} = 24'h04057f;
            7'd86: {cfg_addr,cfg_mask} = 24'h04067f;
            7'd87: {cfg_addr,cfg_mask} = 24'h04077f;
            7'd88: {cfg_addr,cfg_mask} = 24'h04087f;
            7'd89: {cfg_addr,cfg_mask} = 24'h04097f;
            7'd90: {cfg_addr,cfg_mask} = 24'h040a7f;
            7'd91: {cfg_addr,cfg_mask} = 24'h040b7f;
            7'd92: {cfg_addr,cfg_mask} = 24'h040c7f;
            7'd93: {cfg_addr,cfg_mask} = 24'h040d7f;
            7'd94: {cfg_addr,cfg_mask} = 24'h040e7f;
            7'd95: {cfg_addr,cfg_mask} = 24'h040f7f;
            7'd96: {cfg_addr,cfg_mask} = 24'h04107f;
            7'd97: {cfg_addr,cfg_mask} = 24'h04117f;
            7'd98: {cfg_addr,cfg_mask} = 24'h04127f;
            7'd99: {cfg_addr,cfg_mask} = 24'h04137f;
            default: ;
        endcase
    end
    always @(posedge clk) begin
        if (!rst_n || open_session) begin
            state<=IDLE; record<=0; count<=0; addr<=0;
            committed_min<=0; staged_min<=0; committed_config<=0; staged_config<=0;
            committed_half<=0; staged_half<=0; committed_end<=0; staged_end<=0;
            image_version<=0; staged_version<=0;
        end else if(discard_scan) state<=IDLE;
        else case(state)
            IDLE: if(begin_scan) begin
                record<=0; count<=record_count;
                staged_min<=committed_min; staged_config<=committed_config;
                staged_half<=committed_half; staged_end<=committed_end;
                staged_version<=image_version;
                state<=(record_count>=1 && record_count<=8) ? HIGH : REJECTED;
            end
            HIGH: begin addr[15:8]<=read_byte; state<=LOW; end
            LOW: begin addr[7:0]<=read_byte; state<=BYTE_DATA; end
            BYTE_DATA: begin
                if(staged_end || !(instruction_ok || config_ok || version_ok)) state<=REJECTED;
                else begin
                    if(instruction_ok) begin
                        staged_min<={1'b0,addr[5:0]}+1'b1;
                        staged_half<=!staged_half;
                    end else if(config_ok) staged_config<=staged_config+1'b1;
                    else begin staged_end<=1; staged_version<=read_byte; end
                    record<=record+1'b1;
                    state<=record+1'b1==count ? APPROVED : HIGH;
                end
            end
            APPROVED: if(commit_scan) begin
                committed_min<=staged_min; committed_config<=staged_config;
                committed_half<=staged_half; committed_end<=staged_end;
                image_version<=staged_version; state<=IDLE;
            end
            default: ;
        endcase
    end
endmodule
`default_nettype wire
