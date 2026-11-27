`timescale 1ns/1ps
`default_nettype none

// Stop-and-wait host protocol, with UART 115200 8N1 and SPI mode 0.
// 01 length_hi length_lo request[...] -> 00 miso[...].
// 02 -> pulse host_reset_n low, then return 00.
// Invalid op/length/framing or truncated request -> ff, no SPI activity.
module uart_spi_bridge #(
    parameter integer UART_CLKS = 434,
    parameter integer SPI_HALF_CLKS = 100,
    parameter integer RX_TIMEOUT_CLKS = 5_000_000
) (
    input wire clk,
    input wire rst_n,
    input wire uart_rx,
    output wire uart_tx,
    output reg spi_sck,
    output reg spi_cs_n,
    output wire spi_mosi,
    input wire spi_miso,
    output reg host_reset_n
);
    localparam [15:0] MAX_LENGTH = 16'd260;
    localparam integer RESET_CLKS = 32;
    // An idle character interval lets a malformed frame finish arriving.
    localparam integer DRAIN_CLKS = 12 * UART_CLKS;
    localparam [3:0] GET_OP = 0, GET_HI = 1, GET_LO = 2, GET_PAYLOAD = 3,
                     SPI_PREP = 4, SPI_SHIFT = 5, SPI_HOLD = 6, PVM_RESET = 7,
                     SEND_STATUS = 8, SEND_PAYLOAD = 9, WAIT_TX = 10,
                     DRAIN_RX = 11;

    reg [3:0] state;
    reg [8:0] byte_index, length;
    reg [7:0] length_hi, status_byte;
    reg [2:0] bit_index;
    reg [7:0] mosi_shift, miso_shift;
    localparam integer SPI_TIMER_W = $clog2(SPI_HALF_CLKS+1);
    localparam integer SPI_LOAD = SPI_HALF_CLKS - 1;
    localparam integer RESET_TIMER_W = $clog2(RESET_CLKS+1);
    localparam integer RESET_LOAD = RESET_CLKS - 1;
    localparam integer RX_TIMER_MAX =
        RX_TIMEOUT_CLKS > DRAIN_CLKS ? RX_TIMEOUT_CLKS : DRAIN_CLKS;
    localparam integer RX_TIMER_W = $clog2(RX_TIMER_MAX+1);
    reg [SPI_TIMER_W-1:0] spi_ticks;
    reg [RESET_TIMER_W-1:0] reset_ticks;
    reg [RX_TIMER_W-1:0] rx_ticks;

    wire [7:0] rx_byte;
    wire rx_valid, rx_error, rx_busy;
    wire tx_ready;
    wire tx_start = tx_ready && (state == SEND_STATUS || state == SEND_PAYLOAD);
    wire [15:0] proposed_length = {length_hi, rx_byte};
    wire is_last_byte = byte_index + 9'd1 == length;
    wire spi_byte_done = state == SPI_SHIFT && spi_sck && spi_ticks == 0 && bit_index == 0;
    wire [8:0] read_index =
        spi_byte_done && !is_last_byte ? byte_index + 9'd1 : byte_index;
    // Reuse the input storage for output bytes once the byte has been sent.
    reg [7:0] frame_mem [0:MAX_LENGTH-1];
    wire [7:0] frame_data = frame_mem[read_index];
    wire write_request_byte = state == GET_PAYLOAD && rx_valid;
    wire write_memory = write_request_byte || spi_byte_done;
    wire [7:0] write_data = write_request_byte ? rx_byte : miso_shift;
    wire [7:0] tx_data = state == SEND_STATUS ? status_byte : frame_data;
    wire receiving = state == GET_HI || state == GET_LO || state == GET_PAYLOAD;

    assign spi_mosi = mosi_shift[7];

    bridge_uart_rx #(.BIT_CLKS(UART_CLKS)) rx (
        .clk(clk), .rst_n(rst_n), .serial_in(uart_rx),
        .data(rx_byte), .valid(rx_valid), .framing_error(rx_error), .busy(rx_busy)
    );
    bridge_uart_tx #(.BIT_CLKS(UART_CLKS)) tx (
        .clk(clk), .rst_n(rst_n), .start(tx_start), .data(tx_data),
        .serial_out(uart_tx), .ready(tx_ready)
    );

    always @(posedge clk) begin
        if (rst_n && write_memory)
            frame_mem[byte_index] <= write_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= GET_OP;
            byte_index <= 0;
            length <= 0;
            length_hi <= 0;
            status_byte <= 0;
            bit_index <= 0;
            mosi_shift <= 0;
            miso_shift <= 0;
            spi_ticks <= 0;
            reset_ticks <= 0;
            rx_ticks <= 0;
            spi_sck <= 0;
            spi_cs_n <= 1;
            host_reset_n <= 1;
        end else if ((receiving || state == GET_OP) && rx_error) begin
            length <= 0;
            status_byte <= 8'hff;
            rx_ticks <= DRAIN_CLKS[RX_TIMER_W-1:0];
            state <= DRAIN_RX;
        end else if (receiving && rx_ticks == 0 && !rx_valid && !rx_busy) begin
            length <= 0;
            status_byte <= 8'hff;
            state <= SEND_STATUS;
        end else begin
            if (receiving) begin
                if (rx_busy || rx_valid)
                    rx_ticks <= RX_TIMEOUT_CLKS[RX_TIMER_W-1:0];
                else if (rx_ticks != 0)
                    rx_ticks <= rx_ticks - 1'b1;
            end
            case (state)
                GET_OP: if (rx_valid) begin
                    length <= 0;
                    byte_index <= 0;
                    status_byte <= 0;
                    if (rx_byte == 8'h01) begin
                        rx_ticks <= RX_TIMEOUT_CLKS[RX_TIMER_W-1:0];
                        state <= GET_HI;
                    end else if (rx_byte == 8'h02) begin
                        host_reset_n <= 0;
                        reset_ticks <= RESET_LOAD[RESET_TIMER_W-1:0];
                        state <= PVM_RESET;
                    end else begin
                        status_byte <= 8'hff;
                        rx_ticks <= DRAIN_CLKS[RX_TIMER_W-1:0];
                        state <= DRAIN_RX;
                    end
                end
                GET_HI: if (rx_valid) begin
                    length_hi <= rx_byte;
                    state <= GET_LO;
                end
                GET_LO: if (rx_valid) begin
                    if (proposed_length != 0 && proposed_length <= MAX_LENGTH) begin
                        length <= proposed_length[8:0];
                        state <= GET_PAYLOAD;
                    end else begin
                        status_byte <= 8'hff;
                        rx_ticks <= DRAIN_CLKS[RX_TIMER_W-1:0];
                        state <= DRAIN_RX;
                    end
                end
                GET_PAYLOAD: if (rx_valid) begin
                    if (is_last_byte) begin
                        byte_index <= 0;
                        state <= SPI_PREP;
                    end else
                        byte_index <= byte_index + 1'b1;
                end
                SPI_PREP: begin
                    mosi_shift <= frame_data;
                    miso_shift <= 0;
                    bit_index <= 7;
                    spi_cs_n <= 0;
                    spi_ticks <= SPI_LOAD[SPI_TIMER_W-1:0];
                    state <= SPI_SHIFT;
                end
                SPI_SHIFT: begin
                    if (spi_ticks != 0)
                        spi_ticks <= spi_ticks - 1'b1;
                    else begin
                        spi_ticks <= SPI_LOAD[SPI_TIMER_W-1:0];
                        spi_sck <= !spi_sck;
                        if (!spi_sck) begin
                            miso_shift <= {miso_shift[6:0], spi_miso};
                        end else if (bit_index != 0) begin
                            mosi_shift <= {mosi_shift[6:0], 1'b0};
                            bit_index <= bit_index - 1'b1;
                        end else if (is_last_byte) begin
                            state <= SPI_HOLD;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                            mosi_shift <= frame_data;
                            bit_index <= 7;
                        end
                    end
                end
                SPI_HOLD: begin
                    if (spi_ticks != 0)
                        spi_ticks <= spi_ticks - 1'b1;
                    else begin
                        spi_cs_n <= 1;
                        mosi_shift <= 0;
                        byte_index <= 0;
                        state <= SEND_STATUS;
                    end
                end
                PVM_RESET: begin
                    if (reset_ticks != 0)
                        reset_ticks <= reset_ticks - 1'b1;
                    else begin
                        host_reset_n <= 1;
                        state <= SEND_STATUS;
                    end
                end
                SEND_STATUS: if (tx_ready)
                    state <= length == 0 ? WAIT_TX : SEND_PAYLOAD;
                SEND_PAYLOAD: if (tx_ready) begin
                    if (is_last_byte)
                        state <= WAIT_TX;
                    else
                        byte_index <= byte_index + 1'b1;
                end
                WAIT_TX: if (tx_ready)
                    state <= GET_OP;
                DRAIN_RX: begin
                    if (rx_busy || rx_valid || rx_error)
                        rx_ticks <= DRAIN_CLKS[RX_TIMER_W-1:0];
                    else if (rx_ticks != 0)
                        rx_ticks <= rx_ticks - 1'b1;
                    else
                        state <= SEND_STATUS;
                end
                default: state <= GET_OP;
            endcase
        end
    end
endmodule

module bridge_uart_rx #(parameter integer BIT_CLKS = 434) (
    input wire clk, rst_n, serial_in,
    output reg [7:0] data,
    output reg valid, framing_error,
    output wire busy
);
    localparam [1:0] IDLE = 0, START_BIT = 1, DATA_BITS = 2, STOP_BIT = 3;
    localparam integer TIMER_W = $clog2(BIT_CLKS+1);
    localparam integer HALF_LOAD = BIT_CLKS / 2 - 1;
    localparam integer BIT_LOAD = BIT_CLKS - 1;
    reg [1:0] state;
    (* ASYNC_REG = "TRUE" *) reg rx_meta, rx_sync;
    reg [2:0] bit_index;
    reg [TIMER_W-1:0] ticks;
    reg [7:0] shift;
    assign busy = state != IDLE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1;
            rx_sync <= 1;
            state <= IDLE;
            ticks <= 0;
            bit_index <= 0;
            shift <= 0;
            data <= 0;
            valid <= 0;
            framing_error <= 0;
        end else begin
            rx_meta <= serial_in;
            rx_sync <= rx_meta;
            valid <= 0;
            framing_error <= 0;
            if (state == IDLE) begin
                if (!rx_sync) begin
                    ticks <= HALF_LOAD[TIMER_W-1:0];
                    state <= START_BIT;
                end
            end else if (ticks != 0) begin
                ticks <= ticks - 1'b1;
            end else begin
                ticks <= BIT_LOAD[TIMER_W-1:0];
                case (state)
                    START_BIT: begin
                        bit_index <= 0;
                        state <= rx_sync ? IDLE : DATA_BITS;
                    end
                    DATA_BITS: begin
                        shift <= {rx_sync, shift[7:1]};
                        bit_index <= bit_index + 1'b1;
                        if (bit_index == 3'd7)
                            state <= STOP_BIT;
                    end
                    STOP_BIT: begin
                        state <= IDLE;
                        if (rx_sync) begin
                            data <= shift;
                            valid <= 1;
                        end else
                            framing_error <= 1;
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule

module bridge_uart_tx #(parameter integer BIT_CLKS = 434) (
    input wire clk, rst_n, start,
    input wire [7:0] data,
    output wire serial_out, ready
);
    localparam integer TIMER_W = $clog2(BIT_CLKS+1);
    localparam integer BIT_LOAD = BIT_CLKS - 1;
    reg [9:0] shift;
    reg [3:0] remaining;
    reg [TIMER_W-1:0] ticks;
    assign ready = remaining == 0;
    assign serial_out = shift[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift <= 10'h3ff;
            remaining <= 0;
            ticks <= 0;
        end else if (ready) begin
            if (start) begin
                shift <= {1'b1, data, 1'b0};
                remaining <= 10;
                ticks <= BIT_LOAD[TIMER_W-1:0];
            end
        end else if (ticks != 0) begin
            ticks <= ticks - 1'b1;
        end else begin
            shift <= {1'b1, shift[9:1]};
            remaining <= remaining - 1'b1;
            ticks <= BIT_LOAD[TIMER_W-1:0];
        end
    end
endmodule

`default_nettype wire
