`timescale 1ns/1ps
`default_nettype none

// Generate a synchronous enable every max(div, 1) clocks.
// Owner: Kalash Bheda. PVM S01. See STAGE_01 sections 2 and 5.
module pvm_tick (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        run,
    input  wire        restart,
    input  wire [15:0] div,
    output wire        tick
);
    reg [15:0] elapsed_q;
    wire last_cycle;

    // A consumer samples tick on the rising edge that ends the period.
    assign last_cycle = (div == 16'd0) || (elapsed_q == div - 16'd1);
    assign tick = rst_n && run && !restart && last_cycle;

    always @(posedge clk) begin
        if (!rst_n || !run || restart || last_cycle)
            elapsed_q <= 16'd0;
        else
            elapsed_q <= elapsed_q + 16'd1;
    end
endmodule

`default_nettype wire
