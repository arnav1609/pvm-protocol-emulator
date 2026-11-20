`timescale 1ns/1ps
`default_nettype none

// 33 frozen checks for PVM S09. Independent TB expectations; ISS pending.
module tb_engine_a;
    reg clk = 1'b0;
    reg rst_n = 1'b0, run = 1'b0, enable_pulse = 1'b0;
    reg [15:0] clkdiv;
    reg [4:0] entry_pc, wrap_bottom, wrap_top, out_base, out_cnt, set_base, in_base, side_base, jmp_pin, pull_thresh;
    reg [2:0] set_cnt;
    reg [1:0] side_cnt;
    reg wide, tx_empty, rx_full;
    reg [19:0] pin_in;
    reg [3:0] lut_out;
    reg [15:0] words [0:31];
    reg [31:0] valid;
    wire [4:0] rd_pc, eng_pc;
    wire [19:0] out_val, oe_val;
    wire [3:0] fab_ctrl, eng_fault_code;
    wire [7:2] user_flags;
    wire fab_wr, evt_clr_arb, evt_clr_unf, engine_tick, eng_done_req, eng_fault_req;
    reg sampled_tick, good, subcase_ok;
    integer checks = 0, errors = 0, n;

    localparam [15:0] WORK_OUT = 16'h6701, WORK_JMP = 16'h0042, WORK_SET = 16'he727,
                      WORK_PULL = 16'h97a0, WORK_WAIT = 16'h200c, WORK_DONE = 16'hc0c0;

    always #10 clk = ~clk;
    always @(posedge clk)
        sampled_tick <= engine_tick;

    pvm_engine dut (
        .clk(clk), .rst_n(rst_n), .run(run), .enable_pulse(enable_pulse), .clkdiv(clkdiv),
        .entry_pc(entry_pc), .wrap_bottom(wrap_bottom), .wrap_top(wrap_top),
        .out_base(out_base), .out_cnt(out_cnt), .set_base(set_base), .set_cnt(set_cnt),
        .in_base(in_base), .side_base(side_base), .side_cnt(side_cnt), .jmp_pin(jmp_pin),
        .wide(wide), .pull_thresh(pull_thresh), .instr(words[rd_pc]), .instr_valid(valid[rd_pc]),
        .pin_in(pin_in), .lut_out(lut_out), .arb_lost(1'b1), .underrun(1'b1),
        .tx_empty(tx_empty), .rx_full(rx_full),
        .rd_pc(rd_pc), .out_val(out_val), .oe_val(oe_val), .fab_ctrl(fab_ctrl), .fab_wr(fab_wr),
        .user_flags(user_flags), .evt_clr_arb(evt_clr_arb), .evt_clr_unf(evt_clr_unf),
        .engine_tick(engine_tick), .eng_pc(eng_pc), .eng_done_req(eng_done_req),
        .eng_fault_req(eng_fault_req), .eng_fault_code(eng_fault_code)
    );

    task cycle;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task prepare;
        begin
            @(negedge clk);
            run = 1'b0;
            enable_pulse = 1'b0;
            clkdiv = 16'd1;
            entry_pc = 5'd0;
            wrap_bottom = 5'd0;
            wrap_top = 5'd31;
            out_base = 5'd0;
            out_cnt = 5'd16;
            set_base = 5'd12;
            set_cnt = 3'd1;
            in_base = 5'd0;
            side_base = 5'd0;
            side_cnt = 2'd0;
            jmp_pin = 5'd14;
            wide = 1'b0;
            pull_thresh = 5'd0;
            pin_in = 20'd0;
            lut_out = 4'd0;
            tx_empty = 1'b1;
            rx_full = 1'b0;
            valid = 32'd0;
        end
    endtask

    task load_word(input [4:0] address, input [15:0] word);
        begin
            words[address] = word;
            valid[address] = 1'b1;
        end
    endtask

    task start;
        begin
            @(negedge clk);
            run = 1'b1;
            enable_pulse = 1'b1;
            cycle;
            @(negedge clk);
            enable_pulse = 1'b0;
        end
    endtask

    task check(input [8*48:1] name, input passed);
        begin
            checks = checks + 1;
            if (passed === 1'b1)
                $display("[PASS] %0s", name);
            else begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    task test_clock(input [8*48:1] name, input integer divisor, input use_jump);
        integer core_cycle, tick_number, waveform_ticks, waveform_phase;
        reg expected_high, pass;
        begin
            prepare;
            clkdiv = divisor[15:0];
            wrap_top = use_jump ? 5'd2 : 5'd1;
            load_word(5'd0, 16'he301); // SET PINS,1 [3]
            load_word(5'd1, 16'he300); // SET PINS,0 [3]
            load_word(5'd2, 16'h0000); // JMP 0
            start;
            pass = 1'b1;
            waveform_ticks = use_jump ? 9 : 8;
            for (core_cycle = 1; core_cycle <= divisor * waveform_ticks * 3; core_cycle = core_cycle + 1) begin
                cycle;
                tick_number = core_cycle / divisor;
                waveform_phase = (tick_number - 1) % waveform_ticks;
                expected_high = tick_number > 0 && waveform_phase < 4;
                pass = pass && (out_val[12] === expected_high) &&
                       (sampled_tick === ((core_cycle % divisor) == 0));
            end
            check(name, pass);
        end
    endtask

    task jump_case(input [2:0] condition, input [4:0] x, input [4:0] y,
                   input pin_value, input expect_taken, output reg pass);
        begin
            prepare;
            if (condition == 3'd7) begin
                wide = 1'b1;
                pull_thresh = 5'd16;
            end
            pin_in[14] = pin_value;
            load_word(5'd0, {11'b11100000001, x}); // SET X
            load_word(5'd1, {11'b11100000010, y}); // SET Y
            load_word(5'd2, {8'h00, condition, 5'd5});
            start;
            repeat (3) cycle;
            pass = (eng_pc === (expect_taken ? 5'd5 : 5'd3)) && (eng_fault_req === 1'b0);
        end
    endtask

    task test_jump(input [8*48:1] name, input [2:0] condition, input [4:0] x,
                   input [4:0] y, input pin_value, input expect_taken);
        reg pass;
        begin
            jump_case(condition, x, y, pin_value, expect_taken, pass);
            check(name, pass);
        end
    endtask

    task bad_encoding(input [15:0] word, output reg pass);
        begin
            prepare;
            load_word(5'd0, word);
            start;
            cycle;
            pass = (eng_fault_req === 1'b1) && (eng_fault_code === 4'd3) && (eng_pc === 5'd0);
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_engine_a CHECKS=33");
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_engine_a.vcd");
            $dumpvars(0, tb_engine_a);
        end
        cycle;
        @(negedge clk);
        rst_n = 1'b1;

        test_clock("CLKDIV1_TIMING", 1, 1'b0);
        test_clock("CLKDIV3_TIMING", 3, 1'b1);

        prepare;
        load_word(5'd0, 16'hff01); // SET PINS,1 [31]
        load_word(5'd1, 16'he300); // SET PINS,0 [3]
        start;
        cycle;
        good = (eng_pc === 5'd0) && (out_val[12] === 1'b1);
        for (n = 1; n <= 31; n = n + 1) begin
            cycle;
            good = good && (out_val[12] === 1'b1) &&
                   (eng_pc === (n == 31 ? 5'd1 : 5'd0));
        end
        cycle;
        check("DELAY_MAX_31", good && (out_val[12] === 1'b0));

        prepare;
        side_cnt = 2'd1;
        side_base = 5'd9;
        load_word(5'd0, 16'hf201); // SET PINS,1 SIDE 1 [2]
        load_word(5'd1, 16'he000); // SET PINS,0 SIDE 0
        start;
        cycle;
        good = (out_val[9] === 1'b1) && (out_val[12] === 1'b1) && (eng_pc === 5'd0);
        repeat (2) cycle;
        good = good && (out_val[9] === 1'b1) && (eng_pc === 5'd1);
        cycle;
        check("SIDESET_1BIT", good && ({out_val[9], out_val[12]} === 2'b00));

        prepare;
        side_cnt = 2'd2;
        side_base = 5'd19;
        set_base = 5'd19;
        set_cnt = 3'd2;
        load_word(5'd0, 16'hf902); // PINS 10, SIDE 11, delay 1
        load_word(5'd1, 16'he803); // PINS 11, SIDE 01, delay 0
        start;
        cycle;
        good = ({out_val[0], out_val[19]} === 2'b11) && (eng_pc === 5'd0);
        cycle;
        good = good && ({out_val[0], out_val[19]} === 2'b11) && (eng_pc === 5'd1);
        cycle;
        check("SIDESET_2BIT_PRIORITY_OVER_SET", good && ({out_val[0], out_val[19]} === 2'b01));

        prepare;
        entry_pc = 5'd3;
        wrap_bottom = 5'd2;
        wrap_top = 5'd3;
        load_word(5'd2, 16'he000);
        load_word(5'd3, 16'he001);
        start;
        cycle;
        good = (eng_pc === 5'd2) && (out_val[12] === 1'b1);
        cycle;
        good = good && (eng_pc === 5'd3) && (out_val[12] === 1'b0);
        prepare;
        entry_pc = 5'd31;
        wrap_top = 5'd20;
        load_word(5'd31, 16'he020);
        start;
        cycle;
        check("WRAP", good && (eng_pc === 5'd0));

        test_jump("JMP_COND_0_TAKEN", 3'd0, 5'd0, 5'd0, 1'b0, 1'b1);
        test_jump("JMP_COND_1_TAKEN", 3'd1, 5'd0, 5'd0, 1'b0, 1'b1);
        test_jump("JMP_COND_1_NOT_TAKEN", 3'd1, 5'd1, 5'd0, 1'b0, 1'b0);
        test_jump("JMP_COND_2_TAKEN", 3'd2, 5'd1, 5'd0, 1'b0, 1'b1);
        test_jump("JMP_COND_2_NOT_TAKEN", 3'd2, 5'd0, 5'd0, 1'b0, 1'b0);
        test_jump("JMP_COND_3_TAKEN", 3'd3, 5'd0, 5'd0, 1'b0, 1'b1);
        test_jump("JMP_COND_3_NOT_TAKEN", 3'd3, 5'd0, 5'd1, 1'b0, 1'b0);
        test_jump("JMP_COND_4_TAKEN", 3'd4, 5'd0, 5'd1, 1'b0, 1'b1);
        test_jump("JMP_COND_4_NOT_TAKEN", 3'd4, 5'd0, 5'd0, 1'b0, 1'b0);
        test_jump("JMP_COND_5_TAKEN", 3'd5, 5'd2, 5'd1, 1'b0, 1'b1);
        test_jump("JMP_COND_5_NOT_TAKEN", 3'd5, 5'd2, 5'd2, 1'b0, 1'b0);
        test_jump("JMP_COND_6_TAKEN", 3'd6, 5'd0, 5'd0, 1'b1, 1'b1);
        test_jump("JMP_COND_6_NOT_TAKEN", 3'd6, 5'd0, 5'd0, 1'b0, 1'b0);

        // The maximum WIDE threshold distinguishes D-013's 16 from an 8-bit reset count.
        jump_case(3'd7, 5'd0, 5'd0, 1'b0, 1'b0, good);
        prepare;
        wide = 1'b1;
        pull_thresh = 5'd16;
        load_word(5'd0, 16'h00e5);
        rst_n = 1'b0;
        cycle;
        @(negedge clk);
        rst_n = 1'b1;
        run = 1'b1;
        cycle;
        check("JMP_COND_7_NOT_TAKEN", good && (eng_pc === 5'd1));

        prepare;
        load_word(5'd0, 16'he025); // SET X,5
        load_word(5'd1, 16'h0041); // JMP X--,1
        load_word(5'd2, 16'ha001); // MOV PINS,X
        start;
        cycle;
        good = eng_pc === 5'd1;
        for (n = 1; n <= 6; n = n + 1) begin
            cycle;
            good = good && (eng_pc === (n == 6 ? 5'd2 : 5'd1));
        end
        cycle;
        check("XDEC_LOOP_COUNT", good && (out_val[15:0] === 16'hffff));

        prepare;
        set_base = 5'd19;
        set_cnt = 3'd3;
        load_word(5'd0, 16'he007);
        start;
        cycle;
        check("SET_PINS_BASE_WRAP_MOD20", out_val === 20'h80003);

        prepare;
        set_cnt = 3'd5;
        load_word(5'd0, 16'he095);
        load_word(5'd1, 16'he080);
        start;
        cycle;
        good = (oe_val === 20'h15000) && (out_val === 20'd0);
        cycle;
        check("SET_PINDIRS", good && (oe_val === 20'd0));

        prepare;
        clkdiv = 16'd3;
        load_word(5'd0, 16'he0d8); // SET FAB,24, whose four low bits are 8
        start;
        repeat (2) cycle;
        good = (fab_wr === 1'b0) && (fab_ctrl === 4'd0);
        cycle;
        good = good && (fab_wr === 1'b1) && (fab_ctrl === 4'd8);
        cycle;
        check("SET_FAB_PULSE", good && (fab_wr === 1'b0) && (fab_ctrl === 4'd8));

        prepare;
        in_base = 5'd19;
        pin_in = 20'h80001;
        rx_full = 1'b1;
        lut_out = 4'h9;
        load_word(5'd0, 16'he025); // SET X,5
        load_word(5'd1, 16'ha049); // MOV Y,~X
        load_word(5'd2, 16'ha002); // MOV PINS,Y
        load_word(5'd3, 16'ha051); // MOV Y,reverse X
        load_word(5'd4, 16'ha022); // MOV X,Y
        load_word(5'd5, 16'ha001); // MOV PINS,X
        load_word(5'd6, 16'ha000); // MOV PINS,PINS
        load_word(5'd7, 16'ha004); // MOV PINS,STATUS
        load_word(5'd8, 16'ha003); // MOV PINS,NULL
        load_word(5'd9, 16'ha0e7); // MOV FAB,FAB
        start;
        repeat (3) cycle;
        good = out_val[15:0] === 16'hfffa;
        repeat (3) cycle;
        good = good && (out_val[15:0] === 16'ha000);
        cycle;
        good = good && (out_val[15:0] === 16'h0003);
        cycle;
        good = good && (out_val[15:0] === 16'h0007);
        cycle;
        good = good && (out_val[15:0] === 16'h0000);
        cycle;
        check("MOV_X_Y_INVERT_REVERSE", good && (fab_wr === 1'b1) && (fab_ctrl === 4'h9));

        prepare;
        load_word(5'd0, 16'he027);
        load_word(5'd1, 16'ha281); // MOV PC,X [2]
        start;
        repeat (2) cycle;
        good = eng_pc === 5'd1;
        cycle;
        good = good && (eng_pc === 5'd1);
        cycle;
        check("MOV_PC", good && (eng_pc === 5'd7));

        prepare;
        load_word(5'd0, 16'hc002);
        load_word(5'd1, 16'hc007);
        load_word(5'd2, 16'hc042);
        load_word(5'd3, 16'hc047);
        start;
        cycle;
        good = user_flags === 6'b000001;
        cycle;
        good = good && (user_flags === 6'b100001);
        cycle;
        good = good && (user_flags === 6'b100000);
        cycle;
        check("EVT_SET_CLR_FLAGS", good && (user_flags === 6'd0));

        prepare;
        load_word(5'd0, 16'hc040);
        load_word(5'd1, 16'hc041);
        load_word(5'd2, 16'he020);
        start;
        cycle;
        good = {evt_clr_arb, evt_clr_unf} === 2'b10;
        cycle;
        good = good && ({evt_clr_arb, evt_clr_unf} === 2'b01);
        cycle;
        check("EVT_CLR_ARB_PULSE", good && ({evt_clr_arb, evt_clr_unf} === 2'b00));

        prepare;
        entry_pc = 5'd4;
        load_word(5'd4, WORK_DONE);
        start;
        cycle;
        good = (eng_done_req === 1'b1) && (eng_pc === 5'd4) && (eng_fault_req === 1'b0);
        cycle;
        check("EVT_DONE", good && (eng_done_req === 1'b0) && (sampled_tick === 1'b0));

        prepare;
        entry_pc = 5'd9;
        start;
        cycle;
        good = (eng_fault_req === 1'b1) && (eng_fault_code === 4'd4) && (eng_pc === 5'd9);
        cycle;
        check("INVALID_WORD_FAULT_PC", good && (eng_fault_req === 1'b0) && (eng_pc === 5'd9));

        bad_encoding(16'h2014, good); // WAIT PIN out of range
        bad_encoding(16'h2024, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'h2048, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'h2060, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'h40e1, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'h4011, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'h6011, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'h8001, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'ha018, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'hc000, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'hc001, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'hc008, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'hc080, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'he060, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'he0a0, subcase_ok); good = good && subcase_ok;
        bad_encoding(16'he0e0, subcase_ok); good = good && subcase_ok;
        check("ILLEGAL_ENCODINGS", good);

        prepare;
        load_word(5'd0, 16'he025); // SET X,5
        load_word(5'd1, 16'he04b); // SET Y,11
        load_word(5'd2, 16'ha001); // MOV PINS,X
        load_word(5'd3, 16'hc002); // EVT SET FLAG 2
        load_word(5'd7, 16'ha001); // MOV PINS,X
        load_word(5'd8, 16'ha002); // MOV PINS,Y
        start;
        repeat (4) cycle;
        good = (out_val === 20'd5) && (user_flags === 6'd1);
        @(negedge clk);
        entry_pc = 5'd7;
        start;
        good = good && (eng_pc === 5'd7) && (user_flags === 6'd0);
        cycle;
        good = good && (out_val === 20'd0) && (eng_pc === 5'd8);
        cycle;
        check("ENABLE_REINIT", good && (out_val === 20'd0) && (eng_pc === 5'd9));

        // Check the ISA words for the datapath and WAIT, which are staged after S09.
        prepare;
        side_cnt = 2'd1;
        load_word(5'd0, WORK_SET);
        load_word(5'd1, WORK_JMP);
        load_word(5'd2, WORK_DONE);
        start;
        repeat (7) cycle;
        good = eng_pc === 5'd0;
        cycle;
        good = good && (eng_pc === 5'd1);
        cycle;
        good = good && (eng_pc === 5'd2);
        cycle;
        check("WORKED_ENCODINGS", good && (eng_done_req === 1'b1) &&
              (WORK_OUT  === {3'b011, 1'b0, 4'd7, 3'd0, 5'd1}) &&
              (WORK_PULL === {3'b100, 1'b1, 4'd7, 1'b1, 1'b0, 1'b1, 5'd0}) &&
              (WORK_WAIT === {3'b001, 5'd0, 1'b0, 2'd0, 5'd12}));

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == 33) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #100000;
        $display("TB_TIMEOUT engine_a");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
