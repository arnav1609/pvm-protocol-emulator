`timescale 1ns/1ps
`default_nettype none

// 17 frozen pin-guard checks, frozen 2026-11-20 before registration. Stage S08.
// SEED 0x93B52AF7
module tb_pin_guard;
    localparam integer N_CHECKS = 17;
    localparam [2:0] RUN = 3'd3;
    reg clk = 1'b0, rst_n = 1'b0;
    reg [2:0] state = 3'd0;
    reg [139:0] pin_cfg = 140'd0;
    reg [19:0] out_val = 20'd0, oe_val = 20'd0;
    reg [3:0] lut_out = 4'd0;
    reg arb_en = 1'b0, arb_lost = 1'b0;
    reg [4:0] arb_sda = 5'd12, arb_scl = 5'd13;
    wire [6:0] uo_pins, uo_readback;
    wire [7:0] uio_out, uio_oe;
    wire [19:0] od_release_intent;
    reg [31:0] rng = 32'h93b52af7;
    integer checks = 0, errors = 0, n, p;
    reg safe, before_update, after_update;

    always #10 clk = ~clk;

    pvm_pin_guard dut (
        .clk(clk), .rst_n(rst_n), .state(state), .pin_cfg(pin_cfg),
        .out_val(out_val), .oe_val(oe_val), .lut_out(lut_out),
        .arb_en(arb_en), .arb_lost(arb_lost), .arb_sda(arb_sda), .arb_scl(arb_scl),
        .uo_pins(uo_pins), .uio_out(uio_out), .uio_oe(uio_oe),
        .uo_readback(uo_readback), .od_release_intent(od_release_intent)
    );

    task sample;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task setup_pin(input integer pin, input [6:0] config_value);
        begin
            pin_cfg[7*pin+:7] = config_value;
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

    task check_fabric_owner(input [2:0] owner, input integer bit_index, input [8*48:1] name);
        reg high_ok;
        begin
            @(negedge clk);
            setup_pin(12, {4'b0001, owner});
            lut_out = 4'b0001 << bit_index;
            sample;
            high_ok = {uio_oe[0], uio_out[0]} === 2'b11;
            @(negedge clk);
            lut_out = ~(4'b0001 << bit_index);
            sample;
            check(name, high_ok && ({uio_oe[0], uio_out[0]} === 2'b10));
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_pin_guard CHECKS=%0d", N_CHECKS);
        $display("SEED %08h", rng);
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_pin_guard.vcd");
            $dumpvars(0, tb_pin_guard);
        end
        sample;
        safe = ({uo_pins, uio_oe, uo_readback} === 22'd0);

        @(negedge clk);
        rst_n = 1'b1;
        setup_pin(5, 7'h29);
        setup_pin(12, 7'h09);
        oe_val[12] = 1'b1;
        out_val[5] = 1'b0;
        for (n = 0; n <= 5; n = n + 1) begin
            if (n != 3) begin
                state = n[2:0];
                sample;
                safe = safe && (uio_oe === 8'h00) && (uo_pins === 7'h01);
                @(negedge clk);
            end
        end
        check("NOT_RUN_SAFE", safe);

        state = RUN;
        setup_pin(5, 7'h20);
        setup_pin(12, 7'h28);
        sample;
        check("OWNER_NONE_IDLE", (uo_pins[0] === 1'b1) &&
              ({uio_oe[0], uio_out[0]} === 2'b01));

        @(negedge clk);
        setup_pin(5, 7'h09);
        setup_pin(12, 7'h09);
        out_val[5] = 1'b1;
        out_val[12] = 1'b1;
        sample;
        check("ENGINE_PUSHPULL", {uo_pins[0], uio_out[0], uio_oe[0]} === 3'b111);
        @(negedge clk);
        oe_val[12] = 1'b0;
        sample;
        check("ENGINE_OE_UIO", {uio_oe[0], uio_out[0]} === 2'b01);
        check("UO_ALWAYS_ENABLED", (oe_val[5] === 1'b0) && (uo_pins[0] === 1'b1));

        check_fabric_owner(3'd3, 0, "FABRIC_OWNER_L0");
        check_fabric_owner(3'd4, 1, "FABRIC_OWNER_L1");
        check_fabric_owner(3'd5, 2, "FABRIC_OWNER_L2");
        check_fabric_owner(3'd6, 3, "FABRIC_OWNER_L3");

        @(negedge clk);
        setup_pin(5, 7'h49);
        sample;
        check("INVERT", uo_pins[0] === 1'b0);

        @(negedge clk);
        setup_pin(12, 7'h11);
        out_val[12] = 1'b0;
        oe_val[12] = 1'b1;
        sample;
        check("OD_LOW_DRIVES", {uio_oe[0], uio_out[0], od_release_intent[12]} === 3'b100);
        @(negedge clk);
        out_val[12] = 1'b1;
        sample;
        check("OD_HIGH_RELEASES", {uio_oe[0], uio_out[0], od_release_intent[12]} === 3'b001);

        safe = 1'b1;
        for (n = 0; n < 2000; n = n + 1) begin
            @(negedge clk);
            rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            for (p = 12; p < 20; p = p + 1)
                setup_pin(p, {rng[p], 1'b0, 2'b10, 3'd1});
            out_val[19:12] = rng[7:0];
            oe_val[19:12] = rng[31:24];
            sample;
            safe = safe && ((uio_oe & uio_out) === 8'h00);
        end
        check("OD_NEVER_OE_AND_1", safe);

        @(negedge clk);
        for (p = 12; p < 20; p = p + 1)
            setup_pin(p, 7'h11);
        out_val = 20'd0;
        oe_val = 20'hff000;
        arb_en = 1'b1;
        sample;
        safe = uio_oe === 8'hff;
        @(negedge clk);
        arb_lost = 1'b1;
        #1;
        before_update = uio_oe[1:0] === 2'b11;
        sample;
        check("ARB_FORCE_RELEASE", safe && before_update && (uio_oe[1:0] === 2'b00));
        check("ARB_OTHER_PINS_UNAFFECTED", uio_oe[7:2] === 6'h3f);

        @(negedge clk);
        setup_pin(5, 7'h09);
        out_val[5] = 1'b0;
        sample;
        @(negedge clk);
        out_val[5] = 1'b1;
        #1;
        before_update = uo_pins[0] === 1'b0;
        sample;
        after_update = uo_pins[0] === 1'b1;
        check("LATENCY_1_CYCLE", before_update && after_update);
        before_update = uo_readback[0] === 1'b0;
        sample;
        check("READBACK_ALIGNED", before_update && (uo_readback[0] === 1'b1));

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == N_CHECKS) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #100000;
        $display("TB_TIMEOUT pin_guard");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
