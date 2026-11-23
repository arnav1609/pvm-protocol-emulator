`timescale 1ns/1ps
`default_nettype none

// Sole effect issuer. All frame bytes are held stable until complete.
// Controller must preflight the whole chunk, compare CRC_CALC before FINISH,
// and qualify policy issue. bus_rdata is registered by pvm_cfg on bus_re.
module pvm_auth_bus (
    input wire clk, rst_n, abort_session,
    input wire issue, finish_crc_bad,
    input wire [7:0] op,
    input wire [2:0] pvm_state,
    input wire [3:0] record_count,
    input wire [2:0] fifo_count,
    input wire [15:0] expected_crc,
    input wire [7:0] image_version,
    input wire [31:0] preload,
    output reg [7:0] frame_index,
    input wire [7:0] frame_byte, bus_rdata,
    output reg [15:0] bus_addr,
    output reg [7:0] bus_wdata,
    output reg bus_we, bus_re, bus_rack,
    output reg complete, success, busy,
    output reg [31:0] rx_result,
    output reg [2:0] rx_length
);
    localparam IDLE=0, HALT=1, CLEAR=2, ADDR_HI=3, ADDR_LO=4, RECORD=5,
               CRC_LO=6, CRC_HI=7, VALIDATE=8, WAIT_READY=9,
               ID_LO=10, ID_LO_CHECK=11, ID_HI=12, ID_HI_CHECK=13,
               ID_VER=14, ID_VER_CHECK=15, PRELOAD=16, START=17,
               PUSH=18, POP_READ=19, POP_ACK=20, FLAGS=21, FAIL_STOP=22,
               CHECK_CHUNK=23, CHECK_CHUNK_DATA=24, CHECK_READY=25, CHECK_READY_DATA=26;
    reg [4:0] state;
    reg [3:0] record_index;
    reg [2:0] fifo_index;
    reg [5:0] timeout_count;
    reg [7:0] current_op;
    reg [15:0] record_addr;
    wire [7:0] record_base = 8'd65 + {4'd0,record_index} +
                            {3'd0,record_index,1'b0};

    always @* begin
        frame_index=0;
        bus_addr=16'h0f00;
        bus_wdata=0;
        bus_we=0;
        bus_re=0;
        bus_rack=0;
        if (rst_n) begin
            if (abort_session || state==FAIL_STOP || state==HALT) begin
                bus_we=1; bus_wdata=1;
            end else case (state)
                CLEAR: begin bus_we=1; bus_wdata=4; end
                ADDR_HI: frame_index=record_base;
                ADDR_LO: frame_index=record_base+1'b1;
                RECORD: begin
                    frame_index=record_base+2'd2;
                    bus_addr=record_addr; bus_we=1; bus_wdata=frame_byte;
                end
                CRC_LO: begin bus_addr=16'h0f08; bus_we=1; bus_wdata=expected_crc[7:0]; end
                CRC_HI: begin bus_addr=16'h0f09; bus_we=1; bus_wdata=expected_crc[15:8]; end
                VALIDATE: begin bus_we=1; bus_wdata=2; end
                ID_LO: begin bus_addr=16'h0f20; bus_re=1; end
                ID_HI: begin bus_addr=16'h0f21; bus_re=1; end
                ID_VER: begin bus_addr=16'h0f22; bus_re=1; end
                PRELOAD: begin
                    bus_addr=16'h0f10; bus_we=1;
                    bus_wdata=preload >> {fifo_index[1:0],3'b000};
                end
                START: begin bus_we=pvm_state==2; bus_wdata=3; end
                PUSH: begin
                    frame_index=8'd65+fifo_index;
                    bus_addr=16'h0f10; bus_we=1; bus_wdata=frame_byte;
                end
                POP_READ: begin bus_addr=16'h0f11; bus_re=1; end
                POP_ACK: begin bus_addr=16'h0f11; bus_rack=1; end
                FLAGS: begin bus_we=1; bus_wdata=6; end
                CHECK_CHUNK, CHECK_READY: begin bus_addr=16'h0f01; bus_re=1; end
                default: ;
            endcase
        end
    end

    task finish;
        input ok;
        begin state<=IDLE; busy<=0; complete<=1; success<=ok; end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; record_index<=0; fifo_index<=0; timeout_count<=0;
            current_op<=0; record_addr<=0; complete<=0; success<=0; busy<=0;
            rx_result<=0; rx_length<=0;
        end else begin
            complete<=0;
            if (abort_session) begin
                if (busy) finish(0);
                rx_result<=0; rx_length<=0;
            end else case (state)
                IDLE: if (issue) begin
                    busy<=1;
                    current_op<=op;
                    record_index<=0; fifo_index<=0; timeout_count<=0;
                    case (op)
                        1,5: begin state<=HALT; rx_result<=0; rx_length<=0; end
                        2: state<=ADDR_HI;
                        3: if (finish_crc_bad) state<=FAIL_STOP; else state<=CRC_LO;
                        4: state<=START;
                        6: state<=PUSH;
                        7: begin state<=POP_READ; rx_result<=0; rx_length<=0; end
                        8: state<=FLAGS;
                        default: state<=FAIL_STOP;
                    endcase
                end
                HALT: if (current_op==1) state<=CLEAR; else finish(1);
                CLEAR: finish(1);
                ADDR_HI: begin record_addr[15:8]<=frame_byte; state<=ADDR_LO; end
                ADDR_LO: begin record_addr[7:0]<=frame_byte; state<=RECORD; end
                RECORD: begin
                    record_index<=record_index+1'b1;
                    if (record_index+1'b1==record_count) state<=CHECK_CHUNK;
                    else state<=ADDR_HI;
                end
                CHECK_CHUNK: state<=CHECK_CHUNK_DATA;
                CHECK_CHUNK_DATA: if (bus_rdata[3]) state<=FAIL_STOP; else finish(1);
                CRC_LO: state<=CRC_HI;
                CRC_HI: state<=VALIDATE;
                VALIDATE: state<=WAIT_READY;
                WAIT_READY: begin
                    timeout_count<=timeout_count+1'b1;
                    if (pvm_state==2) state<=CHECK_READY;
                    else if (pvm_state==5 || timeout_count==63) state<=FAIL_STOP;
                end
                CHECK_READY: state<=CHECK_READY_DATA;
                CHECK_READY_DATA:
                    if (bus_rdata[6:0]==7'h42) state<=ID_LO; else state<=FAIL_STOP;
                ID_LO: state<=ID_LO_CHECK;
                ID_LO_CHECK: state<=bus_rdata==expected_crc[7:0] ? ID_HI : FAIL_STOP;
                ID_HI: state<=ID_HI_CHECK;
                ID_HI_CHECK: state<=bus_rdata==expected_crc[15:8] ? ID_VER : FAIL_STOP;
                ID_VER: state<=ID_VER_CHECK;
                ID_VER_CHECK: begin
                    if (bus_rdata!=image_version) state<=FAIL_STOP;
                    else if (fifo_count!=0) state<=PRELOAD;
                    else finish(1);
                end
                PRELOAD,PUSH,POP_ACK: begin
                    if (state==POP_ACK) begin
                        rx_result[8*fifo_index[1:0]+:8]<=bus_rdata;
                        rx_length<=fifo_index+1'b1;
                    end
                    fifo_index<=fifo_index+1'b1;
                    if (fifo_index+1'b1==fifo_count) finish(1);
                    else if (state==POP_ACK) state<=POP_READ;
                end
                POP_READ: state<=POP_ACK;
                START: if (pvm_state==2) finish(1); else state<=FAIL_STOP;
                FLAGS: finish(1);
                FAIL_STOP: finish(0);
                default: state<=FAIL_STOP;
            endcase
        end
    end
endmodule
`default_nettype wire
