`timescale 1ns/1ps
`default_nettype none
module tb_fabric;
    localparam integer N_CHECKS = 21;
    localparam [15:0] DATA = 16'h95e2;
    reg clk = 0, rst_n = 0, run = 0, enable_pulse = 0;
    reg engine_tick, fab_wr, cnt_en, cnt_src, manch_en, arb_en;
    reg clr_flags, evt_clr_arb, evt_clr_unf, pad_mode;
    reg [19:0] sample_pins, engine_out, engine_oe;
    reg [7:0] pad_in;
    reg [139:0] pin_cfg;
    reg [3:0] fab_ctrl, arb_n;
    reg [127:0] cfg_lut;
    reg [11:0] cfg_mode;
    reg [9:0] cnt_reload;
    wire [7:0] pad_sync, pad_oe;
    wire [19:0] pins = pad_mode ? {pad_sync, 12'b0} : sample_pins;
    wire [19:0] intent;
    wire [3:0] lut_out;
    wire phase, arb_lost, underrun;
    integer checks = 0, errors = 0;
    integer trial, n, j, seed, i;
    reg good, first_half;
    reg [3:0] reference_luts, address;
    reg [15:0] bitmap, selectors, model_sources, received;

    always #10 clk = ~clk;
    pvm_sync2 #(.W(8)) sync_pads(.clk(clk), .rst_n(rst_n), .d(pad_in), .q(pad_sync));
    pvm_pin_guard guard (
        .clk(clk), .rst_n(rst_n), .state(run ? 3'd3 : 3'd0), .pin_cfg(pin_cfg),
        .out_val(engine_out), .oe_val(engine_oe), .lut_out(lut_out), .arb_en(arb_en),
        .arb_lost(arb_lost), .arb_sda(5'd12), .arb_scl(5'd13),
        .uo_pins(), .uio_out(), .uio_oe(pad_oe), .uo_readback(), .od_release_intent(intent)
    );
    pvm_fabric dut (
        .clk(clk), .rst_n(rst_n), .run(run), .enable_pulse(enable_pulse), .engine_tick(engine_tick),
        .pin_in(pins), .od_release_intent(intent), .fab_ctrl(fab_ctrl), .fab_wr(fab_wr),
        .cfg_lut(cfg_lut), .cfg_mode(cfg_mode), .cnt_reload(cnt_reload),
        .cnt_en(cnt_en), .cnt_src(cnt_src), .manch_en(manch_en), .arb_en(arb_en), .arb_n(arb_n),
        .arb_sda(5'd12), .arb_scl(5'd13), .clr_flags(clr_flags),
        .evt_clr_arb(evt_clr_arb), .evt_clr_unf(evt_clr_unf), .lut_out(lut_out),
        .cnt_phase(phase), .arb_lost(arb_lost), .underrun(underrun)
    );

    task step;
        begin @(posedge clk); #1; end
    endtask

    task prepare;
        begin
            @(negedge clk);
            {rst_n, run, enable_pulse} = 3'd0;
            {engine_tick, fab_wr, cnt_en, cnt_src, manch_en, arb_en} = 6'd0;
            {clr_flags, evt_clr_arb, evt_clr_unf, pad_mode} = 4'd0;
            {sample_pins, engine_out, engine_oe} = 60'd0;
            {pad_in, pin_cfg, fab_ctrl, arb_n} = 156'd0;
            {cfg_lut, cfg_mode, cnt_reload} = 150'd0;
            step;
            @(negedge clk); rst_n = 1'b1;
        end
    endtask

    task start;
        begin
            {run, enable_pulse} = 2'b11;
            step;
            @(negedge clk); enable_pulse = 1'b0;
        end
    endtask

    task check(input [8*48:1] name, input passed);
        begin
            checks = checks + 1;
            if (passed === 1'b1) $display("[PASS] %0s", name);
            else begin errors = errors + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    task phase_period(input [9:0] reload, output reg ok);
        integer half_period, k;
        begin
            prepare;
            cnt_en = 1'b1; cnt_reload = reload;
            half_period = reload + 1;
            start;
            ok = phase === 1'b0;
            for (k = 1; k <= half_period * 2; k = k + 1) begin
                step;
                ok = ok && phase === (k >= half_period && k < 2*half_period);
            end
        end
    endtask

    task arb_setup(input [3:0] threshold);
        begin
            prepare;
            arb_en = 1'b1; arb_n = threshold;
            pin_cfg[12*7+:7] = 7'h11;
            pin_cfg[13*7+:7] = 7'h11;
            engine_out[12] = 1'b1;
            engine_oe[13:12] = 2'b11;
            start;
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_fabric CHECKS=%0d", N_CHECKS);
        seed = 20261120;
        $display("LUT random seed=%0d, vectors=1000", seed);
        prepare; start; good = 1'b1;
        for (trial = 0; trial < 1000; trial = trial + 1) begin
            sample_pins = $random(seed);
            fab_ctrl = $random(seed);
            for (n = 0; n < 4; n = n + 1) begin
                bitmap = $random(seed); selectors = $random(seed);
                cfg_lut[n*32+:32] = {selectors, bitmap};
                cfg_mode[n*3+2] = (trial+n) % 2;
                model_sources[7:0] = cfg_mode[n*3+2] ?
                    {sample_pins[14:12], sample_pins[4:0]} : sample_pins[19:12];
                model_sources[11:8] = fab_ctrl;
                model_sources[15:12] = n < 2 ? 4'b0010 : {2'b00, lut_out[1:0]};
                for (j = 0; j < 4; j = j + 1)
                    address[j] = model_sources[selectors[j*4+:4]];
                reference_luts[n] = bitmap[address];
            end
            step; good = good && lut_out === reference_luts;
            @(negedge clk);
        end
        check("LUT_ALL_16_TT_RANDOM", good);

        prepare;
        cfg_lut = {32'h000daaaa, 32'h00dc6666, 32'h0001aaaa, 32'h0000aaaa};
        sample_pins[12] = 1'b1;
        start;
        step; good = lut_out === 4'b0001;
        step; good = good && lut_out === 4'b0101;
        @(negedge clk); sample_pins[13] = 1'b1;
        step; good = good && lut_out === 4'b0111;
        step; check("LAYER2_SEES_L0_L1", good && lut_out === 4'b1011);

        prepare;
        cfg_lut[31:0] = 32'h000caaaa; cfg_lut[127:96] = 32'h0008aaaa;
        fab_ctrl[0] = 1'b1;
        start;
        step; good = lut_out === 4'b1000;
        step; check("NO_L2_TO_L1", good && lut_out === 4'b1000);

        prepare; cfg_lut[31:0] = 32'h0000aaaa; cfg_mode[2:0] = 3'd1;
        start;
        step; good = lut_out[0] === 1'b0;
        @(negedge clk); sample_pins[12] = 1'b1;
        step; good = good && lut_out[0] === 1'b1;
        step; good = good && lut_out[0] === 1'b0;
        @(negedge clk); sample_pins[12] = 1'b0;
        step; good = good && lut_out[0] === 1'b0;
        @(negedge clk); sample_pins[12] = 1'b1;
        step; check("MODE_RISE_PULSE", good && lut_out[0] === 1'b1);

        prepare; cfg_lut[31:0] = 32'h0000aaaa; cfg_mode[2:0] = 3'd2;
        start; sample_pins[12] = 1'b1;
        step; good = lut_out[0] === 1'b0;
        @(negedge clk); sample_pins[12] = 1'b0;
        repeat (4) begin step; good = good && lut_out[0] === 1'b0; end
        check("MODE_MAJ3_FILTERS_1CYCLE_GLITCH", good);
        @(negedge clk); sample_pins[12] = 1'b1;
        step; good = lut_out[0] === 1'b0;
        step; good = good && lut_out[0] === 1'b0;
        step; good = good && lut_out[0] === 1'b1;
        @(negedge clk); sample_pins[12] = 1'b0;
        step; good = good && lut_out[0] === 1'b1;
        step; good = good && lut_out[0] === 1'b1;
        step; check("MODE_MAJ3_PASSES_3CYCLE", good && lut_out[0] === 1'b0);

        prepare; cfg_mode = 12'b100100100100;
        cfg_lut = {32'h0007aaaa, 32'h0005aaaa, 32'h0004aaaa, 32'h0000aaaa};
        sample_pins = 20'h05001; start;
        step; good = lut_out === 4'b1101;
        @(negedge clk); sample_pins = 20'h02010;
        step; check("GROUP1_MAPPING", good && lut_out === 4'b0010);

        phase_period(10'd249, good); check("CNT_PERIOD_RELOAD_249", good);
        phase_period(10'd0, good); check("CNT_RELOAD_0", good);
        phase_period(10'd1023, good); check("CNT_RELOAD_1023", good);
        prepare; cnt_en = 1'b1; cnt_src = 1'b1; cnt_reload = 10'd2;
        start; good = 1'b1;
        for (i = 1; i <= 18; i = i + 1) begin
            engine_tick = (i % 3 == 0);
            step; good = good && phase === (i >= 9 && i < 18);
            @(negedge clk);
        end
        check("CNT_SRC_ENGINE_TICK", good);

        prepare; cnt_en = 1'b1; manch_en = 1'b1; cnt_reload = 10'd249;
        cfg_lut[31:0] = 32'h00e86666;
        start; fab_ctrl[0] = DATA[0]; fab_wr = 1'b1;
        step;
        @(negedge clk); fab_wr = 1'b0;
        repeat (499) step;
        good = 1'b1;
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk);
            fab_wr = i < 15;
            fab_ctrl[0] = i < 15 ? DATA[i+1] : 1'b0;
            step; first_half = lut_out[0];
            good = good && !underrun && !phase;
            @(negedge clk); fab_wr = 1'b0;
            repeat (250) step;
            good = good && phase && (lut_out[0] === !first_half);
            received[i] = first_half;
            repeat (249) step;
        end
        check("MANCH_STREAM_16BITS", good && received === DATA);
        check("MANCH_UNDERRUN", underrun && !phase);

        prepare; cnt_en = 1'b1; manch_en = 1'b1; cnt_reload = 10'd1;
        cfg_lut[31:0] = 32'h0008aaaa;
        start; fab_ctrl[0] = 1'b1; fab_wr = 1'b1;
        step;
        @(negedge clk); fab_wr = 1'b0;
        repeat (2) step;
        @(negedge clk); fab_ctrl[0] = 1'b0; fab_wr = 1'b1;
        step;
        @(negedge clk); fab_wr = 1'b0;
        step; good = lut_out[0] === 1'b1 && !underrun;
        repeat (4) step;
        check("MANCH_BOUNDARY_WRITE_QUEUED", good && lut_out[0] === 1'b0 && !underrun);

        arb_setup(4'd3); sample_pins[13] = 1'b1;
        good = 1'b1;
        repeat (3) begin step; good = good && !arb_lost; end
        step; check("ARB_DETECT_AFTER_N", good && arb_lost);

        arb_setup(4'd3); sample_pins[13] = 1'b1;
        repeat (2) step;
        @(negedge clk); sample_pins[13] = 1'b0;
        repeat (4) step; check("ARB_NO_DETECT_IF_SCL_SHORT", !arb_lost);

        arb_setup(4'd1); engine_out[12] = 1'b0; sample_pins[13] = 1'b1;
        repeat (5) step;
        check("ARB_NO_DETECT_WHEN_DRIVING_LOW", !arb_lost && pad_oe[0]);

        arb_setup(4'd1); pad_mode = 1'b1; pad_in[1:0] = 2'b11;
        engine_out[13] = 1'b1;
        repeat (5) step;
        @(negedge clk); pad_in[0] = 1'b0;
        step; good = !arb_lost && pad_sync[0];
        step; good = good && !arb_lost && !pad_sync[0];
        @(negedge clk); engine_out[13] = 1'b0;
        step; good = good && arb_lost && pad_oe[1];
        @(negedge clk); engine_out[12] = 1'b0;
        step; check("ARB_RELEASE_BOUND_CYCLES", good && arb_lost && pad_oe[1:0] == 2'b00);

        arb_setup(4'd1); sample_pins[13] = 1'b1;
        repeat (2) step;
        @(negedge clk); sample_pins[12] = 1'b1; evt_clr_arb = 1'b1;
        step; good = !arb_lost;
        @(negedge clk); sample_pins[12] = 1'b0; evt_clr_arb = 1'b0;
        step; good = good && arb_lost;
        @(negedge clk); sample_pins[12] = 1'b1; clr_flags = 1'b1;
        step; good = good && !arb_lost;
        @(negedge clk); sample_pins[12] = 1'b0; clr_flags = 1'b0;
        step; good = good && arb_lost;
        @(negedge clk); run = 1'b0;
        step; check("FLAGS_STICKY_AFTER_RUN", arb_lost && pad_oe == 8'h00);
        @(negedge clk); clr_flags = 1'b1;
        step; check("ARB_CLEAR_BY_EVT_HOST_HALT", good && !arb_lost);

        prepare; cfg_lut[31:0] = 32'h0000ffff; cnt_en = 1'b1; cnt_reload = 10'd0;
        start;
        step; good = phase && lut_out[0];
        @(negedge clk); run = 1'b0;
        step; check("NOT_RUN_CLEARS", good && lut_out === 4'b0000 && phase === 1'b0);

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", errors == 0 && checks == N_CHECKS ? "PASS" : "FAIL");
        $finish;
    end
    initial begin
        #1000000;
        $display("TB_TIMEOUT\nRESULT : FAIL");
        $finish;
    end
endmodule
`default_nettype wire
