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
    reg [31:0] src_prev;
    wire [7:0] matching_rules, selected;
    wire [3:0] less_than_k;
    wire [1:0] min_verdict [0:3];
    wire [1:0] max_verdict [0:3];
    wire [2:0] targets [0:7];
    wire [2:0] actions [0:7];
    wire [1:0] rule_min [0:7];
    wire [1:0] rule_max [0:7];
    reg [2:0] rule, target, action;
    reg [1:0] verdict_min, verdict_max, verdict;
    integer i;
    genvar k, e, slot;

    assign selected[0] = matching_rules[0];

    pvm_presc timebase (
        .clk(clk), .rst_n(rst_n), .run(active), .restart(start || halt_clr),
        .sel(presc), .en(men)
    );

    generate
        for (k = 0; k < 4; k = k + 1) begin : thresholds
            wire [15:0] limit = cfg_k[k*16+:16];
            wire [16:0] upper = {1'b0, limit} + {1'b0, cfg_m};
            wire [16:0] lower = {1'b0, limit} - {1'b0, cfg_m};
            wire [16:0] elapsed = {1'b0, t};
            assign less_than_k[k] = t < limit;
            assign min_verdict[k] = (ovf && upper[16]) ? INCONCLUSIVE :
                                    elapsed >= upper ? PASS :
                                    (!lower[16] && elapsed < lower) ? VIOLATION :
                                    INCONCLUSIVE;
            assign max_verdict[k] = (ovf && upper >= 17'h0ffff) ? INCONCLUSIVE :
                                    (!lower[16] && elapsed <= lower) ? PASS :
                                    elapsed > upper ? VIOLATION :
                                    INCONCLUSIVE;
        end
        for (e = 0; e < 8; e = e + 1) begin : rules
            wire [23:0] entry = cfg_entries[e*24+:24];
            wire [4:0] source_id = entry[12:8];
            wire [1:0] k_idx = entry[17:16];
            wire now_high = sources[source_id];
            wire prev_high = src_prev[source_id];
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
            assign rule_min[e] = min_verdict[k_idx];
            assign rule_max[e] = max_verdict[k_idx];
        end
    endgenerate

    always @(*) begin
        rule = 3'd0;
        target = 3'd0;
        action = 3'd0;
        verdict_min = 2'd0;
        verdict_max = 2'd0;
        for (i = 0; i < 8; i = i + 1) begin
            if (selected[i]) begin
                rule = rule | i[2:0];
                target = target | targets[i];
                action = action | actions[i];
                verdict_min = verdict_min | rule_min[i];
                verdict_max = verdict_max | rule_max[i];
            end
        end
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
            src_prev <= 32'd0;
            tstamp <= 16'd0;
        end else begin
            src_prev <= sources;
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
