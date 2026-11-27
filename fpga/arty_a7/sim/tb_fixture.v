`timescale 1ns/1ps
`default_nettype none

module tb_fixture;
    reg clk = 0;
    always #10 clk = !clk;
    reg rst_n = 0;
    reg master_sda_low = 0, master_scl_low = 0;
    wire sda_low, scl_low;
    tri1 sda, scl;
    assign sda = master_sda_low || sda_low ? 1'b0 : 1'bz;
    assign scl = master_scl_low || scl_low ? 1'b0 : 1'bz;

    i2c_target_fixture dut (
        .clk(clk), .rst_n(rst_n), .sda(sda), .scl(scl),
        .sda_low(sda_low), .scl_low(scl_low)
    );

    integer cases=0;
    task fail;
        input [8*48-1:0] name;
        begin
            $display("FAIL %0s at %0t",name,$time);
            $finish_and_return(1);
        end
    endtask

    task check;
        input [8*48-1:0] name;
        begin
            $display("PASS %0s",name);
            cases=cases+1;
        end
    endtask

    task start_burst;
        begin
            if ({sda,scl,sda_low,scl_low} !== 4'b1100)
                fail("FIXTURE_IDLE");
            master_sda_low=1;
            repeat(240) @(negedge clk);
            master_scl_low=1;
        end
    endtask

    task send_data;
        input [7:0] value;
        integer i;
        begin
            for (i=7;i>=0;i=i-1) begin
                master_sda_low=!value[i];
                repeat (80) @(negedge clk);
                if (sda_low !== 1'b0)
                    fail("FIXTURE_EARLY_DRIVE");
                master_scl_low=0;
                #1;
                if (scl !== 1'b1 || sda !== value[i])
                    fail("FIXTURE_DATA_INTERFERENCE");
                repeat (240) @(negedge clk);
                master_scl_low=1;
            end
        end
    endtask

    task ack;
        input expected_ack;
        input integer expected_stretch;
        integer wait_clks;
        reg saw_gap;
        begin
            master_sda_low=0;
            #1;
            saw_gap = sda !== 1'b0;
            repeat (80) begin
                @(negedge clk);
                if (sda !== 1'b0)
                    saw_gap = 1;
            end
            if (sda_low !== expected_ack)
                fail("FIXTURE_ACK");
            if (expected_ack && saw_gap)
                fail("FIXTURE_ACK_GAP");
            master_scl_low=0;
            #1;
            wait_clks=0;
            while (scl === 1'b0) begin
                @(negedge clk);
                wait_clks=wait_clks+1;
                if (wait_clks>400)
                    fail("FIXTURE_STRETCH_TIMEOUT");
            end
            if (wait_clks != expected_stretch) begin
                $display("ACK stretch %0d expected %0d",wait_clks,expected_stretch);
                fail("FIXTURE_STRETCH");
            end
            if ({scl,sda} !== {1'b1,!expected_ack})
                fail("FIXTURE_ACK_LEVEL");
            repeat(240) @(negedge clk);
            master_scl_low=1;
            repeat(160) @(negedge clk);
            if (sda_low !== 0 || scl_low !== 0)
                fail("FIXTURE_ACK_RELEASE");
        end
    endtask

    task stop_burst;
        begin
            master_sda_low=1;
            repeat(80) @(negedge clk);
            master_scl_low=0;
            repeat(160) @(negedge clk);
            master_sda_low=0;
            repeat(80) @(negedge clk);
            if ({sda,scl,sda_low,scl_low} !== 4'b1100)
                fail("FIXTURE_STOP_RELEASE");
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n=1;
        repeat (4) @(negedge clk);
        start_burst;
        send_data(8'ha0); ack(1,331);
        send_data(8'h3c); ack(1,0);
        stop_burst;
        check("FIXTURE_VALID_ADDRESS_DATA_STOP");

        start_burst;
        send_data(8'ha2); ack(0,0);
        stop_burst;
        check("FIXTURE_WRONG_ADDRESS");

        start_burst;
        send_data(8'ha0); ack(1,331);
        send_data(8'h3d); ack(0,0);
        stop_burst;
        check("FIXTURE_WRONG_DATA");

        start_burst;
        send_data(8'ha0);
        master_sda_low=0;
        repeat(80) @(negedge clk);
        master_scl_low=0;
        #1;
        if ({sda_low,scl_low} !== 2'b11)
            fail("FIXTURE_RESET_TEST_SETUP");
        rst_n=0;
        #1;
        if ({sda,scl,sda_low,scl_low} !== 4'b1100)
            fail("FIXTURE_RESET_RELEASE");
        check("FIXTURE_RESET_RELEASE");
        if (cases != 4)
            fail("FIXTURE_FROZEN_COUNT");
        $display("RESULT PASS CHECKS %0d",cases);
        $finish;
    end

    initial begin
        #2000000;
        fail("FIXTURE_TIMEOUT");
    end
endmodule

`default_nettype wire
