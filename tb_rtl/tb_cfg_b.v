`timescale 1ns/1ps
`default_nettype none

// 22 frozen validation checks, frozen 2026-11-20 before registration. Stage S07.
module tb_cfg_b;
    localparam integer N_CHECKS = 22;
    localparam [15:0] CTRL = 16'h0f00;
    localparam [2:0] HALT = 3'd0, VALIDATING = 3'd1, READY = 3'd2, FAULT = 3'd5;
    reg clk = 1'b0, rst_n = 1'b0;
    reg [15:0] bus_addr = 16'h0000;
    reg [7:0] bus_wdata = 8'h00;
    reg bus_we = 1'b0, bus_re = 1'b0;
    wire [7:0] bus_rdata;
    wire [2:0] state;
    wire [4:0] entry_pc;
    wire imem_wr_en, imem_clr, entry_valid;
    wire [5:0] imem_wr_addr, imem_rd_addr;
    wire [7:0] imem_wr_data, imem_rd_data;
    reg [15:0] crc_model, first_crc, second_crc;
    reg [23:0] image_id;
    reg valid_started, ok, old_id_ok;
    integer checks = 0, errors = 0;

    always #10 clk = ~clk;

    pvm_cfg dut (
        .clk(clk), .rst_n(rst_n), .bus_addr(bus_addr), .bus_wdata(bus_wdata),
        .bus_we(bus_we), .bus_re(bus_re), .bus_rack(1'b0), .bus_rdata(bus_rdata),
        .imem_wr_en(imem_wr_en), .imem_wr_addr(imem_wr_addr), .imem_wr_data(imem_wr_data),
        .imem_clr_valid(imem_clr), .imem_bus_rd_addr(imem_rd_addr), .imem_bus_rd_data(imem_rd_data),
        .imem_entry_valid(entry_valid), .entry_pc(entry_pc),
        .tx_level(3'd0), .rx_level(3'd0), .rx_head(8'h00), .tx_fifo_ovf(1'b0), .rx_fifo_unf(1'b0),
        .eng_done_req(1'b0), .eng_fault_req(1'b0), .eng_fault_code(4'd0), .eng_pc(5'd0),
        .flags(8'h00), .state(state), .cnt_pass(16'h0000), .cnt_viol(16'h0000), .cnt_inc(16'h0000),
        .mon_state(3'd0), .log_flat(160'd0), .log_wptr(2'd0), .log_total(6'd0)
    );

    pvm_imem imem (
        .clk(clk), .rst_n(rst_n), .wr_en(imem_wr_en), .wr_addr(imem_wr_addr),
        .wr_data(imem_wr_data), .clr_valid(imem_clr), .rd_pc(5'd0),
        .entry_pc(entry_pc), .entry_valid(entry_valid),
        .bus_rd_addr(imem_rd_addr), .bus_rd_data(imem_rd_data)
    );

    task bus_step(input write, input read, input [15:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            bus_we = write;
            bus_re = read;
            bus_addr = addr;
            bus_wdata = data;
            @(posedge clk);
            #1;
        end
    endtask

    task write_byte(input [15:0] address, input [7:0] data);
        begin
            bus_step(1'b1, 1'b0, address, data);
        end
    endtask

    task read_byte(input [15:0] address, output reg [7:0] data);
        begin
            bus_step(1'b0, 1'b1, address, 8'h00);
            data = bus_rdata;
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

    task set_field(input [15:0] address, input [7:0] data);
        integer bit_index;
        reg mix;
        begin
            write_byte(address, data);
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                mix = crc_model[15] ^ data[bit_index];
                crc_model = {crc_model[14:0], 1'b0};
                if (mix)
                    crc_model = crc_model ^ 16'h1021;
            end
        end
    endtask

    task new_image(input empty_imem);
        begin
            @(negedge clk);
            rst_n = 1'b0;
            bus_we = 1'b0;
            bus_re = 1'b0;
            @(posedge clk);
            #1;
            @(negedge clk);
            rst_n = 1'b1;
            crc_model = 16'hffff;
            if (!empty_imem) begin
                // SET PINS, 1. The engine is not executed in this stage.
                set_field(16'h0000, 8'h01);
                set_field(16'h0001, 8'he0);
            end
        end
    endtask

    task validate(input correct_crc);
        reg [15:0] expected;
        integer waited;
        begin
            expected = correct_crc ? crc_model : (crc_model ^ 16'h0001);
            write_byte(16'h0f08, expected[7:0]);
            write_byte(16'h0f09, expected[15:8]);
            write_byte(CTRL, 8'h02);
            valid_started = state === VALIDATING;
            for (waited = 0; waited < 32 && state === VALIDATING; waited = waited + 1)
                bus_step(1'b0, 1'b0, 16'h0000, 8'h00);
        end
    endtask

    task fault_is(input [7:0] code, output reg pass);
        reg [7:0] fault_code, fault_pc, time_low, time_high;
        begin
            read_byte(16'h0f02, fault_code);
            read_byte(16'h0f03, fault_pc);
            read_byte(16'h0f04, time_low);
            read_byte(16'h0f05, time_high);
            pass = valid_started && (state === FAULT) && (fault_code === code) &&
                   (fault_pc === 8'h00) && ({time_high, time_low} !== 16'h0000);
        end
    endtask

    task single_bad_field(input [8*48:1] name, input [15:0] address,
                          input [7:0] data, input [7:0] fault);
        reg result;
        begin
            new_image(1'b0);
            set_field(address, data);
            validate(1'b1);
            fault_is(fault, result);
            check(name, result);
        end
    endtask

    task setup_arb(input [7:0] control, input [7:0] sda, input configure_sda_od);
        begin
            new_image(1'b0);
            set_field(16'h0224, control);
            set_field(16'h0225, sda);
            set_field(16'h0226, 8'd13);
            set_field(16'h040d, 8'h11);
            if (configure_sda_od)
                set_field(16'h040c, 8'h11);
        end
    endtask

    task read_image_id(output reg [23:0] id);
        begin
            read_byte(16'h0f20, id[7:0]);
            read_byte(16'h0f21, id[15:8]);
            read_byte(16'h0f22, id[23:16]);
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_cfg_b CHECKS=%0d", N_CHECKS);
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_cfg_b.vcd");
            $dumpvars(0, tb_cfg_b);
        end
        single_bad_field("OD_ON_UO", 16'h0405, 8'h11, 8'h06);
        single_bad_field("OUTPUT_ON_UI", 16'h0400, 8'h09, 8'h06);
        single_bad_field("OWNER_WITH_INPUT_MODE", 16'h040c, 8'h01, 8'h06);
        single_bad_field("OWNER7", 16'h0405, 8'h0f, 8'h07);
        single_bad_field("MODE3", 16'h0405, 8'h18, 8'h07);
        single_bad_field("OUT_CNT_17", 16'h0103, 8'd17, 8'h07);
        single_bad_field("SET_CNT_6", 16'h0105, 8'd6, 8'h07);
        single_bad_field("SIDE_CNT_3", 16'h0108, 8'd3, 8'h07);
        single_bad_field("BASE_20", 16'h0102, 8'd20, 8'h07);
        single_bad_field("WRAP_INVERTED", 16'h010a, 8'h01, 8'h07);

        new_image(1'b1);
        validate(1'b1);
        fault_is(8'h07, ok);
        check("ENTRY_INVALID", ok);
        single_bad_field("LUTMODE3", 16'h021c, 8'h03, 8'h07);
        single_bad_field("MANCH_NO_CNT", 16'h0222, 8'h04, 8'h07);
        setup_arb(8'h01, 8'd12, 1'b1);
        validate(1'b1);
        fault_is(8'h07, ok);
        check("ARB_N0", ok);
        setup_arb(8'h31, 8'd5, 1'b1);
        validate(1'b1);
        fault_is(8'h07, ok);
        check("ARB_PIN_NOT_UIO", ok);
        setup_arb(8'h31, 8'd12, 1'b0);
        validate(1'b1);
        fault_is(8'h07, ok);
        check("ARB_PIN_NOT_OD", ok);
        single_bad_field("MON_GUARD3", 16'h031d, 8'he0, 8'h07);
        new_image(1'b0);
        set_field(16'h0305, 8'h80);
        set_field(16'h0306, 8'h1c);
        validate(1'b1);
        fault_is(8'h07, ok);
        check("MON_ACTION7", ok);

        new_image(1'b0);
        set_field(16'h0400, 8'h09);
        validate(1'b0);
        fault_is(8'h05, ok);
        check("CRC_BEFORE_PIN", ok);

        new_image(1'b0);
        set_field(16'h0104, 8'd5);
        set_field(16'h0105, 8'd1);
        set_field(16'h0405, 8'h29);
        set_field(16'h0f0a, 8'hb2);
        first_crc = crc_model;
        validate(1'b1);
        check("LEGAL_IMAGE_READY", valid_started && (state === READY));
        read_image_id(image_id);
        check("IMAGE_ID_LATCHED", image_id === {8'hb2, first_crc});

        write_byte(CTRL, 8'h01);
        old_id_ok = state === HALT;
        crc_model = 16'hffff;
        set_field(16'h0f0a, 8'h4f);
        read_image_id(image_id);
        old_id_ok = old_id_ok && (image_id === {8'hb2, first_crc});
        second_crc = crc_model;
        validate(1'b1);
        read_image_id(image_id);
        check("REVALIDATE_AFTER_HALT", old_id_ok && (state === READY) && (image_id === {8'h4f, second_crc}));

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == N_CHECKS) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #40000;
        $display("TB_TIMEOUT cfg_b");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
