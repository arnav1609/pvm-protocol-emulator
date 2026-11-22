`timescale 1ns/1ps
`default_nettype none

// Resolve pin owners and apply electrical and lifecycle safety before registering outputs.
// Owner: Kalash Bheda. PVM S08. See 02_PINS_AND_TOP.md and 07_FAULTS_LIFECYCLE.md section 4.
module pvm_pin_guard (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [2:0]   state,
    input  wire [139:0] pin_cfg,
    input  wire [19:0]  out_val,
    input  wire [19:0]  oe_val,
    input  wire [3:0]   lut_out,
    input  wire         arb_en,
    input  wire         arb_lost,
    input  wire [4:0]   arb_sda,
    input  wire [4:0]   arb_scl,
    output reg  [6:0]   uo_pins,
    output reg  [7:0]   uio_out,
    output reg  [7:0]   uio_oe,
    output reg  [6:0]   uo_readback,
    output wire [19:0]  od_release_intent
);
    wire running = state == 3'd3;
    wire [6:0] uo_next;
    wire [7:0] uio_next, uio_oe_next;
    genvar p;

    generate
        for (p = 0; p < 20; p = p + 1) begin : pins
            wire [6:0] config_bits = pin_cfg[7*p+:7];
            wire [2:0] owner = config_bits[2:0];
            wire [1:0] mode = config_bits[4:3];
            wire idle = config_bits[5];
            wire invert = config_bits[6];
            wire engine_owner = (owner == 3'd1) || (owner == 3'd2);
            wire fabric_owner = (owner >= 3'd3) && (owner <= 3'd6);
            wire [1:0] lut_index = owner[1:0] - 2'd3;
            wire owner_value = engine_owner ? out_val[p] : (fabric_owner ? lut_out[lut_index] : idle);
            wire owner_enable = fabric_owner || (engine_owner && ((p < 12) || oe_val[p]));
            wire value = owner_value ^ invert;
            wire open_drain = mode == 2'd2;

            assign od_release_intent[p] = running && open_drain && (value || !owner_enable);
            if (p >= 5 && p < 12) begin : dedicated_output
                assign uo_next[p-5] = (running && mode == 2'd1) ? value : idle;
            end
            if (p >= 12) begin : bidirectional
                localparam [4:0] PIN = p[4:0];
                wire push_pull = mode == 2'd1;
                wire arb_block = arb_en && arb_lost && ((PIN == arb_sda) || (PIN == arb_scl));
                assign uio_next[p-12] = running && (push_pull || open_drain) ?
                                       (open_drain ? 1'b0 : value) : 1'b0;
                assign uio_oe_next[p-12] = running && !arb_block && owner_enable &&
                                          (push_pull || (open_drain && !value));
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (!rst_n) begin
            uo_pins <= 7'h00;
            uio_out <= 8'h00;
            uio_oe <= 8'h00;
            uo_readback <= 7'h00;
        end else begin
            uo_pins <= uo_next;
            uio_out <= uio_next;
            uio_oe <= uio_oe_next;
            // Sample the driven pad value for a two-register path to pin_in.
            uo_readback <= uo_pins;
        end
    end
endmodule

`default_nettype wire
