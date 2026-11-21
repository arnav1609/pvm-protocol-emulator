`timescale 1ns/1ps
`default_nettype none

module tb_reset_sync;
    reg clk = 1'b0;
    reg rst_n = 1'b1;
    wire [7:0] uo, uio_out, uio_oe;
    reg release_ok, pulse_ok;
    integer checks = 0;
    integer errors = 0;

    always #5 clk = !clk;

    pvm_top dut (
        .clk(clk), .rst_n(rst_n), .ui_in(8'h0a), .uo_out(uo),
        .uio_in(8'h00), .uio_out(uio_out), .uio_oe(uio_oe)
    );

    task sample;
        begin @(posedge clk); #1; end
    endtask

    task check(input [8*40:1] name, input ok);
        begin
            checks = checks + 1;
            if (ok === 1'b1) begin
                $display("[PASS] %0s", name);
            end else begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_reset_sync CHECKS=3");
        #2 rst_n = 1'b0;
        #1 check("RESET_ASYNC_ASSERT", dut.core_rst_n === 1'b0);

        @(negedge clk);
        #1 rst_n = 1'b1;
        #1 release_ok = dut.core_rst_n === 1'b0;
        sample;
        release_ok = release_ok && dut.core_rst_n === 1'b0;
        sample;
        release_ok = release_ok && dut.core_rst_n === 1'b1;
        check("RESET_TWO_EDGE_RELEASE", release_ok);

        sample;
        sample;
        pulse_ok = dut.protocol_ui[0] === 1'b1;
        // Even a pulse between clock edges must reach the synchronous consumers.
        @(negedge clk);
        #1 rst_n = 1'b0;
        #1 rst_n = 1'b1;
        #1 pulse_ok = pulse_ok && dut.core_rst_n === 1'b0;
        sample;
        check("RESET_PULSE_REACHES_CORE", pulse_ok && dut.protocol_ui[0] === 1'b0 &&
              dut.state === 3'd0 && uio_oe === 8'h00 && uo[6:0] === 7'h00);

        $display("CHECKS : %0d\nERRORS : %0d\nRESULT : %0s",
                 checks, errors, errors == 0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule

`default_nettype wire
