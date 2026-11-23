`timescale 1ns/1ps
`default_nettype none

// Secure SPI front end. INFO is snapshotted at CS assertion. Public reads
// request one allowlisted bus byte and have no access to read acknowledgments.
module pvm_auth_spi (
    input wire clk, rst_n, sck, cs_n, mosi,
    output wire miso,
    output wire frame_start, frame_end, frame_byte_aligned, rx_valid,
    output wire [7:0] rx_byte,
    input wire [591:0] info,
    input wire [7:0] bus_rdata,
    output wire [15:0] safe_addr,
    output wire safe_read,
    input wire safe_read_grant
);
    localparam [2:0] CMD=0, ID=1, INFO_DUMMY=2, INFO_DATA=3, SAFE_HI=4,
                     SAFE_LO=5, SAFE_DUMMY=6, IGNORE=7;
    reg [2:0] state;
    reg [6:0] index;
    reg [15:0] addr;
    reg [591:0] snapshot;
    reg safe_pending;
    reg [7:0] tx_byte;
    reg tx_load;

    assign safe_addr = addr;
    assign safe_read = rst_n && !cs_n && state==SAFE_DUMMY && rx_valid && readable(addr);

    function readable;
        input [15:0] address;
        begin
            readable=(address>=16'h0f01 && address<=16'h0f05) ||
                     address==16'h0f0b || address==16'h0f0c || address==16'h0f12 ||
                     (address>=16'h0f20 && address<=16'h0f22) ||
                     (address>=16'h0330 && address<=16'h0336) ||
                     (address>=16'h0f80 && address<=16'h0f9f && address[2:0]<=4) ||
                     address==16'h0fa0;
        end
    endfunction

    pvm_spi_byte spi (
        .clk(clk),.rst_n(rst_n),.sck(sck),.cs_n(cs_n),.mosi(mosi),
        .tx_byte(tx_byte),.tx_load(tx_load && !cs_n),.rx_byte(rx_byte),.rx_valid(rx_valid),
        .frame_start(frame_start),.frame_end(frame_end),.frame_byte_aligned(frame_byte_aligned),.miso(miso)
    );

    always @* begin
        tx_byte=0;
        tx_load=0;
        if (safe_pending) begin
            tx_byte=bus_rdata;
            tx_load=1;
        end else if (rx_valid) begin
            case (state)
                CMD: if (rx_byte==8'h9f) begin tx_byte=8'h50; tx_load=1; end
                ID: begin
                    tx_load=1;
                    case (index)
                        1: tx_byte=8'h56;
                        2: tx_byte=8'h4d;
                        3: tx_byte=8'h21;
                        default: ;
                    endcase
                end
                INFO_DUMMY,INFO_DATA: begin
                    tx_load=1;
                    if (index<74) tx_byte=snapshot[8*index+:8];
                end
                default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) snapshot<=0;
        else if (frame_start) snapshot<=info;
        if (!rst_n || cs_n) begin
            state<=CMD;
            index<=0;
            addr<=0;
            safe_pending<=0;
        end else begin
            safe_pending<=safe_read_grant;
            if (rx_valid) begin
                case (state)
                    CMD: case (rx_byte)
                        8'h9f: begin state<=ID; index<=1; end
                        8'ha1: begin state<=INFO_DUMMY; index<=0; end
                        8'ha2: state<=SAFE_HI;
                        default: state<=IGNORE;
                    endcase
                    ID: if (index<4) index<=index+1'b1;
                    INFO_DUMMY,INFO_DATA: begin
                        state<=INFO_DATA;
                        if (index<74) index<=index+1'b1;
                    end
                    SAFE_HI: begin addr[15:8]<=rx_byte; state<=SAFE_LO; end
                    SAFE_LO: begin addr[7:0]<=rx_byte; state<=SAFE_DUMMY; end
                    SAFE_DUMMY: state<=IGNORE;
                    default: ;
                endcase
            end
        end
    end
endmodule

`default_nettype wire
