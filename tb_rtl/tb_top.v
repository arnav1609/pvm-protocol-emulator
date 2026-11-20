`timescale 1ns/1ps
`default_nettype none

// Exercise the public SPI and GPIO interface of the Tiny Tapeout wrapper.
module tb_top;
    localparam [15:0] CTRL = 16'h0f00;
`ifdef PVM_MON_NON_INTRUSION
    localparam integer N_CHECKS = 1;
`else
    localparam integer N_CHECKS = 3;
`endif
    localparam [7:0] UART_DATA = 8'h35, SPI_DATA = 8'ha6;
    reg clk = 1'b0, rst_n = 1'b0;
    reg [7:0] ui = 8'h02;
    wire [7:0] uo, uio_out, uio_oe;
    reg [15:0] crc;
    reg [7:0] serial_rx, status, code, value, log_entry, log_status, mon_count;
    integer checks = 0, errors = 0;
    integer sample_index, bit_index, wait_cycles;
    reg pass, ready, expected_line;

    always #10 clk = ~clk;
    tt_um_arnav1609_pvm dut (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(ui), .uio_in(8'h00),
        .uo_out(uo), .uio_out(uio_out), .uio_oe(uio_oe)
    );

    task edge_sample;
        begin @(posedge clk); #1; end
    endtask

    task set_select(input selected);
        begin
            @(negedge clk);
            ui[1] = !selected;
            repeat (8) @(negedge clk);
        end
    endtask

    task spi_byte(input [7:0] mosi, output reg [7:0] miso);
        integer bit_index;
        begin
            for (bit_index=7;bit_index>=0;bit_index=bit_index-1) begin
                ui[2] = mosi[bit_index];
                repeat (8) @(negedge clk);
                ui[0] = 1'b1;
                #1;
                miso[bit_index] = uo[7];
                repeat (8) @(negedge clk);
                ui[0] = 1'b0;
            end
        end
    endtask

    task open_frame(input [7:0] command, input [15:0] addr);
        reg [7:0] ignored;
        begin
            set_select(1'b1);
            spi_byte(command, ignored);
            spi_byte(addr[15:8], ignored);
            spi_byte(addr[7:0], ignored);
        end
    endtask

    task write_register(input [15:0] addr, input [7:0] data);
        begin
            open_frame(8'h02, addr);
            spi_byte(data, serial_rx);
            set_select(1'b0);
        end
    endtask

    task read_register(input [15:0] addr, output reg [7:0] data);
        begin
            open_frame(8'h03, addr);
            spi_byte(8'h00, data);
            spi_byte(8'h00, data);
            set_select(1'b0);
        end
    endtask

    function [15:0] crc_byte(input [15:0] seed, input [7:0] data);
        reg [15:0] state;
        integer n;
        begin
            state = seed ^ {data, 8'h00};
            for (n=0;n<8;n=n+1)
                state = (state << 1) ^ (state[15] ? 16'h1021 : 16'h0000);
            crc_byte = state;
        end
    endfunction

    task write_config(input [15:0] addr, input [7:0] data);
        begin
            write_register(addr, data);
            crc = crc_byte(crc, data);
        end
    endtask

    task write_word(input [4:0] addr, input [15:0] data);
        begin
            open_frame(8'h02, {10'd0, addr, 1'b0});
            spi_byte(data[7:0], serial_rx);
            spi_byte(data[15:8], serial_rx);
            set_select(1'b0);
            crc = crc_byte(crc_byte(crc, data[7:0]), data[15:8]);
        end
    endtask

    task reset_and_halt;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            ui = 8'h02;
            repeat (4) @(negedge clk);
            rst_n = 1'b1;
            write_register(CTRL, 8'h01);
            crc = 16'hffff;
        end
    endtask

    task validate_image(output reg ready);
        begin
            write_register(16'h0f08, crc[7:0]);
            write_register(16'h0f09, crc[15:8]);
            write_register(CTRL, 8'h02);
            read_register(16'h0f01, status);
            ready = (status === 8'h42);
        end
    endtask

    task new_image;
        begin
            write_register(CTRL, 8'h01);
            write_register(CTRL, 8'h04);
            crc = 16'hffff;
        end
    endtask

    task uart_image(input [7:0] monitor_cfg);
        begin
            write_word(0, 16'he001); // Idle high
            write_word(1, 16'he0c1); // SET FAB, 1
            write_word(2, 16'h80a0); // PULL BLOCK
            write_word(3, 16'he027); // SET X, 7
            write_word(4, 16'he100); // Start bit
            write_word(5, 16'h6001); // OUT PINS, 1
            write_word(6, 16'h0045); // JMP X--, 5
            write_word(7, 16'he101); // Stop bit
            write_word(8, 16'hc0c0); // EVT DONE
            write_config(16'h0100, 8'd64);
            write_config(16'h0102, 8'd5);
            write_config(16'h0103, 8'd1);
            write_config(16'h0104, 8'd5);
            write_config(16'h0105, 8'd1);
            write_config(16'h010b, 8'd8);
            write_config(16'h010c, 8'd1);
            write_config(16'h0200, 8'haa);
            write_config(16'h0201, 8'haa);
            write_config(16'h0202, 8'h08); // L0 follows FAB bit 0
            write_config(16'h0405, 8'h29); // P5 engine push-pull, idle high
            write_config(16'h0408, 8'h0b); // P8 fabric L0 push-pull
            write_config(16'h0300, 8'h08); // Rule 0: STATE 0 -> 1, rising edge
            write_config(16'h0301, 8'h85); // VALID, P5, always
            write_config(16'h0302, 8'h18); // PASS
            write_config(16'h032a, monitor_cfg);
            validate_image(ready);
            write_register(16'h0f10, UART_DATA);
            write_register(CTRL, 8'h03);
        end
    endtask

    task spi_image;
        begin
            write_word(0, 16'h80a0); // PULL BLOCK
            write_word(1, 16'he027); // SET X, 7
            write_word(2, 16'h6001); // Update MOSI with SCK low
            write_word(3, 16'h1042); // SCK high, JMP X--, 2
            write_word(4, 16'hc0c0); // SCK low and done
            write_config(16'h0100, 8'd32);
            write_config(16'h0102, 8'd7);
            write_config(16'h0107, 8'd6);
            write_config(16'h0108, 8'd1);
            write_config(16'h010b, 8'd4);
            write_config(16'h010c, 8'd0); // Shift left for MSB first
            write_config(16'h0405, 8'd0);
            write_config(16'h0406, 8'h0a);
            write_config(16'h0407, 8'h09);
            write_config(16'h032a, 8'd0);
            validate_image(ready);
            write_register(16'h0f10, SPI_DATA);
            write_register(CTRL, 8'h03);
        end
    endtask

    task complete_image;
        begin
            write_word(0, 16'hc0c0);
            validate_image(ready);
            write_register(CTRL, 8'h03);
            read_register(16'h0f01, status);
            read_register(16'h0f02, code);
        end
    endtask

    task wait_pin(input integer pin, input level, input integer limit, output reg reached);
        begin : pin_wait
            integer elapsed;
            for (elapsed = 0; elapsed < limit && uo[pin] !== level; elapsed = elapsed + 1)
                edge_sample;
            reached = uo[pin] === level;
        end
    endtask

    task check(input [8*48:1] name, input ok);
        begin
            checks = checks + 1;
            if (ok === 1'b1) $display("[PASS] %0s", name);
            else begin errors = errors + 1; $display("[FAIL] %0s", name); end
        end
    endtask

`ifdef PVM_MON_NON_INTRUSION
    wire [35:0] trace_signals = {uo[6:0], uio_out, uio_oe, dut.pvm.engine_pc,
                                 dut.pvm.tx_level, dut.pvm.rx_level,
                                 dut.pvm.engine_tick, dut.pvm.eng_fault_req};
    reg [35:0] trace_off [0:1999];
