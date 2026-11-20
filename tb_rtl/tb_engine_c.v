`timescale 1ns/1ps
`default_nettype none

// S11, 12 frozen standalone WAIT, timeout and fault checks; ISS pending.
module tb_engine_c;
    reg clk = 1'b0, rst_n = 1'b0, enable = 1'b0, run = 1'b0;
    reg [15:0] timeout, word;
    reg [1:0] presc, side_cnt;
    reg [19:0] pins;
    reg [3:0] fabric_bits;
    reg arb, tx_empty, rx_full;
    wire [4:0] pc;
    wire [19:0] out_val;
    wire engine_tick, fault, tx_pop, rx_push;
    wire [3:0] code;
    reg sampled_tick, pass, exact_slow;
    integer checks = 0, errors = 0, n;

    always #10 clk = ~clk;
    always @(posedge clk) sampled_tick <= engine_tick;

    pvm_engine dut (
        .clk(clk), .rst_n(rst_n), .run(run), .enable_pulse(enable), .clkdiv(16'd1),
        .entry_pc(5'd0), .wrap_bottom(5'd0), .wrap_top(5'd31), .out_base(5'd0), .out_cnt(5'd16),
        .set_base(5'd12), .set_cnt(3'd1), .in_base(5'd0), .side_base(5'd17), .side_cnt(side_cnt),
        .jmp_pin(5'd0), .wide(1'b0), .pull_thresh(5'd0), .push_thresh(5'd0), .out_shr(1'b1),
        .in_shr(1'b0), .autopull(1'b0), .autopush(1'b0), .timeout(timeout), .to_presc(presc),
        .instr(word), .instr_valid(1'b1), .pin_in(pins), .lut_out(fabric_bits),
        .arb_lost(arb), .underrun(1'b0), .tx_empty(tx_empty), .rx_full(rx_full),
        .tx_level(tx_empty ? 3'd0 : 3'd1), .rx_level(rx_full ? 3'd4 : 3'd0),
        .tx_dout(8'h6a), .tx_pop(tx_pop), .rx_push(rx_push), .rx_din(),
        .rd_pc(), .out_val(out_val), .oe_val(), .fab_ctrl(), .fab_wr(), .user_flags(),
        .evt_clr_arb(), .evt_clr_unf(), .engine_tick(engine_tick), .eng_pc(pc),
        .eng_done_req(), .eng_fault_req(fault), .eng_fault_code(code)
    );

    pvm_trace trace (
        .clk(clk), .run_state({2'b00, run}), .pc(pc),
        .instr_valid(dut.issue_cycle && !dut.invalid_fetch),
        .out_val(out_val), .oe_val(dut.oe_val), .fab_ctrl(dut.fab_ctrl), .fab_wr(dut.fab_wr),
        .tx_pop(tx_pop), .rx_push(rx_push), .rx_din(dut.rx_din),
        .fault_req(fault), .fault_code(code)
    );

    task cycle;
        begin @(posedge clk); #1; end
    endtask

    task prepare(input [15:0] instruction);
        begin
            @(negedge clk);
            run = 1'b0;
            rst_n = 1'b0;
            enable = 1'b0;
            word = instruction;
            timeout = 16'd0;
            presc = 2'd0;
            side_cnt = 2'd0;
            pins = 20'd0;
            fabric_bits = 4'd0;
            arb = 1'b0;
            tx_empty = 1'b1;
            rx_full = 1'b1;
            cycle;
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task start;
        begin
            run = 1'b1;
            enable = 1'b1;
            cycle;
            @(negedge clk);
            enable = 1'b0;
        end
    endtask

    task check(input [8*48:1] name, input ok);
        begin
            checks = checks + 1;
            if (ok === 1'b1)
                $display("[PASS] %0s", name);
            else begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    task expect_timeout(input [15:0] instruction, input [15:0] limit,
                        input [1:0] mode, input integer expected, output reg ok);
        integer cycle_index;
        begin
            prepare(instruction);
            timeout = limit;
            presc = mode;
            start;
            ok = 1'b1;
            for (cycle_index=1; cycle_index<expected; cycle_index=cycle_index+1) begin
                cycle;
                ok = ok && (pc === 5'd0) && !fault && !tx_pop && !rx_push;
            end
            cycle;
            ok = ok && fault && (code === 4'd2) && (pc === 5'd0);
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_engine_c CHECKS=12");
        prepare(16'h200c);
        pins[12] = 1'b1;
        start;
        repeat (2) cycle;
        pass = (pc === 5'd0) && !fault;
        @(negedge clk); pins[12] = 1'b0;
        cycle;
        check("WAIT_PIN_POL0", pass && (pc === 5'd1));

        prepare(16'h208c);
        start;
        repeat (2) cycle;
        pass = (pc === 5'd0) && !fault;
        @(negedge clk); pins[12] = 1'b1;
        cycle;
        check("WAIT_PIN_POL1", pass && (pc === 5'd1));

        prepare(16'h20a2); // WAIT 1 FAB 2
        start;
        cycle;
        pass = pc === 5'd0;
        @(negedge clk); fabric_bits[1] = 1'b1;
        cycle;
        pass = pass && (pc === 5'd0);
        @(negedge clk); fabric_bits[2] = 1'b1;
        cycle;
        check("WAIT_FAB", pass && (pc === 5'd1));

        prepare(16'h20c0); // WAIT 1 FLAG 0 (ARB_LOST)
        start;
        cycle;
        pass = pc === 5'd0;
        @(negedge clk); arb = 1'b1;
        cycle;
        check("WAIT_FLAG_ARB", pass && (pc === 5'd1));

        prepare(16'h308c);
        side_cnt = 2'd1;
        start;
        pass = out_val[17] === 1'b0;
        cycle;
        pass = pass && (out_val[17] === 1'b1) && (pc === 5'd0);
        repeat (3) cycle;
        check("WAIT_SIDESET_APPLIED_DURING_STALL", pass && (out_val[17] === 1'b1) && (pc === 5'd0));

        prepare(16'h238c); // WAIT 1 PIN 12 [3]
        start;
        repeat (5) cycle;
        pass = pc === 5'd0;
        @(negedge clk); pins[12] = 1'b1;
        cycle;
        pass = pass && (pc === 5'd0);
        repeat (2) begin
            cycle;
            pass = pass && (pc === 5'd0);
        end
        cycle;
        check("DELAY_AFTER_WAIT_ONLY", pass && (pc === 5'd1));

        expect_timeout(16'h208c, 16'd3, 2'd0, 3, pass);
        expect_timeout(16'h208c, 16'd2, 2'd1, 32, exact_slow);
        check("TIMEOUT_EXACT_COUNT", pass && exact_slow);

        prepare(16'h208c);
        timeout = 16'd3;
        start;
        repeat (2) cycle;
        pass = (pc === 5'd0) && !fault;
        @(negedge clk); pins[12] = 1'b1;
        cycle;
        check("TIMEOUT_COMPLETION_WINS", pass && (pc === 5'd1) && !fault);

        prepare(16'h208c);
        start;
        pass = 1'b1;
        for (n=0;n<100;n=n+1) begin
            cycle;
            pass = pass && (pc === 5'd0) && !fault;
        end
        check("TIMEOUT_0_DISABLED", pass);

        expect_timeout(16'h80a0, 16'd3, 2'd0, 3, pass);
        check("TIMEOUT_ON_PULL", pass);

        expect_timeout(16'h8020, 16'd3, 2'd0, 3, pass);
        check("TIMEOUT_ON_PUSH", pass);

        prepare(16'he060);
        start;
        cycle;
        pass = fault && (code === 4'd3) && (pc === 5'd0);
        @(negedge clk); word = 16'he001;
        repeat (3) begin
            cycle;
            pass = pass && !sampled_tick && !fault && (pc === 5'd0) && (out_val[12] === 1'b0);
        end
        check("FAULT_STOPS_ENGINE", pass);

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == 12) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin #200000; $display("TB_TIMEOUT engine_c"); $finish; end
endmodule
`default_nettype wire
