`timescale 1ns/1ps
`default_nettype none

// S10, 40 frozen checks. Expected outcomes are independent of the DUT; ISS pending.
module tb_engine_b;
    localparam [15:0] PULL_BLOCK = 16'h80a0, PULL_NONBLOCK = 16'h8080,
                      PUSH_BLOCK = 16'h8020, PUSH_NONBLOCK = 16'h8000,
                      MOV_PINS_OSR = 16'ha006, MOV_PINS_ISR = 16'ha005,
                      MOV_OSR_PINS = 16'ha0c0;

    reg clk = 1'b0;
    reg rst_n = 1'b0, run = 1'b0, enable_pulse = 1'b0;
    reg [15:0] clkdiv, timeout;
    reg [4:0] out_base, out_cnt, in_base, side_base, wrap_bottom, wrap_top;
    reg [4:0] push_thresh, pull_thresh;
    reg [1:0] side_cnt;
    reg wide, in_shr, out_shr, autopull, autopush;
    reg [19:0] pin_in;
    reg [15:0] words [0:31];
    reg [31:0] valid;
    wire [4:0] rd_pc, eng_pc;
    wire [19:0] out_val, oe_val;
    wire engine_tick, eng_done_req, eng_fault_req;
    wire [3:0] eng_fault_code;
    wire tx_empty, rx_full, tx_pop, rx_push;
    wire [7:0] tx_dout, rx_din, rx_head;
    wire [2:0] tx_level, rx_level;

    reg host_tx_push = 1'b0, host_rx_pop = 1'b0, seed_rx_push = 1'b0;
    reg [7:0] host_tx_data, seed_rx_data;
    reg sampled_tick, sampled_pop, sampled_push;
    reg [7:0] sampled_rx_data;
    integer pops, pushes;
    integer checks = 0, errors = 0, i, mode, tick_number;
    reg good, bit_at_line;
    reg [7:0] read_byte, uart_bits;

    always #10 clk = ~clk;
    always @(posedge clk) begin
        sampled_tick <= engine_tick;
        sampled_pop <= tx_pop;
        sampled_push <= rx_push;
        sampled_rx_data <= rx_din;
        if (!rst_n) begin
            pops <= 0;
            pushes <= 0;
        end else begin
            if (tx_pop) pops <= pops + 1;
            if (rx_push) pushes <= pushes + 1;
        end
    end

    pvm_fifo tx_fifo (
        .clk(clk), .rst_n(rst_n), .clr(1'b0), .push(host_tx_push), .din(host_tx_data),
        .pop(tx_pop), .dout(tx_dout), .full(), .empty(tx_empty), .level(tx_level), .ovf(), .unf()
    );
    pvm_fifo rx_fifo (
        .clk(clk), .rst_n(rst_n), .clr(1'b0), .push(rx_push || seed_rx_push),
        .din(seed_rx_push ? seed_rx_data : rx_din), .pop(host_rx_pop), .dout(rx_head),
        .full(rx_full), .empty(), .level(rx_level), .ovf(), .unf()
    );

    pvm_engine dut (
        .clk(clk), .rst_n(rst_n), .run(run), .enable_pulse(enable_pulse), .clkdiv(clkdiv),
        .entry_pc(5'd0), .wrap_bottom(wrap_bottom), .wrap_top(wrap_top),
        .out_base(out_base), .out_cnt(out_cnt), .set_base(5'd12), .set_cnt(3'd1),
        .in_base(in_base), .side_base(side_base), .side_cnt(side_cnt), .jmp_pin(5'd0),
        .wide(wide), .pull_thresh(pull_thresh), .push_thresh(push_thresh),
        .out_shr(out_shr), .in_shr(in_shr), .autopull(autopull), .autopush(autopush),
        .timeout(timeout), .to_presc(2'd0), .instr(words[rd_pc]), .instr_valid(valid[rd_pc]),
        .pin_in(pin_in), .lut_out(4'd0), .arb_lost(1'b0), .underrun(1'b0),
        .tx_empty(tx_empty), .rx_full(rx_full), .tx_level(tx_level), .rx_level(rx_level),
        .tx_dout(tx_dout), .tx_pop(tx_pop), .rx_push(rx_push), .rx_din(rx_din),
        .rd_pc(rd_pc), .out_val(out_val), .oe_val(oe_val), .fab_ctrl(), .fab_wr(),
        .user_flags(), .evt_clr_arb(), .evt_clr_unf(), .engine_tick(engine_tick),
        .eng_pc(eng_pc), .eng_done_req(eng_done_req), .eng_fault_req(eng_fault_req),
        .eng_fault_code(eng_fault_code)
    );

    pvm_trace trace (
        .clk(clk), .run_state({2'b00, run}), .pc(eng_pc),
        .instr_valid(dut.issue_cycle && !dut.invalid_fetch),
        .out_val(out_val), .oe_val(oe_val), .fab_ctrl(dut.fab_ctrl), .fab_wr(dut.fab_wr),
        .tx_pop(tx_pop), .rx_push(rx_push), .rx_din(rx_din),
        .fault_req(eng_fault_req), .fault_code(eng_fault_code)
    );

    task edge_cycle;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task tick;
        begin
            edge_cycle;
            while (sampled_tick !== 1'b1) edge_cycle;
        end
    endtask

    task prepare;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            run = 1'b0;
            enable_pulse = 1'b0;
            clkdiv = 16'd1;
            timeout = 16'd0;
            out_base = 5'd0;
            out_cnt = 5'd16;
            in_base = 5'd0;
            side_base = 5'd17;
            wrap_bottom = 5'd0;
            wrap_top = 5'd31;
            side_cnt = 2'd0;
            wide = 1'b0;
            in_shr = 1'b0;
            out_shr = 1'b1;
            autopull = 1'b0;
            autopush = 1'b0;
            pull_thresh = 5'd0;
            push_thresh = 5'd0;
            pin_in = 20'd0;
            valid = 32'd0;
            host_tx_push = 1'b0;
            host_rx_pop = 1'b0;
            seed_rx_push = 1'b0;
            edge_cycle;
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task load(input [4:0] address, input [15:0] instruction);
        begin
            words[address] = instruction;
            valid[address] = 1'b1;
        end
    endtask

    task start;
        begin
            @(negedge clk);
            run = 1'b1;
            enable_pulse = 1'b1;
            edge_cycle;
            @(negedge clk);
            enable_pulse = 1'b0;
        end
    endtask

    task tx_put(input [7:0] value);
        begin
            @(negedge clk);
            host_tx_data = value;
            host_tx_push = 1'b1;
            edge_cycle;
            @(negedge clk);
            host_tx_push = 1'b0;
        end
    endtask

    task rx_seed(input integer entries);
        integer n;
        begin
            for (n = 0; n < entries; n = n+1) begin
                @(negedge clk);
                seed_rx_data = 8'hd0 + n[7:0];
                seed_rx_push = 1'b1;
                edge_cycle;
            end
            @(negedge clk);
            seed_rx_push = 1'b0;
        end
    endtask

    task rx_take(output reg [7:0] value);
        begin
            @(negedge clk);
            value = rx_head;
            host_rx_pop = 1'b1;
            edge_cycle;
            @(negedge clk);
            host_rx_pop = 1'b0;
        end
    endtask

    task check(input [8*48:1] name, input passed);
        begin
            checks = checks + 1;
            if (passed === 1'b1)
                $display("[PASS] %0s", name);
            else begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    task out_order(input [8*48:1] name, input shift_right);
        integer bit_index;
        reg pass;
        reg [7:0] payload;
        begin
            prepare;
            out_shr = shift_right;
            out_cnt = 5'd1;
            payload = 8'h35;
            load(5'd0, PULL_BLOCK);
            for (bit_index=1; bit_index<=8; bit_index=bit_index+1)
                load(bit_index[4:0], 16'h6001);
            tx_put(payload);
            start;
            tick;
            pass = (pops == 1);
            for (bit_index=0; bit_index<8; bit_index=bit_index+1) begin
                tick;
                pass = pass && (out_val[0] === payload[shift_right ? bit_index : 7-bit_index]);
            end
            check(name, pass);
        end
    endtask

    task in_order(input [8*48:1] name, input shift_right, input [15:0] expected);
        begin
            prepare;
            in_shr = shift_right;
            pin_in = 20'h00005;
            load(5'd0, 16'h4004);
            load(5'd1, 16'h4004);
            load(5'd2, MOV_PINS_ISR);
            start;
            tick;
            @(negedge clk);
            pin_in = 20'h0000a;
            repeat (2) tick;
            check(name, out_val[15:0] === expected);
        end
    endtask

    function [15:0] reverse16(input [15:0] data);
        integer b;
        begin
            for (b=0; b<16; b=b+1) reverse16[b] = data[15-b];
        end
    endfunction

    task exec_setup(input mov_parent, input [15:0] injected,
                    input [3:0] parent_delay, input wrap_parent, input reverse_op);
        reg [7:0] mov_operand;
        begin
            prepare;
            side_cnt = 2'd1;
            if (wrap_parent) begin
                wrap_top = 5'd1;
                wrap_bottom = 5'd7;
            end
            if (injected == PUSH_BLOCK)
                rx_seed(4);
            if (mov_parent) begin
                mov_operand = reverse_op ? 8'h71 : 8'h69;
                pin_in[15:0] = reverse_op ? reverse16(injected) : ~injected;
                load(5'd0, 16'ha020); // MOV X,PINS
                load(5'd1, {3'b101, 1'b0, parent_delay, mov_operand});
            end else begin
                pin_in[15:0] = injected;
                load(5'd0, MOV_OSR_PINS);
                load(5'd1, {3'b011, 1'b0, parent_delay, 8'he0}); // OUT EXEC,16
            end
            load(5'd2, MOV_PINS_OSR);
            start;
            tick;
        end
    endtask

    task exec_suite(input mov_parent, input [8*24:1] prefix);
        reg pass;
        reg [7:0] discarded;
        begin
            exec_setup(mov_parent, 16'he101, 4'd2, 1'b0, 1'b0);
            tick;
            pass = (eng_pc === 5'd1) && (out_val[12] === 1'b0);
            @(negedge clk);
            valid[1] = 1'b0; // Injection bypasses the IMEM-valid check.
            repeat (2) begin
                tick;
                pass = pass && (eng_pc === 5'd1) && (out_val[12] === 1'b0);
            end
            tick;
            pass = pass && (eng_pc === 5'd1) && (out_val[12] === 1'b1);
            tick;
            check({prefix, "_PARENT_AND_INJECTED_DELAY"}, pass && (eng_pc === 5'd2));

            exec_setup(mov_parent, 16'he001, 4'd0, 1'b1, 1'b1);
            tick;
            pass = (eng_pc === 5'd1) && (out_val[12] === 1'b0);
            tick;
            check({prefix, "_WRAP"}, pass && (eng_pc === 5'd7) && (out_val[12] === 1'b1));

            exec_setup(mov_parent, 16'h000b, 4'd0, 1'b1, 1'b0);
            tick;
            pass = eng_pc === 5'd1;
            tick;
            check({prefix, "_JUMP"}, pass && (eng_pc === 5'd11));

            exec_setup(mov_parent, 16'h3092, 4'd1, 1'b0, 1'b0); // WAIT 1 PIN 18 SIDE 1
            repeat (2) tick;
            pass = (eng_pc === 5'd1) && (out_val[17] === 1'b0);
            repeat (3) begin
                tick;
                pass = pass && (eng_pc === 5'd1) && (out_val[17] === 1'b1) && !eng_fault_req;
            end
            @(negedge clk);
            pin_in[18] = 1'b1;
            tick;
            check({prefix, "_SIDESET_WAIT"}, pass && (eng_pc === 5'd2));

            exec_setup(mov_parent, mov_parent ? 16'h60e0 : 16'ha061, 4'd0, 1'b0, 1'b0);
            repeat (2) tick;
            check({prefix, "_NESTED_FAULT"}, eng_fault_req && (eng_fault_code === 4'd3) && (eng_pc === 5'd1));

            exec_setup(mov_parent, 16'he060, 4'd0, 1'b0, 1'b0);
            repeat (2) tick;
            check({prefix, "_ILLEGAL_FAULT"}, eng_fault_req && (eng_fault_code === 4'd3) && (eng_pc === 5'd1));

            exec_setup(mov_parent, 16'h2092, 4'd0, 1'b0, 1'b0);
            @(negedge clk);
            timeout = 16'd3;
            tick; // Parent
            repeat (2) tick;
            pass = (eng_pc === 5'd1) && !eng_fault_req;
            tick;
            check({prefix, "_WAIT_TIMEOUT"}, pass && eng_fault_req &&
                  (eng_fault_code === 4'd2) && (eng_pc === 5'd1));

            exec_setup(mov_parent, mov_parent ? PUSH_BLOCK : PULL_BLOCK, 4'd0, 1'b0, 1'b0);
            repeat (3) tick;
            pass = (eng_pc === 5'd1) && (pops == 0) && (pushes == 0) && !eng_fault_req;
            if (mov_parent)
                rx_take(discarded);
            else
                tx_put(8'hb7);
            tick;
            pass = pass && (eng_pc === 5'd2);
            if (mov_parent)
                pass = pass && (pushes == 1) && (sampled_rx_data === 8'h00);
            else begin
                pass = pass && (pops == 1);
                tick;
                pass = pass && (out_val[15:0] === 16'h00b7);
            end
            check({prefix, "_BLOCKING_FIFO"}, pass);
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_engine_b CHECKS=40");
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_engine_b.vcd");
            $dumpvars(0, tb_engine_b);
        end

        prepare;
        load(5'd0, PULL_BLOCK);
        load(5'd1, MOV_PINS_OSR);
        start;
        tick;
        good = (pops == 0) && (eng_pc === 5'd0);
        tx_put(8'h5a);
        tick;
        good = good && (eng_pc === 5'd1) && (pops == 1);
        tick;
        check("PULL_BLOCK_STALL_THEN_GO", good && (out_val[15:0] === 16'h005a));

        prepare;
        load(5'd0, 16'he035); // SET X,21
        load(5'd1, PULL_NONBLOCK);
        load(5'd2, MOV_PINS_OSR);
        start;
        repeat (3) tick;
        check("PULL_NONBLOCK_EMPTY_COPIES_X", (out_val[15:0] === 16'h0015) && (pops == 0));

        prepare;
        load(5'd0, PULL_BLOCK);
        load(5'd1, 16'h80e0); // PULL IFEMPTY BLOCK
        load(5'd2, MOV_PINS_OSR);
        tx_put(8'h3a);
        tx_put(8'hf1);
        start;
        repeat (3) tick;
        check("PULL_IFEMPTY_SKIP", (pops == 1) && (tx_level === 3'd1) && (out_val[15:0] === 16'h003a));

        prepare;
        pin_in = 20'h0005a;
        load(5'd0, 16'h4008);
        load(5'd1, PUSH_BLOCK);
        load(5'd2, MOV_PINS_ISR);
        rx_seed(4);
        start;
        repeat (2) tick;
        good = (eng_pc === 5'd1) && (pushes == 0);
        rx_take(read_byte);
        tick;
        check("PUSH_BLOCK_FULL_STALL", good && (eng_pc === 5'd2) && (pushes == 1) &&
              (sampled_rx_data === 8'h5a) && (rx_level === 3'd4));

        prepare;
        pin_in = 20'h000a5;
        load(5'd0, 16'h4008);
        load(5'd1, PUSH_NONBLOCK);
        load(5'd2, MOV_PINS_ISR);
        rx_seed(4);
        start;
        repeat (3) tick;
        check("PUSH_NONBLOCK_DROP", (eng_pc === 5'd3) && (pushes == 0) &&
              (out_val[15:0] === 16'h0000) && (rx_level === 3'd4));

        prepare;
        pin_in = 20'h00005;
        load(5'd0, 16'h4004);
        load(5'd1, 16'h8060);
        load(5'd2, 16'h4004);
        load(5'd3, 16'h8060);
        start;
        repeat (2) tick;
        good = (eng_pc === 5'd2) && (pushes == 0);
        repeat (2) tick;
        check("PUSH_IFFULL", good && (pushes == 1) && (rx_head === 8'h55));

        out_order("OUT_SHR_LSB_FIRST", 1'b1);
        out_order("OUT_SHL_MSB_FIRST", 1'b0);

        prepare;
        pin_in = 20'h0a53e;
        load(5'd0, MOV_OSR_PINS);
        load(5'd1, 16'h6000);
        load(5'd2, MOV_PINS_OSR);
        start;
        repeat (2) tick;
        good = out_val[15:0] === 16'ha53e;
        tick;
        check("OUT_COUNT_16", good && (out_val[15:0] === 16'h0000));

        prepare;
        out_base = 5'd17;
        out_cnt = 5'd4;
        pin_in = 20'h0000a;
        load(5'd0, MOV_OSR_PINS);
        load(5'd1, 16'h6084);
        start;
        repeat (2) tick;
        check("OUT_PINDIRS", (oe_val === 20'h40001) && (out_val === 20'd0));

        prepare;
        pin_in = 20'h00013;
        load(5'd0, MOV_OSR_PINS);
        load(5'd1, 16'h60a5);
        start;
        repeat (2) tick;
        check("OUT_PC", eng_pc === 5'd19);

        prepare;
        in_base = 5'd19;
        pin_in = 20'h80003;
        load(5'd0, 16'h4003);
        load(5'd1, MOV_PINS_ISR);
        start;
        repeat (2) tick;
        check("IN_PINS_BASE", out_val[15:0] === 16'h0007);

        in_order("IN_SHR", 1'b1, 16'ha500);
        in_order("IN_SHL", 1'b0, 16'h005a);

        prepare;
        out_cnt = 5'd4;
        autopull = 1'b1;
        load(5'd0, 16'h6004);
        load(5'd1, 16'h6004);
        load(5'd2, 16'h6004);
        tx_put(8'he1);
        tx_put(8'ha6);
        start;
        tick;
        good = (out_val[3:0] === 4'h1) && (pops == 1);
        tick;
        good = good && (out_val[3:0] === 4'he) && (pops == 1);
        tick;
        check("AUTOPULL_THRESH_8", good && (out_val[3:0] === 4'h6) && (pops == 2));

        prepare;
        autopush = 1'b1;
        pin_in = 20'h00005;
        load(5'd0, 16'h4004);
        load(5'd1, 16'h4004);
        start;
        tick;
        good = pushes == 0;
        @(negedge clk);
        pin_in = 20'h0000a;
        tick;
        check("AUTOPUSH_THRESH_8", good && (pushes == 1) && (rx_head === 8'h5a));

        prepare;
        clkdiv = 16'd3;
        wide = 1'b1;
        load(5'd0, PULL_BLOCK);
        load(5'd1, MOV_PINS_OSR);
        tx_put(8'h5b);
        tx_put(8'ha6);
        start;
        tick;
        good = (eng_pc === 5'd0) && (tx_level === 3'd1) && sampled_pop;
        repeat (2) begin
            edge_cycle;
            good = good && !sampled_pop && (eng_pc === 5'd0) && (tx_level === 3'd1);
        end
        edge_cycle;
        good = good && sampled_tick && sampled_pop && (eng_pc === 5'd1) && (tx_level === 3'd0);
        tick;
        check("WIDE_PULL_2BYTES_LE", good && (out_val[15:0] === 16'ha65b));

        prepare;
        wide = 1'b1;
        clkdiv = 16'd3;
        pin_in = 20'h0913c;
        load(5'd0, 16'h4000);
        load(5'd1, PUSH_BLOCK);
        load(5'd2, 16'h0002);
        rx_seed(3);
        start;
        repeat (2) tick;
        good = (eng_pc === 5'd1) && (pushes == 0) && (rx_level === 3'd3);
        rx_take(read_byte);
        good = good && (read_byte === 8'hd0);
        tick;
        good = good && (eng_pc === 5'd1) && (pushes == 1) && (sampled_rx_data === 8'h3c);
        rx_take(read_byte); // Host read between the two beats
        good = good && (read_byte === 8'hd1);
        edge_cycle;
        good = good && !sampled_push && (eng_pc === 5'd1);
        edge_cycle;
        good = good && sampled_tick && (eng_pc === 5'd2) && (pushes == 2) && (sampled_rx_data === 8'h91);
        rx_take(read_byte); good = good && (read_byte === 8'hd2);
        rx_take(read_byte); good = good && (read_byte === 8'h3c);
        rx_take(read_byte);
        check("WIDE_PUSH_NEEDS_2_SLOTS", good && (read_byte === 8'h91));

        prepare;
        wide = 1'b1;
        clkdiv = 16'd3;
        load(5'd0, PULL_NONBLOCK);
        tx_put(8'h1a);
        start;
        repeat (2) tick;
        good = (tx_level === 3'd1) && (pops == 0) && (eng_pc === 5'd0);
        tx_put(8'h2b);
        tick;
        good = good && (pops == 1) && (eng_pc === 5'd0);
        tick;
        check("WIDE_NO_PARTIAL_STALL", good && (pops == 2) && (eng_pc === 5'd1));

        prepare;
        wide = 1'b1;
        autopull = 1'b1;
        load(5'd0, 16'h6100); // OUT PINS,16 [1]
        tx_put(8'h72);
        tx_put(8'hd6);
        start;
        tick;
        good = (eng_pc === 5'd0) && (pops == 1) && (out_val[15:0] === 16'h0000);
        tick;
        good = good && (eng_pc === 5'd0) && (pops == 2) && (out_val[15:0] === 16'hd672);
        tick;
        check("WIDE_AUTOPULL", good && (eng_pc === 5'd1));

        prepare;
        wide = 1'b1;
        autopush = 1'b1;
        pin_in = 20'h0bc4e;
        load(5'd0, 16'h4000);
        start;
        tick;
        good = (eng_pc === 5'd0) && (pushes == 1) && (sampled_rx_data === 8'h4e);
        @(negedge clk);
        pin_in = 20'h07468;
        tick;
        check("WIDE_AUTOPUSH", good && (eng_pc === 5'd1) && (pushes == 2) && (sampled_rx_data === 8'hbc));

        prepare;
        load(5'd0, 16'h00e4); // One JMP 7 revisited after PULL
        load(5'd1, PULL_BLOCK);
        load(5'd2, 16'h0000);
        tx_put(8'h33);
        start;
        tick;
        good = eng_pc === 5'd1;
        repeat (2) tick;
        good = good && (eng_pc === 5'd0) && (pops == 1);
        tick;
        check("JMP_COND_7_TAKEN", good && (eng_pc === 5'd4));

        exec_suite(1'b0, "OUT_EXEC");
        exec_suite(1'b1, "MOV_EXEC");

        prepare;
        clkdiv = 16'd3;
        out_base = 5'd12;
        out_cnt = 5'd1;
        load(5'd0, 16'he001); // Idle high
        load(5'd1, PULL_BLOCK);
        load(5'd2, 16'he027); // X = 7
        load(5'd3, 16'he100); // Start low, 2 ticks
        load(5'd4, 16'h6001); // Data bit, LSB first
        load(5'd5, 16'h0044); // JMP X--,4
        load(5'd6, 16'he101); // Stop high
        load(5'd7, 16'h0007);
        tx_put(8'h35);
        start;
        repeat (3) tick;
        good = out_val[12] === 1'b1;
        uart_bits = 8'h00;
        for (i=1; i<=60; i=i+1) begin
            edge_cycle;
            tick_number = i / 3;
            if (tick_number == 0 || tick_number >= 19)
                bit_at_line = 1'b1;
            else if (tick_number < 3)
                bit_at_line = 1'b0;
            else
                bit_at_line = (8'h35 >> ((tick_number-3)/2)) & 1;
            good = good && (out_val[12] === bit_at_line);
            if (tick_number >= 3 && tick_number < 19 && ((tick_number-3)%2 == 0) && i%3 == 0)
                uart_bits[(tick_number-3)/2] = out_val[12];
        end
        check("UART_TX_0x35_WAVEFORM", good && (uart_bits === 8'h35));

        prepare;
        in_shr = 1'b1;
        in_base = 5'd12;
        pin_in[12] = 1'b1;
        load(5'd0, 16'h200c); // WAIT 0 PIN 12
        for (i=1; i<=8; i=i+1)
            load(i[4:0], 16'h4001);
        load(5'd9, 16'h4068); // IN NULL,8 aligns the eight sampled bits at ISR[7:0].
        load(5'd10, PUSH_BLOCK);
        start;
        tick;
        good = eng_pc === 5'd0;
        @(negedge clk);
        pin_in[12] = 1'b0;
        tick;
        for (i=0; i<8; i=i+1) begin
            @(negedge clk);
            pin_in[12] = uart_bits[i];
            tick;
        end
        repeat (2) tick;
        check("UART_RX_LOOPBACK", good && (pushes == 1) && (rx_head === 8'h35));

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == 40) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #200000;
        $display("TB_TIMEOUT engine_b");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
