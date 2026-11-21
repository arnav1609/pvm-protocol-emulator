`timescale 1ns/1ps
`default_nettype none

// Shift mode-0 SPI bytes using inputs already synchronized to clk.
// Owner: Kalash Bheda. PVM S04. See 03_BUS_AND_REGMAP.md section 2.
module pvm_spi_byte (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sck,
    input  wire       cs_n,
    input  wire       mosi,
    input  wire [7:0] tx_byte,
    input  wire       tx_load,
    output reg  [7:0] rx_byte,
    output reg        rx_valid,
    output reg        frame_start,
    output reg        frame_end,
    output wire       miso
);
    wire sck_rise, sck_fall;
    wire select_rise, select_fall;
    reg [6:0] rx_shift_q, tx_shift_q;
    reg [2:0] rx_bits_q;
    reg byte_complete_q;
    reg [7:0] tx_pending_q;
    reg tx_pending_valid_q;
    reg miso_q;
    wire [7:0] next_tx_byte;

    pvm_edge sck_edges (
        .clk(clk), .rst_n(rst_n), .d(sck), .rise(sck_rise), .fall(sck_fall)
    );
    // Detect edges of active-high select, whose inactive reset value is zero.
    pvm_edge select_edges (
        .clk(clk), .rst_n(rst_n), .d(~cs_n), .rise(select_rise), .fall(select_fall)
    );

    assign next_tx_byte = tx_load ? tx_byte : (tx_pending_valid_q ? tx_pending_q : 8'h00);
    assign miso = cs_n ? 1'b0 : miso_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_shift_q <= 7'h00;
            tx_shift_q <= 7'h00;
            rx_bits_q <= 3'd0;
            byte_complete_q <= 1'b0;
            tx_pending_q <= 8'h00;
            tx_pending_valid_q <= 1'b0;
            miso_q <= 1'b0;
            rx_byte <= 8'h00;
            rx_valid <= 1'b0;
            frame_start <= 1'b0;
            frame_end <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            frame_start <= select_rise;
            frame_end <= select_fall;
            if (cs_n) begin
                rx_shift_q <= 7'h00;
                tx_shift_q <= 7'h00;
                rx_bits_q <= 3'd0;
                byte_complete_q <= 1'b0;
                tx_pending_valid_q <= 1'b0;
                miso_q <= 1'b0;
            end else begin
                if (tx_load) begin
                    tx_pending_q <= tx_byte;
                    tx_pending_valid_q <= 1'b1;
                end
                if (sck_rise) begin
                    rx_shift_q <= {rx_shift_q[5:0], mosi};
                    rx_bits_q <= rx_bits_q + 3'd1;
                    if (rx_bits_q == 3'd7) begin
                        rx_byte <= {rx_shift_q, mosi};
                        rx_valid <= 1'b1;
                        byte_complete_q <= 1'b1;
                    end
                end
                if (sck_fall) begin
                    if (byte_complete_q) begin
                        // The falling edge between bytes presents the new MSB.
                        miso_q <= next_tx_byte[7];
                        tx_shift_q <= next_tx_byte[6:0];
                        tx_pending_valid_q <= 1'b0;
                        byte_complete_q <= 1'b0;
                    end else begin
                        miso_q <= tx_shift_q[6];
                        tx_shift_q <= {tx_shift_q[5:0], 1'b0};
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
