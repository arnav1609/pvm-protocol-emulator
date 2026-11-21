`timescale 1ns/1ps
`default_nettype none

// S13 SPECMON. See 06_MONITOR.md and the log format in 03_BUS_AND_REGMAP.md.
// Pad time error is bounded by 2T + skew for pulses >= 2T if the synchronizer
// resolves in one cycle. The toolchain sets the margin in monitor timer units.
module pvm_mon (
    input  wire         clk, rst_n, run, halt_clr,
    input  wire [19:0]  pin_in,
    input  wire [3:0]   lut_out,
    input  wire         arb_lost, underrun,
    input  wire [7:2]   user_flags,
    input  wire [191:0] cfg_entries,
    input  wire [63:0]  cfg_k,
    input  wire [15:0]  cfg_m,
    input  wire         mon_en,
    input  wire [1:0]   presc,
    output reg  [2:0]   mon_state,
    output reg  [15:0]  cnt_pass, cnt_viol, cnt_inc,
    output wire [159:0] log_flat,
    output reg  [1:0]   log_wptr,
    output reg  [5:0]   log_total
);
    localparam [1:0] MEASURE = 2'd0, PASS = 2'd1, VIOLATION = 2'd2, INCONCLUSIVE = 2'd3;
    reg active_q, ovf;
    reg [15:0] t, tstamp;
    wire active = run && mon_en;
    wire start = active && !active_q;
    wire men;
    wire [31:0] sources = {user_flags, underrun, arb_lost, lut_out, pin_in};
    wire [7:0] matching_rules, selected;
    wire [3:0] less_than_k;
    wire [2:0] targets [0:7];
    wire [2:0] actions [0:7];
    wire [1:0] rule_k [0:7];
    reg [2:0] rule, target, action;
    reg [1:0] sel_k, verdict_min, verdict_max, verdict;
    reg [15:0] limit;
    wire [16:0] t_plus_m = {1'b0, t} + {1'b0, cfg_m};
    wire [16:0] t_minus_m = {1'b0, t} - {1'b0, cfg_m};
    integer i;
    genvar k, e, slot;

    assign selected[0] = matching_rules[0];

    pvm_presc timebase (
        .clk(clk), .rst_n(rst_n), .run(active), .restart(start || halt_clr),
        .sel(presc), .en(men)
    );

    generate
        for (k = 0; k < 4; k = k + 1) begin : thresholds
            // Guards need t<K for every K; verdict bounds are formed once for the firing rule (opt O1).
            assign less_than_k[k] = t < cfg_k[k*16+:16];
        end
        for (e = 0; e < 8; e = e + 1) begin : rules
            wire [23:0] entry = cfg_entries[e*24+:24];
            wire [4:0] source_id = entry[12:8];
            wire [1:0] k_idx = entry[17:16];
            wire now_high = sources[source_id];
            // opt O2: one history flop per entry instead of 32 shared ones (config is fixed in RUN).
            reg prev_high;
            always @(posedge clk)
                if (!rst_n) prev_high <= 1'b0;
                else prev_high <= now_high;
            wire event_match = entry[7] ? (entry[6] ? !now_high : now_high) :
                               entry[6] ? (prev_high && !now_high) : (!prev_high && now_high);
            wire guard_match = entry[14:13] == 2'd0 ||
                               (entry[14:13] == 2'd1 && less_than_k[k_idx]) ||
                               (entry[14:13] == 2'd2 && !less_than_k[k_idx]);
            assign matching_rules[e] = entry[15] && entry[2:0] == mon_state && event_match && guard_match;
            if (e > 0) begin : priority_mask
                assign selected[e] = matching_rules[e] && !(|matching_rules[e-1:0]);
            end
            assign targets[e] = entry[5:3];
            assign actions[e] = entry[20:18];
            assign rule_k[e] = k_idx;
        end
    endgenerate

    always @(*) begin
        rule = 3'd0;
        target = 3'd0;
        action = 3'd0;
        sel_k = 2'd0;
        for (i = 0; i < 8; i = i + 1) begin
            if (selected[i]) begin
                rule = rule | i[2:0];
                target = target | targets[i];
                action = action | actions[i];
                sel_k = sel_k | rule_k[i];
            end
        end
        // opt O1b: t+M and t-M do not depend on the rule, so they run in parallel with
        // rule matching; only the K mux and one comparison follow the selection.
        limit = cfg_k[sel_k*16+:16];
        verdict_min = (ovf && limit > ~cfg_m) ? INCONCLUSIVE :
                      (!t_minus_m[16] && t_minus_m[15:0] >= limit) ? PASS :
                      (t_plus_m < {1'b0, limit}) ? VIOLATION : INCONCLUSIVE;
        verdict_max = (ovf && limit >= ~cfg_m) ? INCONCLUSIVE :
                      (t_plus_m <= {1'b0, limit}) ? PASS :
                      (!t_minus_m[16] && t_minus_m[15:0] > limit) ? VIOLATION : INCONCLUSIVE;
        case (action)
            3'd2: verdict = verdict_min;
            3'd3: verdict = verdict_max;
            3'd5: verdict = VIOLATION;
            3'd6: verdict = PASS;
            default: verdict = MEASURE;
        endcase
    end

    wire fire = active && !start && |selected;
    wire log_event = fire && action >= 3'd2 && action <= 3'd6;
    wire reset_timer = fire && (action == 3'd1 || log_event);
    wire [39:0] log_entry = {tstamp, t, 2'b00, ovf, verdict, rule};

    generate
        for (slot = 0; slot < 4; slot = slot + 1) begin : log_slots
            reg [39:0] entry_q;
            assign log_flat[40*slot+:40] = entry_q;
            always @(posedge clk) begin
                if (!rst_n || halt_clr)
                    entry_q <= 40'd0;
                else if (log_event && log_wptr == slot[1:0])
                    entry_q <= log_entry;
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (!rst_n) begin
            tstamp <= 16'd0;
        end else begin
            if (men)
                tstamp <= tstamp + 16'd1;
        end
        active_q <= rst_n && !halt_clr && active;
        if (!rst_n || halt_clr || start) begin
            mon_state <= 3'd0;
            t <= 16'd0;
            ovf <= 1'b0;
        end else begin
            if (fire)
                mon_state <= target;
            if (reset_timer) begin
                t <= 16'd0;
                ovf <= 1'b0;
            end else if (men) begin
                if (t == 16'hffff)
                    ovf <= 1'b1;
                else
                    t <= t + 16'd1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n || halt_clr) begin
            cnt_pass <= 16'd0;
            cnt_viol <= 16'd0;
            cnt_inc <= 16'd0;
            log_wptr <= 2'd0;
            log_total <= 6'd0;
        end else if (log_event) begin
            log_wptr <= log_wptr + 2'd1;
            if (!(&log_total))
                log_total <= log_total + 6'd1;
            case (verdict)
                PASS: if (!(&cnt_pass)) cnt_pass <= cnt_pass + 16'd1;
                VIOLATION: if (!(&cnt_viol)) cnt_viol <= cnt_viol + 16'd1;
                INCONCLUSIVE: if (!(&cnt_inc)) cnt_inc <= cnt_inc + 16'd1;
                default: begin end
            endcase
        end
    end
endmodule

`default_nettype wire
