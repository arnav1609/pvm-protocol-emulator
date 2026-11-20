`timescale 1ns/1ps
`default_nettype none

// 23 frozen config checks, frozen 2026-11-20 before registration. Stage S06, D-012.
module tb_cfg_a;
    localparam integer N_CHECKS = 23;
    localparam [15:0] CTRL = 16'h0f00, STATUS = 16'h0f01, RX = 16'h0f11, TX = 16'h0f10;
    localparam [2:0] HALT = 3'd0, VALIDATING = 3'd1, READY = 3'd2,
                     RUN = 3'd3, DONE = 3'd4, FAULT = 3'd5;
    reg clk = 1'b0, rst_n = 1'b0;
    reg [15:0] bus_addr = 16'h0000;
    reg [7:0] bus_wdata = 8'h00;
    reg bus_we = 1'b0, bus_re = 1'b0, bus_rack = 1'b0;
    wire [7:0] bus_rdata;
    wire tx_push, rx_pop, fifo_clr, tx_ovf, rx_unf;
    wire [2:0] tx_level, rx_level, state;
    wire [7:0] tx_data, rx_head;
    wire imem_clr_valid, imem_wr_en, imem_entry_valid, enable_pulse;
    wire [5:0] imem_wr_addr, imem_bus_rd_addr;
    wire [7:0] imem_wr_data, imem_bus_rd_data;
    wire [4:0] entry_pc;
    reg rx_push = 1'b0;
    reg [7:0] rx_data = 8'h00;
    reg eng_done_req = 1'b0, eng_fault_req = 1'b0;
    reg [3:0] eng_fault_code = 4'd0;
    reg [4:0] eng_pc = 5'd0;

    integer checks = 0, errors = 0, clears = 0, enables = 0;
    reg [15:0] clock_cycles = 16'd0;
    reg [15:0] crc_expected, fault_expected;
    reg [7:0] actual, low_byte, high_byte;
    reg ok, earlier;

    always #10 clk = ~clk;

    pvm_cfg dut (
        .clk(clk), .rst_n(rst_n),
        .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_we(bus_we), .bus_re(bus_re),
        .bus_rack(bus_rack), .bus_rdata(bus_rdata),
        .imem_clr_valid(imem_clr_valid), .imem_bus_rd_data(imem_bus_rd_data),
        .imem_wr_en(imem_wr_en), .imem_wr_addr(imem_wr_addr), .imem_wr_data(imem_wr_data),
        .imem_bus_rd_addr(imem_bus_rd_addr), .imem_entry_valid(imem_entry_valid), .entry_pc(entry_pc),
        .tx_push(tx_push), .tx_data(tx_data), .rx_pop(rx_pop), .fifo_clr(fifo_clr),
        .tx_level(tx_level), .rx_level(rx_level), .rx_head(rx_head),
        .tx_fifo_ovf(tx_ovf), .rx_fifo_unf(rx_unf),
        .eng_done_req(eng_done_req), .eng_fault_req(eng_fault_req),
        .eng_fault_code(eng_fault_code), .eng_pc(eng_pc),
        .flags(8'h00), .state(state), .enable_pulse(enable_pulse),
        .cnt_pass(16'h0000), .cnt_viol(16'h0000), .cnt_inc(16'h0000),
        .mon_state(3'd0), .log_flat(160'd0), .log_wptr(2'd0), .log_total(6'd0)
    );

    pvm_imem imem (
        .clk(clk), .rst_n(rst_n), .wr_en(imem_wr_en), .wr_addr(imem_wr_addr),
        .wr_data(imem_wr_data), .clr_valid(imem_clr_valid), .rd_pc(entry_pc),
        .bus_rd_addr(imem_bus_rd_addr), .bus_rd_data(imem_bus_rd_data), .instr_valid(imem_entry_valid)
    );

    pvm_fifo tx_queue (
        .clk(clk), .rst_n(rst_n), .clr(fifo_clr), .push(tx_push), .din(tx_data), .pop(1'b0),
        .level(tx_level), .ovf(tx_ovf)
    );
    pvm_fifo rx_queue (
        .clk(clk), .rst_n(rst_n), .clr(fifo_clr), .push(rx_push), .din(rx_data), .pop(rx_pop),
        .level(rx_level), .dout(rx_head), .unf(rx_unf)
    );

    always @(posedge clk) begin
        if (!rst_n)
            clock_cycles <= 16'd0;
        else begin
            clock_cycles <= clock_cycles + 16'd1;
            if (imem_clr_valid)
                clears <= clears + 1;
            if (enable_pulse)
                enables <= enables + 1;
        end
    end

    task bus_step(input [2:0] op, input [15:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            {bus_we, bus_re, bus_rack} = op;
            bus_addr = addr;
            bus_wdata = data;
            @(posedge clk);
            #1;
        end
    endtask

    task write_addr(input [15:0] addr, input [7:0] data);
        begin
            bus_step(3'b100, addr, data);
        end
    endtask

    task read_addr(input [15:0] addr, output reg [7:0] data);
        begin
            bus_step(3'b010, addr, 8'h00);
            data = bus_rdata;
        end
    endtask

    task inject_rx(input [7:0] data);
        begin
            @(negedge clk);
            {bus_we, bus_re, bus_rack} = 3'b000;
            rx_data = data;
            rx_push = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            rx_push = 1'b0;
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

    function [15:0] crc_model;
        input [15:0] old;
        input [7:0] data;
        reg [15:0] accum;
        reg bit_in;
        integer n;
        begin
            accum = old;
            for (n = 7; n >= 0; n = n - 1) begin
                bit_in = accum[15] ^ data[n];
                accum = {accum[14:0], 1'b0};
                if (bit_in)
                    accum = accum ^ 16'h1021;
            end
            crc_model = accum;
        end
    endfunction

    function [7:0] field_mask;
        input [7:0] bank, offset;
        begin
            field_mask = 8'h00;
            case (bank)
                8'h01: begin
                    case (offset)
                        8'h00, 8'h01, 8'h10, 8'h11: field_mask = 8'hff;
                        8'h05: field_mask = 8'h07;
                        8'h08, 8'h12: field_mask = 8'h03;
                        default: if (offset <= 8'h12) field_mask = 8'h1f;
                    endcase
                end
                8'h02: begin
                    if (offset < 8'h20) begin
                        if ((offset % 8) <= 3)
                            field_mask = 8'hff;
                        else if ((offset % 8) == 4)
                            field_mask = 8'h07;
                    end else begin
                        case (offset)
                            8'h20: field_mask = 8'hff;
                            8'h21: field_mask = 8'h03;
                            8'h22: field_mask = 8'h07;
                            8'h24: field_mask = 8'hf1;
                            8'h25, 8'h26: field_mask = 8'h1f;
                            default: begin end
                        endcase
                    end
                end
                8'h03: begin
                    if (offset < 8'h20) begin
                        if ((offset % 4) <= 1)
                            field_mask = 8'hff;
                        else if ((offset % 4) == 2)
                            field_mask = 8'h1f;
                    end else if (offset <= 8'h29)
                        field_mask = 8'hff;
                    else if (offset == 8'h2a)
                        field_mask = 8'h07;
                end
                8'h04: if (offset <= 8'h13) field_mask = 8'h7f;
                default: begin end
            endcase
        end
    endfunction

    task check_bank(input [7:0] bank, input integer last, input [8*48:1] name);
        integer i;
        reg [7:0] data, result;
        reg good;
        begin
            good = 1'b1;
            for (i = 0; i <= last; i = i + 1) begin
                data = 8'had ^ i[7:0];
                write_addr({bank, i[7:0]}, data);
                read_addr({bank, i[7:0]}, result);
                good = good && (result === (data & field_mask(bank, i[7:0])));
            end
            check(name, good);
        end
    endtask

    task wait_validation;
        integer cycles_waited;
        begin
            for (cycles_waited = 0; (cycles_waited < 32) && (state === VALIDATING);
                 cycles_waited = cycles_waited + 1)
                bus_step(3'b000, 16'h0000, 8'h00);
        end
    endtask

    task write_crc(input [15:0] assumed_crc);
        begin
            write_addr(16'h0f08, assumed_crc[7:0]);
            write_addr(16'h0f09, assumed_crc[15:8]);
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_cfg_a CHECKS=%0d", N_CHECKS);
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_cfg_a.vcd");
            $dumpvars(0, tb_cfg_a);
        end
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        read_addr(STATUS, actual);
        check("RESET_STATE_HALT", (state === HALT) && (actual === 8'h00));

        write_addr(16'h0100, 8'h9b);
        write_addr(16'h0101, 8'hab);
        read_addr(16'h0100, actual);
        check("WH_WRITE_HALT_OK", actual === 8'h9b);
        @(negedge clk);
        bus_addr = 16'h0101;
        bus_re = 1'b1;
        #1;
        ok = bus_rdata === 8'h9b;
        @(posedge clk);
        #1;
        ok = ok && (bus_rdata === 8'hab);
        bus_step(3'b000, 16'h0100, 8'h00);
        check("READ_LATENCY_1", ok && (bus_rdata === 8'hab));

        read_addr(16'haccd, actual);
        check("UNMAPPED_READ_ZERO", actual === 8'h00);
        write_addr(16'haccd, 8'h71);
        read_addr(STATUS, actual);
        check("UNMAPPED_WRITE_REJ", actual[3] === 1'b1);
        write_addr(CTRL, 8'h01);
        write_addr(CTRL, 8'h03);
        read_addr(STATUS, actual);
        check("ENABLE_FROM_HALT_REJ", (state === HALT) && (actual[3] === 1'b1) && (enable_pulse === 1'b0));
        write_addr(CTRL, 8'h04);
        ok = clears == 1;

        check_bank(8'h01, 18, "REGISTER_ROUNDTRIP_ENGINE");
        check_bank(8'h02, 38, "REGISTER_ROUNDTRIP_FABRIC");
        check_bank(8'h03, 42, "REGISTER_ROUNDTRIP_MONITOR");
        check_bank(8'h04, 19, "REGISTER_ROUNDTRIP_PINS");

        // Start lifecycle checks from a legal image after exercising all field bits.
        @(negedge clk);
        rst_n = 1'b0;
        {bus_we, bus_re, bus_rack} = 3'b000;
        @(negedge clk);
        rst_n = 1'b1;
        write_addr(CTRL, 8'h01);
        write_addr(16'h0000, 8'h00);
        write_addr(16'h0001, 8'h00);
        write_addr(16'h0100, 8'h2c);
        write_addr(16'h0102, 8'h93);
        write_addr(16'h0f0a, 8'h65);
        crc_expected = crc_model(crc_model(16'hffff, 8'h00), 8'h00);
        crc_expected = crc_model(crc_model(crc_model(crc_expected, 8'h2c), 8'h93), 8'h65);
        write_crc(crc_expected);
        read_addr(16'h0f06, low_byte);
        read_addr(16'h0f07, high_byte);
        write_addr(CTRL, 8'h02);
        earlier = state === VALIDATING;
        wait_validation;
        read_addr(STATUS, actual);
        check("CRC_MATCH_READY", earlier && ({high_byte, low_byte} === crc_expected) &&
              (state === READY) && (actual[6] === 1'b1));

        write_addr(TX, 8'h88);
        write_addr(CTRL, 8'h03);
        earlier = (state === RUN) && (enable_pulse === 1'b1) && (tx_level === 3'd1);
        bus_step(3'b000, 16'h0000, 8'h00);
        check("ENABLE_PULSE_WIDTH_1", earlier && (enable_pulse === 1'b0) && (enables == 1));
        write_addr(16'h0100, 8'h55);
        read_addr(16'h0100, actual);
        earlier = actual === 8'h2c;
        read_addr(STATUS, actual);
        check("WH_WRITE_RUN_REJECTED", earlier && (actual[3] === 1'b1));
        write_addr(CTRL, 8'h04);
        check("CLR_IMEM_ONLY_HALT", ok && (clears == 1));

        @(negedge clk);
        {bus_we, bus_re, bus_rack} = 3'b000;
        eng_done_req = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        eng_done_req = 1'b0;
        read_addr(16'h0f02, actual);
        check("ENGINE_DONE_TO_DONE", (state === DONE) && (actual === 8'h01));
        write_addr(CTRL, 8'h05);
        check("CLR_FAULT_TO_HALT", state === HALT);

        write_addr(CTRL, 8'h01);
        write_crc(16'hffff);
        write_addr(CTRL, 8'h02);
        wait_validation;
        write_addr(CTRL, 8'h03);
        @(negedge clk);
        {bus_we, bus_re, bus_rack} = 3'b000;
        eng_fault_req = 1'b1;
        eng_fault_code = 4'd3;
        eng_pc = 5'd19;
        fault_expected = clock_cycles;
        @(posedge clk);
        #1;
        @(negedge clk);
        eng_fault_req = 1'b0;
        read_addr(16'h0f02, actual);
        earlier = actual === 8'h03;
        read_addr(16'h0f03, actual);
        earlier = earlier && (actual === 8'h13);
        read_addr(16'h0f04, low_byte);
        read_addr(16'h0f05, high_byte);
        check("ENGINE_FAULT_LATCH", earlier && (state === FAULT) && ({high_byte, low_byte} === fault_expected));

        write_addr(CTRL, 8'h01);
        write_crc(16'h0000);
        write_addr(CTRL, 8'h02);
        wait_validation;
        read_addr(16'h0f02, actual);
        check("CRC_MISMATCH_FAULT", (state === FAULT) && (actual === 8'h05));

        repeat (5) write_addr(TX, 8'h41);
        bus_step(3'b000, 16'h0000, 8'h00);
        read_addr(STATUS, actual);
        check("TXFIFO_PUSH_OVF", (tx_level === 3'd4) && (actual[4] === 1'b1));
        inject_rx(8'ha2);
        inject_rx(8'h37);
        read_addr(RX, actual);
        earlier = (actual === 8'ha2) && (rx_level === 3'd2);
        read_addr(RX, actual);
        check("RXFIFO_PEEK_NO_POP_ON_RE", earlier && (actual === 8'ha2) && (rx_level === 3'd2));
        bus_step(3'b001, RX, 8'h00);
        read_addr(RX, actual);
        check("RXFIFO_POP_ON_RACK", (actual === 8'h37) && (rx_level === 3'd1));
        bus_step(3'b001, RX, 8'h00);
        bus_step(3'b001, RX, 8'h00);
        inject_rx(8'hda);
        write_addr(16'hff72, 8'h31);
        read_addr(STATUS, actual);
        earlier = actual[5:3] === 3'b111;
        write_addr(CTRL, 8'h01);
        read_addr(STATUS, actual);
        check("HALT_CLEARS_STICKY", earlier && (actual[5:3] === 3'b000));
        read_addr(16'h0f12, actual);
        earlier = (actual === 8'h00) && (tx_level === 3'd0) && (rx_level === 3'd0);
        read_addr(RX, actual);
        earlier = earlier && (actual === 8'h00);
        // RX underflow is a side effect only of the completed read acknowledgement.
        read_addr(STATUS, actual);
        earlier = earlier && (actual[5] === 1'b0);
        bus_step(3'b001, RX, 8'h00);
        bus_step(3'b000, 16'h0000, 8'h00);
        read_addr(STATUS, actual);
        check("HALT_CLEARS_FIFOS", earlier && (actual[5] === 1'b1));

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == N_CHECKS) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #20000;
        $display("TB_TIMEOUT cfg_a");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
