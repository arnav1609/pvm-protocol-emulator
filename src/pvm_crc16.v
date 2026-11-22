`timescale 1ns/1ps
`default_nettype none

// Accumulate CRC-16/CCITT-FALSE over enabled bytes.
// Owner: Kalash Bheda. PVM S02. See 07_FAULTS_LIFECYCLE.md section 2.
module pvm_crc16 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clr,
    input  wire        en,
    input  wire [7:0]  din,
    output reg  [15:0] crc
);
    function [15:0] accumulate;
        input [15:0] current;
        input [7:0] data;
        reg [15:0] next_crc;
        integer bit_index;
        begin
            next_crc = current ^ {data, 8'h00};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (next_crc[15])
                    next_crc = (next_crc << 1) ^ 16'h1021;
                else
                    next_crc = next_crc << 1;
            end
            accumulate = next_crc;
        end
    endfunction

    wire [15:0] next_crc_byte = accumulate(crc, din);

    always @(posedge clk) begin
        if (!rst_n || clr)
            crc <= 16'hffff;
        else if (en)
            crc <= next_crc_byte;
    end
endmodule

`default_nettype wire
