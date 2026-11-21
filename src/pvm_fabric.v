`timescale 1ns/1ps
`default_nettype none

// S12 PINFABRIC. See 05_FABRIC.md, D-001, D-002, and D-006.
// LUT n: cfg_lut[32*n+:32] = {SEL3,SEL2,SEL1,SEL0,TT[15:0]}.
// Its GROUP and output mode occupy cfg_mode[3*n+:3].
module pvm_fabric (
    input  wire         clk, rst_n, run, enable_pulse, engine_tick,
    input  wire [19:0]  pin_in, od_release_intent,
    input  wire [3:0]   fab_ctrl,
    input  wire         fab_wr,
    input  wire [127:0] cfg_lut,
    input  wire [11:0]  cfg_mode,
    input  wire [9:0]   cnt_reload,
    input  wire         cnt_en, cnt_src, manch_en,
    input  wire         arb_en,
    input  wire [3:0]   arb_n,
    input  wire [4:0]   arb_sda, arb_scl,
    input  wire         clr_flags, evt_clr_arb, evt_clr_unf,
    output wire [3:0]   lut_out,
    output reg          cnt_phase, arb_lost, underrun
);
    reg [9:0] cnt;
    reg hold_bit, hold_valid, act_bit;
    reg [3:0] scl_hi_cnt;
    wire advance = run && cnt_en && (!cnt_src || engine_tick);
    wire terminal = advance && cnt == 10'd0;
    wire bit_boundary = terminal && cnt_phase;
    wire [3:0] fab_in = {fab_ctrl[3:1], manch_en ? act_bit : fab_ctrl[0]};
    wire scl_high = pin_in[arb_scl];
    wire arb_detect = run && arb_en && scl_high && scl_hi_cnt >= arb_n &&
                      od_release_intent[arb_sda] && !pin_in[arb_sda];

    genvar n;
    generate
        for (n = 0; n < 4; n = n + 1) begin : cells
            wire [2:0] mode = cfg_mode[n*3+:3];
            wire [7:0] group_pins = mode[2] ? {pin_in[14:12], pin_in[4:0]} : pin_in[19:12];
            wire [15:0] sources;
            wire [15:0] table_bits = cfg_lut[n*32+:16];
            wire [15:0] selectors = cfg_lut[n*32+16+:16];
            wire [3:0] address = {sources[selectors[15:12]], sources[selectors[11:8]],
                                  sources[selectors[7:4]], sources[selectors[3:0]]};
            wire f = table_bits[address];
            reg value_q, previous_q;
            reg [2:0] history_q;

            if (n < 2) begin : layer1
                assign sources = {arb_lost, cnt_phase, 1'b1, 1'b0, fab_in, group_pins};
            end else begin : layer2
                assign sources = {1'b0, cnt_phase, lut_out[1:0], fab_in, group_pins};
            end
            assign lut_out[n] = value_q;

            always @(posedge clk) begin
                if (!rst_n || !run || enable_pulse) begin
                    value_q <= 1'b0;
                    previous_q <= 1'b0;
                    history_q <= 3'd0;
                end else begin
                    previous_q <= f;
                    history_q <= {history_q[1:0], f};
                    case (mode[1:0])
                        2'd0: value_q <= f;
                        2'd1: value_q <= f && !previous_q;
                        2'd2: value_q <= (history_q[2] && history_q[1]) ||
                                         (history_q[2] && history_q[0]) ||
                                         (history_q[1] && history_q[0]);
                        default: value_q <= 1'b0;
                    endcase
                end
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (!rst_n || !run) begin
            cnt <= 10'd0;
            cnt_phase <= 1'b0;
        end else if (enable_pulse) begin
            cnt <= cnt_reload;
            cnt_phase <= 1'b0;
        end else if (advance) begin
            if (terminal) begin
                cnt <= cnt_reload;
                cnt_phase <= !cnt_phase;
            end else
                cnt <= cnt - 10'd1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || !run || enable_pulse) begin
            act_bit <= 1'b0;
            hold_bit <= 1'b0;
            hold_valid <= 1'b0;
        end else if (manch_en) begin
            if (bit_boundary && hold_valid)
                act_bit <= hold_bit;
            // A write at a boundary queues the next bit while the existing bit is consumed.
            if (fab_wr) begin
                hold_bit <= fab_ctrl[0];
                hold_valid <= 1'b1;
            end else if (bit_boundary)
                hold_valid <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || !run || enable_pulse || !arb_en || !scl_high)
            scl_hi_cnt <= 4'd0;
        else if (!(&scl_hi_cnt))
            scl_hi_cnt <= scl_hi_cnt + 4'd1;

        // Evidence flags have their own clear events and are readable after DONE or FAULT.
        if (!rst_n || clr_flags || evt_clr_arb)
            arb_lost <= 1'b0;
        else if (!enable_pulse && arb_detect)
            arb_lost <= 1'b1;

        if (!rst_n || clr_flags || evt_clr_unf)
            underrun <= 1'b0;
        else if (!enable_pulse && manch_en && bit_boundary && !hold_valid)
            underrun <= 1'b1;
    end
endmodule

`default_nettype wire
