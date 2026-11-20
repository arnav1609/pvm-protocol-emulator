`timescale 1ns/1ps
`default_nettype none

// 17 frozen checks for the S01 primitives, frozen 2026-11-20 before registration.
module tb_primitives;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [2:0] sync_d = 3'b000;
    reg edge_d = 1'b0;
    reg tick_run = 1'b0;
    reg tick_restart = 1'b0;
    reg [15:0] div = 16'd0;
    reg presc_run = 1'b0;
    reg presc_restart = 1'b0;
    reg [1:0] sel = 2'd0;

    wire [2:0] sync_q;
    wire rise, fall, tick, en;
    reg tick_sample, en_sample;
    reg first_sample_ok, transition_ok, stopped_ok;
    integer cycle;
    integer checks = 0;
    integer errors = 0;
    localparam integer N_CHECKS = 17;

    always #10 clk = ~clk;

    pvm_sync2 #(.W(3), .RST_VAL(3'b101)) sync_dut (
        .clk(clk), .rst_n(rst_n), .d(sync_d), .q(sync_q)
    );
    pvm_edge edge_dut (
        .clk(clk), .rst_n(rst_n), .d(edge_d), .rise(rise), .fall(fall)
    );
    pvm_tick tick_dut (
        .clk(clk), .rst_n(rst_n), .run(tick_run), .restart(tick_restart),
        .div(div), .tick(tick)
    );
    pvm_presc presc_dut (
        .clk(clk), .rst_n(rst_n), .run(presc_run), .restart(presc_restart),
        .sel(sel), .en(en)
    );

    // Observe the enables exactly as another synchronous module would.
    always @(posedge clk) begin
        tick_sample <= tick;
        en_sample <= en;
    end

    task check(input [8*48:1] name, input ok);
        begin
            checks = checks + 1;
            if (ok)
                $display("[PASS] %0s", name);
            else begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    task sample_tick_periods(input integer period, input integer periods, output reg ok);
        integer n;
        begin
            ok = 1'b1;
            for (n = 1; n <= period * periods; n = n + 1) begin
                @(posedge clk);
                #1;
                ok = ok && (tick_sample === ((n % period) == 0));
            end
        end
    endtask

    task sample_presc_periods(input integer period, input integer periods, output reg ok);
        integer n;
        begin
            ok = 1'b1;
            for (n = 1; n <= period * periods; n = n + 1) begin
                @(posedge clk);
                #1;
                ok = ok && (en_sample === ((n % period) == 0));
            end
        end
    endtask

    task test_divisor(
        input [15:0] divisor,
        input integer period,
        input integer periods,
        input [8*48:1] name
    );
        reg restart_ok, period_ok;
        begin
            @(negedge clk);
            tick_run = 1'b1;
            tick_restart = 1'b1;
            div = divisor;
            @(posedge clk);
            #1;
            restart_ok = (tick_sample === 1'b0);
            @(negedge clk);
            tick_restart = 1'b0;
            sample_tick_periods(period, periods, period_ok);
            check(name, restart_ok && period_ok);
        end
    endtask

    task test_prescaler(input [1:0] mode, input integer period, input [8*48:1] name);
        reg restart_ok, period_ok;
        begin
            @(negedge clk);
            presc_run = 1'b1;
            presc_restart = 1'b1;
            sel = mode;
            @(posedge clk);
            #1;
            restart_ok = (en_sample === 1'b0);
            @(negedge clk);
            presc_restart = 1'b0;
            sample_presc_periods(period, 2, period_ok);
            check(name, restart_ok && period_ok);
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_primitives CHECKS=%0d", N_CHECKS);
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_primitives.vcd");
            $dumpvars(0, tb_primitives);
        end
        @(posedge clk);
        #1;
        check("SYNC_RESET_VAL", sync_q === 3'b101);

        @(negedge clk);
        rst_n = 1'b1;
        sync_d = 3'b010;
        @(posedge clk);
        #1;
        first_sample_ok = (sync_q === 3'b101);
        @(posedge clk);
        #1;
        check("SYNC_LATENCY_2", first_sample_ok && (sync_q === 3'b010));

        @(negedge clk);
        edge_d = 1'b1;
        #1;
        transition_ok = ({rise, fall} === 2'b10);
        @(posedge clk);
        #1;
        check("EDGE_RISE", transition_ok && ({rise, fall} === 2'b00));
        @(negedge clk);
        edge_d = 1'b0;
        #1;
        transition_ok = ({rise, fall} === 2'b01);
        @(posedge clk);
        #1;
        check("EDGE_FALL", transition_ok && ({rise, fall} === 2'b00));
        @(posedge clk);
        #1;
        check("EDGE_NO_CHANGE", {rise, fall} === 2'b00);

        test_divisor(16'd0, 1, 5, "TICK_DIV0");
        test_divisor(16'd1, 1, 5, "TICK_DIV1");
        test_divisor(16'd5, 5, 10, "TICK_DIV5_PERIOD");
        test_divisor(16'd65535, 65535, 1, "TICK_DIV65535");

        // Accumulate a partial period before restarting with a different divisor.
        @(negedge clk);
        div = 16'd8;
        repeat (3) @(posedge clk);
        test_divisor(16'd5, 5, 2, "TICK_RESTART");

        @(negedge clk);
        tick_run = 1'b0;
        div = 16'd0;
        stopped_ok = 1'b1;
        for (cycle = 0; cycle < 5; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            stopped_ok = stopped_ok && (tick_sample === 1'b0);
        end
        check("TICK_RUN_LOW_NO_TICK", stopped_ok);

        test_prescaler(2'd0, 1, "PRESC_SEL0");
        test_prescaler(2'd1, 16, "PRESC_SEL1");
        test_prescaler(2'd2, 256, "PRESC_SEL2");
        test_prescaler(2'd3, 4096, "PRESC_SEL3");
        repeat (7) @(posedge clk);
        test_prescaler(2'd1, 16, "PRESC_RESTART");

        @(negedge clk);
        div = 16'd4;
        tick_run = 1'b1;
        edge_d = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b0;
        edge_d = 1'b0;
        @(posedge clk);
        #1;
        stopped_ok = (sync_q === 3'b101) && ({rise, fall} === 2'b00) &&
                     ({tick_sample, en_sample} === 2'b00);
        @(negedge clk);
        rst_n = 1'b1;
        for (cycle = 1; cycle <= 16; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            stopped_ok = stopped_ok && (tick_sample === ((cycle % 4) == 0)) &&
                         (en_sample === (cycle == 16));
        end
        check("MID_RUN_RESET", stopped_ok);

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == N_CHECKS) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #2000000;
        $display("TB_TIMEOUT primitives");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
