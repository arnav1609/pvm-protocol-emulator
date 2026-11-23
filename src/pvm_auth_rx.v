`timescale 1ns/1ps
`default_nettype none

// Complete-frame adapter for the existing SPI byte shifter.
// Hold frame_valid and the frame stable until release_frame. Host must poll INFO.
module pvm_auth_rx (
    input wire clk, rst_n,
    input wire frame_start, frame_end, frame_byte_aligned,
    input wire rx_valid,
    input wire [7:0] rx_byte,
    input wire accept_submit, release_frame,
    output reg frame_valid,
    output wire [7:0] body_length,
    input wire [7:0] read_index,
    output wire [7:0] read_byte
);
    reg [7:0] bytes [0:152];
    reg [7:0] count, payload_count;
    reg capturing, malformed;
    assign body_length = 8'd64 + payload_count;
    assign read_byte = frame_valid && read_index < count ? bytes[read_index] : 8'd0;
    always @(posedge clk) begin
        if (!rst_n) begin
            count <= 0;
            payload_count <= 0;
            capturing <= 0;
            malformed <= 0;
            frame_valid <= 0;
        end else if (frame_valid) begin
            if (release_frame) frame_valid <= 0;
        end else if (frame_start) begin
            count <= 0;
            payload_count <= 0;
            malformed <= 0;
            capturing <= accept_submit;
        end else if (frame_end) begin
            if (capturing && frame_byte_aligned && !malformed &&
                count == 8'd97 + payload_count)
                frame_valid <= 1;
            capturing <= 0;
        end else if (capturing && rx_valid) begin
            if (count == 153 || (count == 0 && rx_byte != 8'ha0))
                malformed <= 1;
            else if (!malformed) begin
                bytes[count] <= rx_byte;
                count <= count + 1'b1;
                if (count == 64) begin
                    payload_count <= rx_byte;
                    if (rx_byte > 56) malformed <= 1;
                end
            end
        end
    end
endmodule

`default_nettype wire
