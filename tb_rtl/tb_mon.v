`timescale 1ns/1ps
`default_nettype none
module tb_mon;
    localparam integer N_CHECKS = 24;
    localparam [1:0] RISE=0, FALL=1, HIGH=2, LOW=3;
    localparam [1:0] ALWAYS=0, LT=1, GE=2;
    localparam [2:0] RESET=1, MINIMUM=2, MAXIMUM=3, MEASURE=4, VIOLATE=5, PASS=6;
    reg clk = 0, rst_n = 0, run = 0, halt_clr = 0, mon_en = 0;
    reg [19:0] pin_in;
    reg [3:0] lut_out;
    reg arb_lost, underrun;
    reg [7:2] user_flags;
    reg [191:0] entries;
    reg [63:0] limits;
    reg [15:0] margin;
    reg [1:0] presc;
    wire [2:0] state;
    wire [15:0] passes, violations, inconclusive;
    wire [159:0] log_flat;
    wire [1:0] wptr;
    wire [5:0] total;
    integer checks = 0, errors = 0;
    reg good;

    always #10 clk = ~clk;

    pvm_mon dut (
        .clk(clk), .rst_n(rst_n), .run(run), .halt_clr(halt_clr), .pin_in(pin_in),
        .lut_out(lut_out), .arb_lost(arb_lost), .underrun(underrun), .user_flags(user_flags),
        .cfg_entries(entries), .cfg_k(limits), .cfg_m(margin), .mon_en(mon_en), .presc(presc),
        .mon_state(state), .cnt_pass(passes), .cnt_viol(violations), .cnt_inc(inconclusive),
        .log_flat(log_flat), .log_wptr(wptr), .log_total(total)
    );

    task step;
        begin @(posedge clk); #1; end
    endtask

    task prepare;
        begin
            @(negedge clk);
            {rst_n, run, halt_clr, mon_en, pin_in, lut_out, arb_lost, underrun, user_flags} = 36'd0;
            entries = 192'd0;
            limits = 64'd0;
            margin = 16'd0;
            presc = 2'd0;
            step;
            @(negedge clk); rst_n = 1'b1; mon_en = 1'b1;
        end
    endtask

    task start;
        begin run = 1'b1; step; end
    endtask

    task rule(input integer n, input [2:0] from_state, to_state, input [1:0] edge_kind,
              input [4:0] src, input [1:0] guard_kind, kidx, input [2:0] action);
        entries[n*24+:24] = {3'd0, action, kidx, 1'b1, guard_kind, src,
                              edge_kind, to_state, from_state};
    endtask

    task check(input [8*48:1] name, input passed);
        begin
            checks = checks + 1;
            if (passed === 1'b1) $display("[PASS] %0s", name);
            else begin errors = errors + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    function logged(input [2:0] fired_rule, input [1:0] verdict,
                    input overflow, input [15:0] interval);
        begin
            logged = total == 1 && wptr == 1 && log_flat[23:0] ===
                {interval, 2'b00, overflow, verdict, fired_rule} &&
                passes == (verdict == 1 ? 16'd1 : 16'd0) &&
                violations == (verdict == 2 ? 16'd1 : 16'd0) &&
                inconclusive == (verdict == 3 ? 16'd1 : 16'd0);
        end
    endfunction

    task measure(input [2:0] action, input [15:0] k, m, elapsed,
                 input [1:0] verdict, output reg ok);
        begin
            prepare;
            limits[47:32] = k; margin = m;
            rule(3, 0, 4, RISE, 0, ALWAYS, 2, action);
            start;
            repeat (elapsed) step;
            @(negedge clk); pin_in[0] = 1'b1;
            step;
            ok = logged(3, verdict, 0, elapsed) && log_flat[39:24] == elapsed &&
                 state == 4 && dut.t == 0;
        end
    endtask

    task stretch(input [15:0] low_time, input [1:0] verdict, output reg ok);
        begin
            prepare; limits[15:0] = 16'd235; margin = 16'd3;
            pin_in[13] = 1'b1;
            rule(0, 0, 1, FALL, 13, ALWAYS, 0, RESET);
            rule(1, 1, 0, RISE, 13, ALWAYS, 0, MINIMUM);
            start;
            @(negedge clk); pin_in[13] = 1'b0;
            step;
            repeat (low_time) step;
            @(negedge clk); pin_in[13] = 1'b1;
            step;
            ok = state == 0 && logged(1, verdict, 0, low_time);
        end
    endtask

    initial begin : cases
        reg first, second;
        $display("CONFIG: TOP=tb_mon CHECKS=%0d", N_CHECKS);

        prepare;
        rule(0, 0, 1, HIGH, 0, ALWAYS, 0, PASS);
        rule(1, 0, 2, HIGH, 0, ALWAYS, 0, VIOLATE);
        rule(2, 1, 3, HIGH, 0, ALWAYS, 0, VIOLATE);
        pin_in[0] = 1'b1; start;
        step;
        check("FIRST_MATCH_PRIORITY", state == 1 && log_flat[4:0] == 5'b01000);
        good = total == 1 && passes == 1 && violations == 0;
        step;
        check("ONE_FIRE_PER_CYCLE", good && state == 3 && total == 2 &&
              passes == 1 && violations == 1);

        prepare;
        rule(0, 0, 1, RISE, 3, ALWAYS, 0, 0);
        rule(1, 1, 2, FALL, 3, ALWAYS, 0, 0);
        rule(2, 2, 3, HIGH, 6, ALWAYS, 0, 0);
        rule(3, 3, 4, LOW, 7, ALWAYS, 0, 0);
        pin_in[7] = 1'b1; start;
        step; good = state == 0;
        @(negedge clk); pin_in[3] = 1'b1;
        step; good = good && state == 1;
        step; good = good && state == 1;
        @(negedge clk); pin_in[3] = 1'b0;
        step; good = good && state == 2;
        @(negedge clk); pin_in[6] = 1'b1;
        step; good = good && state == 3;
        step; good = good && state == 3;
        @(negedge clk); pin_in[7] = 1'b0;
        step; check("EDGE_RISE_FALL_HIGH_LOW", good && state == 4);

        prepare; limits[63:48] = 16'd2;
        rule(0, 0, 4, HIGH, 0, LT, 3, 0);
        rule(1, 4, 5, HIGH, 1, GE, 3, 0);
        start;
        @(negedge clk); pin_in[1:0] = 2'b11;
        step; good = state == 4;
        step; good = good && state == 4;
        step; check("GUARD_LT_GE", good && state == 5 && total == 0);

        measure(MINIMUM, 235, 3, 238, 1, good); check("CHECK_MIN_PASS", good);
        measure(MINIMUM, 235, 3, 231, 2, good); check("CHECK_MIN_VIOL", good);
        measure(MINIMUM, 235, 3, 237, 3, first);
        measure(MINIMUM, 235, 3, 232, 3, second); check("CHECK_MIN_INC", first && second);
        measure(MAXIMUM, 235, 3, 232, 1, good); check("CHECK_MAX_PASS", good);
        measure(MAXIMUM, 235, 3, 239, 2, good); check("CHECK_MAX_VIOL", good);
        measure(MAXIMUM, 235, 3, 233, 3, first);
        measure(MAXIMUM, 235, 3, 238, 3, second); check("CHECK_MAX_INC", first && second);
        measure(MINIMUM, 16'hffff, 1, 0, 2, first);
        measure(MAXIMUM, 0, 3, 0, 3, second);
        check("ARITHMETIC_17BIT", first && second);

        measure(MEASURE, 235, 3, 7, 0, good); check("MEASURE_LOG_NO_COUNT", good);
        measure(VIOLATE, 0, 0, 1, 2, first);
        measure(PASS, 0, 0, 1, 1, second); check("VIOLATE_PASS_ACTIONS", first && second);
        stretch(300, 1, first);
        stretch(200, 2, second); good = first && second;
        stretch(236, 3, first); check("I2C_STRETCH_RULE_SET", good && first);

        prepare; limits[15:0] = 16'hffff; margin = 16'd1;
        rule(0, 0, 1, RISE, 0, ALWAYS, 0, MAXIMUM);
        start; repeat (65535) step;
        good = dut.t === 16'hffff && !dut.ovf;
        step; check("TIMER_SATURATE_OVF", good && dut.t === 16'hffff && dut.ovf);
        @(negedge clk); pin_in[0] = 1'b1;
        step; check("OVF_INCONCLUSIVE_RULE", logged(0, 3, 1, 16'hffff) && !dut.ovf);

        prepare;
        rule(0, 0, 0, HIGH, 0, ALWAYS, 0, PASS);
        pin_in[0] = 1'b1; start;
        repeat (6) step;
        check("LOG_RING_WRAP_4", total == 6 && wptr == 2 && passes == 6 &&
              log_flat[24+:16] == 4 && log_flat[64+:16] == 5 &&
              log_flat[104+:16] == 2 && log_flat[144+:16] == 3);
        repeat (60) step;
        check("LOG_TOTAL_SAT_63", total == 63 && wptr == 2 && passes == 66);

        @(negedge clk);
        force dut.cnt_pass = 16'hffff;
        force dut.cnt_viol = 16'hffff;
        force dut.cnt_inc = 16'hffff;
        release dut.cnt_pass;
        release dut.cnt_viol;
        release dut.cnt_inc;
        step;
        @(negedge clk); rule(0, 0, 0, HIGH, 0, ALWAYS, 0, VIOLATE);
        step;
        @(negedge clk); margin = 1; rule(0, 0, 0, HIGH, 0, ALWAYS, 0, MINIMUM);
        step;
        check("COUNTER_SAT_FFFF", passes == 16'hffff && violations == 16'hffff &&
              inconclusive == 16'hffff && total == 63);

        @(negedge clk); run = 1'b0;
        step;
        check("STOP_RETAINS_LOG", passes == 16'hffff && total == 63);
        @(negedge clk); halt_clr = 1'b1;
        step;
        check("HALT_CLEARS", {passes, violations, inconclusive, log_flat, wptr, total, state} == 219'd0);

        prepare; presc = 1;
        rule(0, 0, 1, RISE, 0, ALWAYS, 0, MEASURE);
        start; repeat (15) step;
        good = dut.t === 16'd0;
        step; good = good && dut.t === 16'd1;
        @(negedge clk); pin_in[0] = 1'b1;
        step;
        check("PRESC_16_TIMEBASE", good && logged(0, 0, 0, 1) && log_flat[39:24] == 1);

        prepare; mon_en = 1'b0; pin_in[0] = 1'b1;
        rule(0, 0, 1, HIGH, 0, ALWAYS, 0, PASS);
        start; repeat (20) step;
        check("MON_EN_0_IDLE", {state, passes, violations, inconclusive, total, dut.tstamp} == 73'd0);

        prepare;
        rule(0, 0, 1, HIGH, 23, ALWAYS, 0, 0);
        rule(1, 1, 2, HIGH, 24, ALWAYS, 0, 0);
        rule(2, 2, 3, HIGH, 25, ALWAYS, 0, 0);
        rule(3, 3, 4, HIGH, 31, ALWAYS, 0, 0);
        start;
        @(negedge clk); lut_out[3] = 1'b1;
        step; good = state == 1;
        @(negedge clk); arb_lost = 1'b1;
        step; good = good && state == 2;
        @(negedge clk); underrun = 1'b1;
        step; good = good && state == 3;
        @(negedge clk); user_flags[7] = 1'b1;
        step; check("SRC_FLAGS_FABRIC", good && state == 4);

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", errors == 0 && checks == N_CHECKS ? "PASS" : "FAIL");
        $finish;
    end
    initial begin
        #10000000;
        $display("TB_TIMEOUT\nRESULT : FAIL");
        $finish;
    end
endmodule
`default_nettype wire
