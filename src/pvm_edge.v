`timescale 1ns/1ps
`default_nettype none

// Report transitions on a signal already synchronous to clk.
// Owner: Kalash Bheda. PVM S01. See STAGE_01 sections 2 and 5.
module pvm_edge (
    input  wire clk,
    input  wire rst_n,
    input  wire d,
    output wire rise,
    output wire fall
);
    reg d_q;

    always @(posedge clk) begin
        if (!rst_n)
            d_q <= 1'b0;
        else
            d_q <= d;
    end

    assign rise = d & ~d_q;
    assign fall = ~d & d_q;
endmodule

`default_nettype wire
