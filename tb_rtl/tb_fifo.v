`timescale 1ns/1ps
`default_nettype none

// 9 frozen FIFO checks, frozen 2026-11-20 before registration. Stage S02.
// SEED 0xACE3
module tb_fifo;
    localparam integer N_CHECKS = 9;
    reg clk = 1'b0, rst_n = 1'b0, clr = 1'b0, push = 1'b0, pop = 1'b0;
    reg [7:0] din = 8'h00;
    wire [7:0] dout;
    wire full, empty, ovf, unf;
    wire [2:0] level;
    integer checks = 0, errors = 0;
    integer i, j, model_count;
    reg [7:0] queue_model [0:3];
    reg [15:0] rng = 16'hace3;
    reg model_push, model_pop, allow_push, allow_pop, ok;

    always #10 clk = ~clk;

    pvm_fifo dut (
        .clk(clk), .rst_n(rst_n), .clr(clr), .push(push), .pop(pop), .din(din),
        .dout(dout), .full(full), .empty(empty), .level(level), .ovf(ovf), .unf(unf)
    );

    task step(input psh, input pp, input [7:0] data);
        begin
            @(negedge clk);
            push = psh;
            pop = pp;
            din = data;
            @(posedge clk);
            #1;
        end
    endtask

    task clear_fifo;
        begin
            @(negedge clk);
            push = 1'b0;
            pop = 1'b0;
            clr = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            clr = 1'b0;
        end
    endtask

    task fill_fifo;
        integer n;
        begin
            for (n = 0; n < 4; n = n + 1)
                step(1'b1, 1'b0, 8'h40 + n[7:0]);
        end
    endtask

    task check(input [8*48:1] name, input passed);
        begin
            checks = checks + 1;
            if (passed)
                $display("[PASS] %0s", name);
            else begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_fifo CHECKS=%0d", N_CHECKS);
        $display("SEED %04h", rng);
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_fifo.vcd");
            $dumpvars(0, tb_fifo);
        end
        @(posedge clk);
        #1;
        check("RESET_EMPTY", {empty, full, level, dout, ovf, unf} === {1'b1, 1'b0, 3'd0, 8'h00, 2'b00});
        @(negedge clk);
        rst_n = 1'b1;

        fill_fifo;
        check("FULL_FLAG", {full, empty, level} === {2'b10, 3'd4});
        step(1'b1, 1'b0, 8'h99);
        ok = (ovf === 1'b1) && (unf === 1'b0) && (level === 3'd4) && (dout === 8'h40);
        check("OVF_DROP", ok);
        ok = 1'b1;
        for (i = 0; i < 4; i = i + 1) begin
            ok = ok && (dout === (8'h40 + i[7:0]));
            step(1'b0, 1'b1, 8'h00);
            ok = ok && (level === (3'd3 - i[2:0])) && ({ovf, unf} === 2'b00);
        end
        check("ORDER_4", ok && (empty === 1'b1));
        step(1'b0, 1'b1, 8'h00);
        check("UNF", (unf === 1'b1) && (level === 3'd0));

        fill_fifo;
        ok = (dout === 8'h40);
        step(1'b1, 1'b1, 8'h77);
        ok = ok && ({full, level, ovf, unf} === {1'b1, 3'd4, 2'b00});
        for (i = 1; i < 4; i = i + 1) begin
            ok = ok && (dout === (8'h40 + i[7:0]));
            step(1'b0, 1'b1, 8'h00);
        end
        ok = ok && (dout === 8'h77);
        step(1'b0, 1'b1, 8'h00);
        check("PUSHPOP_FULL", ok && (empty === 1'b1));

        step(1'b1, 1'b1, 8'hbc);
        check("PUSHPOP_EMPTY", {empty, level, dout, ovf, unf} === {1'b0, 3'd1, 8'hbc, 2'b01});
        clear_fifo;

        // Model a compact queue using a shift on pop, independent of the RTL pointers.
        model_count = 0;
        ok = 1'b1;
        for (i = 0; i < 20; i = i + 1) begin
            rng = {rng[14:0], rng[15] ^ rng[13] ^ rng[12] ^ rng[10]};
            model_push = rng[0];
            model_pop = rng[8];
            allow_pop = model_pop && model_count > 0;
            allow_push = model_push && (model_count < 4 || allow_pop);
            if (allow_pop) begin
                ok = ok && (dout === queue_model[0]);
                for (j = 1; j < model_count; j = j + 1)
                    queue_model[j-1] = queue_model[j];
                model_count = model_count - 1;
            end
            if (allow_push) begin
                queue_model[model_count] = rng[15:8];
                model_count = model_count + 1;
            end
            step(model_push, model_pop, rng[15:8]);
            ok = ok && (ovf === (model_push && !allow_push)) && (unf === (model_pop && !allow_pop)) &&
                 (empty === (model_count == 0)) && (full === (model_count == 4)) &&
                 (level === model_count[2:0]);
            if (model_count > 0)
                ok = ok && (dout === queue_model[0]);
        end
        check("WRAP", ok);

        clear_fifo;
        fill_fifo;
        clear_fifo;
        check("CLR", {empty, level, dout, ovf, unf} === {1'b1, 3'd0, 8'h00, 2'b00});

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == N_CHECKS) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #10000;
        $display("TB_TIMEOUT fifo");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