`endif
    initial begin : tests
        reg reached;
        $display("CONFIG: TOP=tb_top CHECKS=%0d", N_CHECKS);
`ifdef PVM_MON_NON_INTRUSION
        reset_and_halt;
        uart_image(0);
        pass = ready;
        for (sample_index = 0; sample_index < 2000; sample_index = sample_index + 1) begin
            edge_sample; trace_off[sample_index] = trace_signals;
        end
        read_register(16'h0330, mon_count);
        pass = pass && mon_count === 8'd0;
        reset_and_halt;
        uart_image(1);
        pass = pass && ready;
        for (sample_index = 0; sample_index < 2000; sample_index = sample_index + 1) begin
            edge_sample; pass = pass && trace_off[sample_index] === trace_signals;
        end
        read_register(16'h0330, mon_count);
        read_register(16'h0f01, status);
        check("NON_INTRUSION", pass && mon_count === 8'd1 && status[2:0] === 3'd4);
`else
        reset_and_halt;
        uart_image(1);
        // Wait for the program's initial SET before looking for its start bit.
        wait_pin(0, 1'b1, 120, reached);
        pass = ready && reached;
        wait_pin(0, 1'b0, 500, reached);
        pass = pass && reached;
`ifdef PVM_NO_FABRIC
        pass = pass && uo[3] === 1'b0;
`else
        pass = pass && uo[3] === 1'b1;
`endif
        for (sample_index = 0; sample_index < 1280; sample_index = sample_index + 1) begin
            if (sample_index != 0) edge_sample;
            if (sample_index < 128)
                expected_line = 1'b0;
            else if (sample_index < 1152)
                expected_line = UART_DATA[(sample_index/128)-1];
            else
                expected_line = 1'b1;
            pass = pass && uo[0] === expected_line;
        end
        read_register(16'h0f01, status);
        read_register(16'h0f80, log_entry);
        read_register(16'h0fa0, log_status);
        read_register(16'h0330, mon_count);
        pass = pass && status[2:0] === 3'd4;
`ifdef PVM_NO_MON
        pass = pass && {log_entry, log_status, mon_count} === 24'h000000;
`else
        pass = pass && {log_entry, log_status, mon_count} === 24'h080501;
`endif
        new_image;
        spi_image;
        pass = pass && ready && uo[1] === 1'b0;
        for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
            wait_pin(1, 1'b1, 180, reached);
            pass = pass && reached && uo[2] === SPI_DATA[bit_index];
            wait_cycles = 0;
            while (uo[1] === 1'b1 && wait_cycles < 80) begin
                edge_sample;
                wait_cycles = wait_cycles + 1;
                if (uo[1]) pass = pass && uo[2] === SPI_DATA[bit_index];
            end
            pass = pass && wait_cycles == 32 && uo[1] === 1'b0;
        end
        read_register(16'h0f01, status);
        check("IMAGE_SWAP_UART_TO_SPI", pass && status[2:0] === 3'd4);

        reset_and_halt;
        write_word(0, 16'h2080); // WAIT 1 PIN P0
        write_config(16'h0110, 8'd8);
        validate_image(ready);
        write_register(CTRL, 8'h03);
        read_register(16'h0f01, status);
        read_register(16'h0f02, code);
        read_register(16'h0f03, value);
        pass = ready && status[2:0] === 3'd5 && code === 8'd2 && value === 8'd0;
        write_register(CTRL, 8'h05);
        read_register(16'h0f01, status);
        pass = pass && status[2:0] === 3'd0;
        new_image;
        complete_image;
        check("FAULT_THEN_RECOVER", pass && ready && status[2:0] === 3'd4 && code === 8'd1);

        reset_and_halt;
        write_word(0, 16'he001);
        write_config(16'h0104, 8'd5);
        write_config(16'h0105, 8'd1);
        write_config(16'h010b, 8'd0);
        write_config(16'h0405, 8'h09);
        validate_image(ready);
        write_register(CTRL, 8'h03);
        wait_pin(0, 1'b1, 100, reached);
        pass = ready && reached;
        set_select(1'b1);
        spi_byte(8'h02, serial_rx);
        spi_byte(8'h04, serial_rx);
        @(negedge clk); rst_n = 1'b0;
        repeat (2) edge_sample;
        pass = pass && {uo[6:0], uio_out, uio_oe} === 23'd0;
        @(negedge clk); rst_n = 1'b1;
        repeat (8) edge_sample;
        set_select(1'b0);
        read_register(16'h0f01, status);
        read_register(16'h0f06, value);
        pass = pass && status === 8'h00 && value === 8'hff;
        new_image;
        complete_image;
        check("DESELECT_RESET_RELOAD", pass && ready && status[2:0] === 3'd4 && code === 8'd1);
`endif
        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", errors == 0 && checks == N_CHECKS ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #20000000;
        $display("TB_TIMEOUT\nRESULT : FAIL");
        $finish;
    end
endmodule
`default_nettype wire
