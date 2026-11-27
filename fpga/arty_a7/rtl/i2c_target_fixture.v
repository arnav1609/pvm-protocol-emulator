`timescale 1ns/1ps
`default_nettype none

// Open-drain addressed-write responder for the pinned 0xA0, 0x3C demo.
module i2c_target_fixture #(
    parameter integer STRETCH_CLKS = 331
) (
    input wire clk, rst_n, sda, scl,
    output reg sda_low, scl_low
);
    localparam [2:0] WAIT_START = 0, RECEIVE = 1, ACK_SETUP = 2,
                     ACK_RISE = 3, ACK_FALL = 4;
    // The pinned controller lowers SCL for 80 clocks before releasing it
    // for address ACK. The fixture observes the falling pad after 3 clocks.
    localparam integer ACK_HOLD_CLKS = 80 + STRETCH_CLKS - 3;
    localparam integer STRETCH_TIMER_W = $clog2(ACK_HOLD_CLKS+1);
    reg [STRETCH_TIMER_W-1:0] stretch_remaining;
    reg [2:0] phase, bit_index;
    (* ASYNC_REG = "TRUE" *) reg sda_meta, scl_meta, sda_sync, scl_sync;
    reg sda_prev, scl_prev;
    reg [6:0] shift;
    reg address_phase, acknowledge;
    wire scl_rise = scl_sync && !scl_prev;
    wire scl_fall = !scl_sync && scl_prev;
    wire start_condition = scl_sync && scl_prev && sda_prev && !sda_sync;
    wire stop_condition = scl_sync && scl_prev && !sda_prev && sda_sync;
    wire [7:0] incoming = {shift, sda_sync};
    wire matches_demo_byte = address_phase ? incoming == 8'ha0 : incoming == 8'h3c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_meta <= 1;
            scl_meta <= 1;
            sda_sync <= 1;
            scl_sync <= 1;
            sda_prev <= 1;
            scl_prev <= 1;
            phase <= WAIT_START;
            bit_index <= 0;
            address_phase <= 1;
            acknowledge <= 0;
            shift <= 0;
            stretch_remaining <= 0;
            sda_low <= 0;
            scl_low <= 0;
        end else begin
            sda_meta <= sda;
            scl_meta <= scl;
            sda_sync <= sda_meta;
            scl_sync <= scl_meta;
            sda_prev <= sda_sync;
            scl_prev <= scl_sync;

            if (stretch_remaining != 0) begin
                stretch_remaining <= stretch_remaining - 1'b1;
                if (stretch_remaining == 1)
                    scl_low <= 0;
            end

            if (start_condition) begin
                phase <= RECEIVE;
                address_phase <= 1;
                bit_index <= 0;
                acknowledge <= 0;
                sda_low <= 0;
                scl_low <= 0;
                stretch_remaining <= 0;
            end else if (stop_condition) begin
                phase <= WAIT_START;
                sda_low <= 0;
                scl_low <= 0;
                stretch_remaining <= 0;
            end else begin
                case (phase)
                    RECEIVE: if (scl_rise) begin
                        shift <= incoming[6:0];
                        bit_index <= bit_index + 1'b1;
                        if (bit_index == 7) begin
                            // Both accepted bytes end in zero. Hold SDA before
                            // the master releases it for ACK to avoid a high pulse.
                            acknowledge <= matches_demo_byte;
                            sda_low <= matches_demo_byte;
                            phase <= ACK_SETUP;
                        end
                    end
                    ACK_SETUP: if (scl_fall) begin
                        if (acknowledge && address_phase && STRETCH_CLKS > 0) begin
                            scl_low <= 1;
                            stretch_remaining <= ACK_HOLD_CLKS[STRETCH_TIMER_W-1:0];
                        end
                        phase <= ACK_RISE;
                    end
                    ACK_RISE: if (scl_rise)
                        phase <= ACK_FALL;
                    ACK_FALL: if (scl_fall) begin
                        sda_low <= 0;
                        phase <= acknowledge && address_phase ? RECEIVE : WAIT_START;
                        address_phase <= 0;
                    end
                    default: begin
                        sda_low <= 0;
                        scl_low <= 0;
                    end
                endcase
            end
        end
    end
endmodule

`default_nettype wire
