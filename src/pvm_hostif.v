`timescale 1ns/1ps
`default_nettype none

// Decode SPI frames and drive the single-master byte bus.
// Owner: Kalash Bheda. PVM S05. See 03_BUS_AND_REGMAP.md sections 1 and 2.
module pvm_hostif (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sck,
    input  wire        cs_n,
    input  wire        mosi,
    input  wire [7:0]  bus_rdata,
    output wire [15:0] bus_addr,
    output wire [7:0]  bus_wdata,
    output reg         bus_we,
    output reg         bus_re,
    output reg         bus_rack,
    output wire        miso
);
    localparam [2:0] S_CMD = 3'd0, S_A_HI = 3'd1, S_A_LO = 3'd2,
                     S_WRITE = 3'd3, S_READ_DUMMY = 3'd4, S_READ_DATA = 3'd5,
                     S_ID = 3'd6, S_IGNORE = 3'd7;
    localparam [7:0] CMD_WRITE = 8'h02, CMD_READ = 8'h03, CMD_ID = 8'h9f;

    reg [2:0] state_q, id_index_q;
    reg [15:0] addr_q;
    reg is_read_q, prefetch_q, read_tx_pending_q;
    wire [7:0] rx_byte;
    wire rx_valid, unused_frame_start, unused_frame_end;
    wire read_tx_load, id_tx_load;
    reg [7:0] id_byte;

    pvm_spi_byte spi (
        .clk(clk), .rst_n(rst_n), .sck(sck), .cs_n(cs_n), .mosi(mosi),
        .tx_byte(read_tx_load ? bus_rdata : id_byte),
        .tx_load(!cs_n && (read_tx_load || id_tx_load)),
        .rx_byte(rx_byte), .rx_valid(rx_valid),
        .frame_start(unused_frame_start), .frame_end(unused_frame_end), .miso(miso)
    );

    assign bus_addr = addr_q;
    assign bus_wdata = rx_byte;
    // bus_rdata becomes available after the edge that samples bus_re.
    assign read_tx_load = read_tx_pending_q;
    assign id_tx_load = rx_valid && ((state_q == S_CMD && rx_byte == CMD_ID) || state_q == S_ID);

    always @(*) begin
        id_byte = 8'h00;
        if (state_q == S_CMD)
            id_byte = 8'h50;
        else begin
            case (id_index_q)
                3'd1: id_byte = 8'h56;
                3'd2: id_byte = 8'h4d;
                3'd3: id_byte = 8'h21;
                default: id_byte = 8'h00;
            endcase
        end
    end

    always @(*) begin
        bus_we = 1'b0;
        bus_re = 1'b0;
        bus_rack = 1'b0;
        if (rst_n && !cs_n) begin
            if (prefetch_q || (state_q == S_READ_DUMMY && rx_valid))
                bus_re = 1'b1;
            else if (state_q == S_READ_DATA && rx_valid)
                bus_rack = 1'b1;
            else if (state_q == S_WRITE && rx_valid)
                bus_we = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || cs_n) begin
            state_q <= S_CMD;
            addr_q <= 16'h0000;
            is_read_q <= 1'b0;
            id_index_q <= 3'd0;
            prefetch_q <= 1'b0;
            read_tx_pending_q <= 1'b0;
        end else begin
            prefetch_q <= 1'b0;
            read_tx_pending_q <= bus_re;
            if (rx_valid) begin
                case (state_q)
                    S_CMD: begin
                        case (rx_byte)
                            CMD_WRITE, CMD_READ: begin
                                is_read_q <= rx_byte == CMD_READ;
                                state_q <= S_A_HI;
                            end
                            CMD_ID: begin
                                id_index_q <= 3'd1;
                                state_q <= S_ID;
                            end
                            default: state_q <= S_IGNORE;
                        endcase
                    end
                    S_A_HI: begin
                        addr_q[15:8] <= rx_byte;
                        state_q <= S_A_LO;
                    end
                    S_A_LO: begin
                        addr_q[7:0] <= rx_byte;
                        state_q <= is_read_q ? S_READ_DUMMY : S_WRITE;
                    end
                    S_WRITE: addr_q <= addr_q + 16'd1;
                    S_READ_DUMMY: state_q <= S_READ_DATA;
                    S_READ_DATA: begin
                        // Acknowledge the old address, then prefetch the next one.
                        addr_q <= addr_q + 16'd1;
                        prefetch_q <= 1'b1;
                    end
                    S_ID: begin
                        if (id_index_q < 3'd4)
                            id_index_q <= id_index_q + 3'd1;
                    end
                    S_IGNORE: begin end
                    default: state_q <= S_CMD;
                endcase
            end
        end
    end
endmodule

`default_nettype wire
