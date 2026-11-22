`timescale 1ns/1ps
`default_nettype none

// Tiny Tapeout wrapper for PVM.
// Owner: Kalash Bheda. PVM S08. See 02_PINS_AND_TOP.md.
module tt_um_arnav1609_pvm (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire unused_ena = ena;

    pvm_top pvm (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in),
        .uio_out(uio_out), .uio_oe(uio_oe), .clk(clk), .rst_n(rst_n)
    );
endmodule

`default_nettype wire
