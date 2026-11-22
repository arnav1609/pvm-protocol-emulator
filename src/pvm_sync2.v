`timescale 1ns/1ps
`default_nettype none

// Synchronize external inputs to clk with two sampling stages.
// Owner: Kalash Bheda. PVM S01. See 02_PINS_AND_TOP.md and STAGE_01.
module pvm_sync2 #(
    parameter integer W = 1,
    parameter [W-1:0] RST_VAL = {W{1'b0}}
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [W-1:0] d,
    output reg  [W-1:0] q
);
    reg [W-1:0] sample_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_q <= RST_VAL;
            q <= RST_VAL;
        end else begin
            sample_q <= d;
            q <= sample_q;
        end
    end
endmodule

`default_nettype wire
