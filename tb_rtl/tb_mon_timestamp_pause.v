`timescale 1ns/1ps
`default_nettype none

// Exercise monitor timestamp lifetime across real SPI image loads.
module tb_mon_timestamp_pause;
    localparam [15:0] CTRL = 16'h0f00, STATUS = 16'h0f01;
    reg clk = 1'b0, rst_n = 1'b0;
    reg [7:0] ui = 8'h02;
    wire [7:0] uo, uio_out, uio_oe;
    reg [15:0] crc;
    reg [7:0] serial_rx, status, log_status;
    reg [15:0] held, restart_timestamp, first_stamp, second_stamp;
    reg ready, halt_holds;
    integer checks = 0, errors = 0;

    wire [15:0] timestamp = dut.pvm.monitor.tstamp;
    always #10 clk = ~clk;
    tt_um_arnav1609_pvm dut (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(ui), .uio_in(8'h00),
        .uo_out(uo), .uio_out(uio_out), .uio_oe(uio_oe)
    );

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

    task load_image(input [7:0] monitor_control);
        begin
            write_register(CTRL, 8'h04);
            crc = 16'hffff;
            write_word(0, 16'h2081); // WAIT 1 PIN 1. P1 controls exit from RUN.
            write_word(1, 16'hc0c0); // EVT DONE.
            write_config(16'h010b, 8'h01); // WRAP_TOP includes EVT DONE.
            write_config(16'h0300, 8'h00); // Rule 0, rise, state 0 to 0.
            write_config(16'h0301, 8'h80); // Valid, source P0, no guard.
            write_config(16'h0302, 8'h10); // MEASURE.
            write_config(16'h032a, monitor_control);
            validate_image(ready);
        end
    endtask

    task rise_pair;
        begin
            // Let the monitor advance before capturing the first timestamp.
            repeat (32) @(negedge clk);
            ui[3] = 1;
            repeat (4) @(negedge clk);
            ui[3] = 0;
            repeat (60) @(negedge clk);
            ui[3] = 1; // Exactly 64 core clocks between rising events.
            repeat (4) @(negedge clk);
            ui[3] = 0;
        end
    endtask

    task read_timestamp(input [15:0] addr, output [15:0] value);
        begin
            read_register(addr, value[7:0]);
            read_register(addr + 16'd1, value[15:8]);
        end
    endtask

    task read_pair;
        begin
            read_timestamp(16'h0f83, first_stamp);
            read_timestamp(16'h0f8b, second_stamp);
            read_register(16'h0fa0, log_status);
        end
    endtask

    task finish_image;
        begin
            @(negedge clk);
            ui[4] = 1;
            wait (dut.pvm.state == 3'd4);
            @(negedge clk);
            ui[4] = 0;
        end
    endtask

    task check(input [8*40:1] name, input ok);
        begin
            checks = checks + 1;
            if (ok === 1'b1) $display("[PASS] %0s", name);
            else begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_mon_timestamp_pause CHECKS=6");
        reset_and_halt;

        // MON_EN stays clear even though the engine enters RUN.
        load_image(8'h02);
        restart_timestamp = timestamp;
        write_register(CTRL, 8'h03);
        rise_pair;
        read_register(STATUS, status);
        read_register(16'h0fa0, log_status);
        check("TIMESTAMP_MON_DISABLED", ready && status[2:0] === 3'd3 &&
              timestamp === restart_timestamp && log_status === 8'd0);
        finish_image;
        write_register(CTRL, 8'h01);

        // Prescaler selector 1 gives one timestamp tick per 16 core clocks.
        load_image(8'h03);
        write_register(CTRL, 8'h03);
        rise_pair;
        read_pair;
        check("TIMESTAMP_RUN_PRESCALE", ready && log_status[7:2] === 6'd2 &&
              first_stamp > 16'd0 && second_stamp === first_stamp + 16'd4);
        finish_image;
        held = timestamp;
        read_register(STATUS, status);
        check("TIMESTAMP_HOLDS_DONE", status[2:0] === 3'd4 && timestamp === held);

        write_register(CTRL, 8'h01);
        read_register(STATUS, status);
        halt_holds = status[2:0] === 3'd0 && timestamp === held;
        load_image(8'h03);
        halt_holds = halt_holds && ready && timestamp === held;
        restart_timestamp = timestamp;
        write_register(CTRL, 8'h03);
        rise_pair;
        read_pair;
        $display("TIMESTAMP: held=%0d restart=%0d first=%0d second=%0d",
                 held, restart_timestamp, first_stamp, second_stamp);
        check("TIMESTAMP_SURVIVES_HALT_RELOAD", halt_holds && first_stamp > held);
        check("TIMESTAMP_RESUMES", log_status[7:2] === 6'd2 &&
              first_stamp > restart_timestamp && second_stamp === first_stamp + 16'd4);
        finish_image;

        held = timestamp;
        @(negedge clk);
        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        check("TIMESTAMP_CHIP_RESET", held > 16'd0 && timestamp === 16'd0);

        $display("CHECKS : %0d\nERRORS : %0d\nRESULT : %0s",
                 checks, errors, errors == 0 ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #4000000;
        $display("TB_TIMEOUT");
        $finish;
    end
endmodule

`default_nettype wire
