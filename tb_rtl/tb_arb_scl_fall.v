`timescale 1ns/1ps
`default_nettype none

module tb_arb_scl_fall;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg run = 1'b0;
    reg [1:0] pad_in = 2'b11;
    wire [1:0] pad_sync;
    wire arb_lost;
    reg passed;

    always #10 clk = ~clk;

    pvm_sync2 #(.W(2)) sync_pads (
        .clk(clk), .rst_n(rst_n), .d(pad_in), .q(pad_sync)
    );
    pvm_fabric fabric (
        .clk(clk), .rst_n(rst_n), .run(run), .enable_pulse(1'b0), .engine_tick(1'b0),
        .pin_in({6'd0, pad_sync, 12'd0}), .od_release_intent(20'h01000),
        .fab_ctrl(4'd0), .fab_wr(1'b0), .cfg_lut(128'd0), .cfg_mode(12'd0),
        .cnt_reload(10'd0), .cnt_en(1'b0), .cnt_src(1'b0), .manch_en(1'b0),
        .arb_en(1'b1), .arb_n(4'd3), .arb_sda(5'd12), .arb_scl(5'd13),
        .clr_flags(1'b0), .evt_clr_arb(1'b0), .evt_clr_unf(1'b0),
        .lut_out(), .cnt_phase(), .arb_lost(arb_lost), .underrun()
    );

    task step;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_arb_scl_fall CHECKS=1");
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        run = 1'b1;
        repeat (6) step;
        passed = pad_sync === 2'b11 && fabric.scl_hi_cnt === 4'd4 && arb_lost === 1'b0;

        // The simultaneous pad transitions reach both synchronized samples on edge two.
        @(negedge clk);
        pad_in = 2'b00;
        step;
        passed = passed && pad_sync === 2'b11 && arb_lost === 1'b0;
        step;
        passed = passed && pad_sync === 2'b00 && fabric.scl_hi_cnt >= 4'd3 && arb_lost === 1'b0;
        // On the detection edge, SCL is already sampled low but the old count still qualifies.
        step;
        passed = passed && fabric.scl_hi_cnt === 4'd0 && arb_lost === 1'b0;
        step;
        passed = passed && arb_lost === 1'b0;

        if (passed === 1'b1) begin
            $display("[PASS] ARB_NO_DETECT_ON_SCL_FALL");
            $display("CHECKS : 1\nERRORS : 0\nRESULT : PASS");
        end else begin
            $display("[FAIL] ARB_NO_DETECT_ON_SCL_FALL");
            $display("CHECKS : 1\nERRORS : 1\nRESULT : FAIL");
        end
        $finish;
    end
endmodule

`default_nettype wire
