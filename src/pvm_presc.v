`timescale 1ns/1ps
`default_nettype none

// Generate a synchronous enable at a fixed power-of-sixteen division.
// Owner: Kalash Bheda. PVM S01. See STAGE_01 sections 2 and 5.
module pvm_presc (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       run,
    input  wire       restart,
    input  wire [1:0] sel,
    output wire       en
);
    reg [11:0] elapsed_q;
    reg last_cycle;

    // The low bits mark each selected period without another counter.
    always @(*) begin
        case (sel)
            2'd0: last_cycle = 1'b1;
            2'd1: last_cycle = &elapsed_q[3:0];
            2'd2: last_cycle = &elapsed_q[7:0];
            2'd3: last_cycle = &elapsed_q;
            default: last_cycle = 1'b0;
        endcase
    end

    assign en = rst_n && run && !restart && last_cycle;

    always @(posedge clk) begin
        if (!rst_n || !run || restart)
            elapsed_q <= 12'd0;
        else
            elapsed_q <= elapsed_q + 12'd1;
    end
endmodule

`default_nettype wire
