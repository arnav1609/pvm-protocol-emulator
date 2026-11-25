`timescale 1ns/1ps
module iv_reset_probe;
    reg clk = 0, d = 0, reset_n = 1;
    wire q;
    sg13cmos5l_dfrbpq_1 uut(q, clk, d, reset_n);
    initial begin
        #3 reset_n = 0;
        #1 $display("RESET pad=%b delayed=%b Q=%b", reset_n, uut.delayed_RESET_B, q);
        #3 reset_n = 1;
        #3 d = 1;
        #3 clk = 1;
        #1 $display("CAPTURE pad_clk=%b delayed_clk=%b pad_d=%b delayed_d=%b Q=%b",
                    clk, uut.delayed_CLK, d, uut.delayed_D, q);
        #3 $finish;
    end
endmodule
