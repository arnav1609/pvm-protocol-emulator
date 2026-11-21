`timescale 1ns/1ps
`default_nettype none

// 5 frozen CCITT-FALSE checks, frozen 2026-11-20 before registration. Stage S02.
module tb_crc16;
    localparam integer N_CHECKS = 5;
    reg clk = 1'b0, rst_n = 1'b0, clr = 1'b0, en = 1'b0;
    reg [7:0] din = 8'h00;
    wire [15:0] crc;
    integer checks = 0, errors = 0;
    integer i;
    reg [15:0] held_crc;
    reg cleared_ok;

    always #10 clk = ~clk;
    pvm_crc16 dut (.clk(clk), .rst_n(rst_n), .clr(clr), .en(en), .din(din), .crc(crc));

    task reset_crc;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            en = 1'b0;
            @(posedge clk);
            #1;
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task write_byte(input valid, input [7:0] data);
        begin
            @(negedge clk);
            en = valid;
            din = data;
            @(posedge clk);
            #1;
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
        $display("CONFIG: TOP=tb_crc16 CHECKS=%0d", N_CHECKS);
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_crc16.vcd");
            $dumpvars(0, tb_crc16);
        end
        reset_crc;
        check("VEC_EMPTY", crc === 16'hffff);
        for (i = 1; i <= 9; i = i + 1)
            write_byte(1'b1, 8'h30 + i[7:0]);
        check("VEC_123456789", crc === 16'h29b1);

        reset_crc;
        write_byte(1'b1, 8'h00);
        check("VEC_00", crc === 16'he1f0);
        held_crc = crc;
        write_byte(1'b0, 8'ha5);
        check("EN_LOW_HOLD", crc === held_crc);

        @(negedge clk);
        clr = 1'b1;
        @(posedge clk);
        #1;
        cleared_ok = (crc === 16'hffff);
        @(negedge clk);
        clr = 1'b0;
        write_byte(1'b1, 8'h31);
        check("CLR_RESTART", cleared_ok && (crc === 16'hc782));

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == N_CHECKS) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #10000;
        $display("TB_TIMEOUT crc16");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
