`timescale 1ns/1ps
`default_nettype none

// S11: two frozen end-to-end SPI-to-pin checks. The bench accesses pads only.
module tb_top_s11;
    localparam [15:0] CTRL = 16'h0f00;
    reg clk = 1'b0, rst_n = 1'b0;
    reg [7:0] ui = 8'h02;
    wire [7:0] uo, uio_out, uio_oe;
    reg [15:0] crc;
    reg [7:0] serial_rx, status, fault_code, fault_pc;
    reg visible_drive, pass, expected_line;
    integer checks = 0, errors = 0, cycle_index;
    localparam [7:0] PAYLOAD = 8'h35;

    always #10 clk = ~clk;
    pvm_top dut (
        .ui_in(ui), .uo_out(uo), .uio_in(8'h00), .uio_out(uio_out), .uio_oe(uio_oe),
        .clk(clk), .rst_n(rst_n)
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

    task check(input [8*40:1] name, input ok);
        begin
            checks = checks + 1;
            if (ok === 1'b1)
                $display("[PASS] %0s", name);
            else begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_top_s11 CHECKS=2");

        reset_and_halt;
        write_word(5'd0, 16'he001); // Idle high
        write_word(5'd1, 16'h80a0); // Wait for the host's TX byte
        write_word(5'd2, 16'he027);
        write_word(5'd3, 16'he100); // Start low for two ticks
        write_word(5'd4, 16'h6001);
        write_word(5'd5, 16'h0044);
        write_word(5'd6, 16'he101); // Stop high for two ticks
        write_word(5'd7, 16'hc0c0);
        write_config(16'h0100, 8'd64);
        write_config(16'h0102, 8'd5);
        write_config(16'h0103, 8'd1);
        write_config(16'h0104, 8'd5);
        write_config(16'h0105, 8'd1);
        write_config(16'h010b, 8'd7);
        write_config(16'h010c, 8'd1);
        write_config(16'h0405, 8'h29);
        validate_image(pass);
        write_register(CTRL, 8'h03);
        write_register(16'h0f10, PAYLOAD);
        pass = pass && (uo[0] === 1'b1);
        cycle_index = 0;
        while (uo[0] === 1'b1 && cycle_index < 300) begin
            edge_sample;
            cycle_index = cycle_index + 1;
        end
        pass = pass && (uo[0] === 1'b0) && (cycle_index < 300);
        // The first low sample is bit cell zero. Each cell is 128 core clocks.
        for (cycle_index=0;cycle_index<1280;cycle_index=cycle_index+1) begin
            if (cycle_index != 0) edge_sample;
            if (cycle_index < 128)
                expected_line = 1'b0;
            else if (cycle_index < 1152)
                expected_line = PAYLOAD[(cycle_index/128)-1];
            else
                expected_line = 1'b1;
            pass = pass && (uo[0] === expected_line);
        end
        read_register(16'h0f01, status);
        check("SPI_UART_TX_SMOKE", pass && (status[2:0] === 3'd4));

        reset_and_halt;
        write_word(5'd0, 16'he081); // Drive P12
        write_word(5'd1, 16'he001); // Drive it high while RUN
        write_word(5'd2, 16'h2080); // WAIT 1 PIN 0; stays low
        write_config(16'h0100, 8'd32);
        write_config(16'h0104, 8'd12);
        write_config(16'h0105, 8'd1);
        write_config(16'h010b, 8'd2);
        write_config(16'h0111, 8'd2); // 512 timeout enables
        write_config(16'h040c, 8'h09);
        validate_image(pass);
        write_register(CTRL, 8'h03);
        visible_drive = 1'b0;
        repeat (700) begin
            edge_sample;
            if (uio_oe[0] && uio_out[0]) visible_drive = 1'b1;
        end
        read_register(16'h0f01, status);
        read_register(16'h0f02, fault_code);
        read_register(16'h0f03, fault_pc);
        check("FAULT_OUTPUTS_SAFE", pass && visible_drive && (uio_oe === 8'h00) &&
              (status[2:0] === 3'd5) && (fault_code === 8'd2) && (fault_pc === 8'd2));

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == 2) ? "PASS" : "FAIL");
        $finish;
    end
    initial begin #3000000; $display("TB_TIMEOUT top_s11"); $finish; end
endmodule
`default_nettype wire
