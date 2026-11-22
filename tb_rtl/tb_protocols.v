`timescale 1ns/1ps
`default_nettype none

// S14b protocol tests only drive the wrapper's host SPI and external pads.
module tb_protocols;
    localparam [15:0] CTRL = 16'h0f00;
    localparam [7:0] UART_DATA = 8'h35;
    localparam integer UART_DIV = 217, UART_BIT_CLOCKS = 2 * UART_DIV;
    localparam integer SPI_DIV = 32, I2C_DIV = 80;
    reg clk = 1'b0, rst_n = 1'b0;
    reg [7:0] ui = 8'h02;
    wire [7:0] uo, uio_out, uio_oe;
    tri1 sda, scl;
    reg target_sda_low = 0, target_scl_low = 0;
    assign sda = uio_oe[0] ? uio_out[0] : 1'bz;
    assign scl = uio_oe[1] ? uio_out[1] : 1'bz;
    assign sda = target_sda_low ? 1'b0 : 1'bz;
    assign scl = target_scl_low ? 1'b0 : 1'bz;
    reg driven_high = 0;
    reg [15:0] crc;
    reg [7:0] serial_rx, status;
    reg ready, passed, reached, expected_line, bus_ok;
    integer cycle_index, bit_index, high_clocks, low_clocks;

    always #10 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n)
            driven_high <= 1'b0;
        else if (|((uio_out & uio_oe) & 8'h03))
            driven_high <= 1'b1;
    end

    tt_um_arnav1609_pvm dut (
        .clk(clk), .rst_n(rst_n), .ena(1'b1), .ui_in(ui), .uio_in({6'b0, scl, sda}),
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

    task enable_image(input [7:0] first, second, input two_bytes);
        begin
            validate_image(ready);
            write_register(16'h0f10, first);
            if (two_bytes) write_register(16'h0f10, second);
            write_register(CTRL, 8'h03);
        end
    endtask

    task wait_uo(input integer pin, input level, input integer limit, output reg ok);
        integer elapsed;
        begin
            for (elapsed = 0; elapsed < limit && uo[pin] !== level; elapsed = elapsed + 1)
                edge_sample;
            ok = uo[pin] === level;
        end
    endtask

    task wait_bus(input clock_line, level, output reg ok);
        integer elapsed;
        begin
            for (elapsed = 0; elapsed < 1000 && (clock_line ? scl : sda) !== level;
                 elapsed = elapsed + 1)
                edge_sample;
            ok = (clock_line ? scl : sda) === level;
        end
    endtask

    task sample_i2c_byte(input [7:0] expected, input stretch_ack, output reg ok);
        integer bit_number, elapsed;
        reg saw_edge;
        begin
            wait_bus(1, 0, saw_edge);
            ok = saw_edge;
            for (bit_number = 7; bit_number >= 0; bit_number = bit_number - 1) begin
                wait_bus(1, 1, saw_edge);
                ok = ok && saw_edge && sda === expected[bit_number] &&
                     uio_oe[0] === !expected[bit_number] && uio_oe[1] === 1'b0;
                for (elapsed = 0; elapsed < 400 && scl === 1'b1; elapsed = elapsed + 1) begin
                    edge_sample;
                    if (scl === 1'b1)
                        ok = ok && sda === expected[bit_number];
                end
                ok = ok && scl === 1'b0;
            end

            // The target drives ACK during the low phase and may hold SCL low.
            @(negedge clk);
            target_sda_low = 1'b1;
            target_scl_low = stretch_ack;
            if (stretch_ack) begin
                for (elapsed = 0; elapsed < 400 && uio_oe[1] !== 1'b0; elapsed = elapsed + 1)
                    edge_sample;
                ok = ok && uio_oe[1] === 1'b0 && uio_oe[0] === 1'b0 &&
                     scl === 1'b0 && sda === 1'b0;
                repeat (4*I2C_DIV+11) begin
                    edge_sample;
                    ok = ok && uio_oe[1] === 1'b0 && uio_oe[0] === 1'b0 && scl === 1'b0;
                end
                @(negedge clk); target_scl_low = 1'b0;
            end
            wait_bus(1, 1, saw_edge);
            ok = ok && saw_edge && sda === 1'b0 && uio_oe[0] === 1'b0;
            wait_bus(1, 0, saw_edge);
            ok = ok && saw_edge;
            @(negedge clk); target_sda_low = 1'b0;
        end
    endtask

    task finish(input [8*48:1] name, input ok);
        begin
            if (ok === 1'b1)
                $display("[PASS] %0s\nCHECKS : 1\nERRORS : 0\nRESULT : PASS", name);
            else
                $display("[FAIL] %0s\nCHECKS : 1\nERRORS : 1\nRESULT : FAIL", name);
            $finish;
        end
    endtask

    initial begin
        $display("CONFIG: TOP=tb_protocols CHECKS=1");
        reset_and_halt;
`ifdef PVM_PROTOCOL_UART
        write_word(0, 16'he001); // Drive idle high
        write_word(1, 16'h80a0); // PULL BLOCK
        write_word(2, 16'he027); // SET X, 7
        write_word(3, 16'he100); // Start bit for two engine ticks
        write_word(4, 16'h6001); // OUT PINS, 1
        write_word(5, 16'h0044); // JMP X--, 4
        write_word(6, 16'he101); // Stop bit for two engine ticks
        write_word(7, 16'hc0c0); // EVT DONE
        write_config(16'h0100, UART_DIV[7:0]);
        write_config(16'h0102, 8'd5);
        write_config(16'h0103, 8'd1);
        write_config(16'h0104, 8'd5);
        write_config(16'h0105, 8'd1);
        write_config(16'h010b, 8'd7);
        write_config(16'h010c, 8'd1);
        write_config(16'h0405, 8'h29);
        enable_image(UART_DATA, 0, 0);
        wait_uo(0, 1, UART_DIV+8, reached);
        passed = ready && reached;
        wait_uo(0, 0, 4*UART_DIV, reached);
        passed = passed && reached;
        for (cycle_index = 0; cycle_index < 10*UART_BIT_CLOCKS; cycle_index = cycle_index + 1) begin
            if (cycle_index != 0) edge_sample;
            if (cycle_index < UART_BIT_CLOCKS)
                expected_line = 1'b0;
            else if (cycle_index < 9*UART_BIT_CLOCKS)
                expected_line = UART_DATA[cycle_index/UART_BIT_CLOCKS-1];
            else
                expected_line = 1'b1;
            passed = passed && uo[0] === expected_line;
        end
        read_register(16'h0f01, status);
        finish("UART_TX_0X35_115200", passed && status[2:0] === 3'd4);
`elsif PVM_PROTOCOL_SPI
        write_word(0, 16'he041); // SET Y, 1
        write_word(1, 16'h80a0); // PULL BLOCK
        write_word(2, 16'he027); // SET X, 7
        write_word(3, 16'h6001); // Update MOSI with SCK low
        write_word(4, 16'h1043); // SCK high, JMP X--, 3
        write_word(5, 16'h0081); // SCK low, JMP Y--, 1
        write_word(6, 16'hc0c0);
        write_config(16'h0100, SPI_DIV[7:0]);
        write_config(16'h0102, 8'd7);
        write_config(16'h0103, 8'd1);
        write_config(16'h0107, 8'd6);
        write_config(16'h0108, 8'd1);
        write_config(16'h010b, 8'd6);
        write_config(16'h010c, 8'd0); // MSB first
        write_config(16'h0406, 8'h0a);
        write_config(16'h0407, 8'h09);
        enable_image(8'ha6, 8'hc9, 1);
        passed = ready && uo[1] === 1'b0;
        wait_uo(1, 1, 6*SPI_DIV, reached);
        passed = passed && reached;
        for (bit_index = 15; bit_index >= 0; bit_index = bit_index - 1) begin : spi_bits
            reg [15:0] payload;
            payload = 16'ha6c9;
            expected_line = payload[bit_index];
            high_clocks = 0;
            while (uo[1] === 1'b1 && high_clocks < 2*SPI_DIV) begin
                passed = passed && uo[2] === expected_line;
                edge_sample;
                high_clocks = high_clocks + 1;
            end
            passed = passed && high_clocks == SPI_DIV && uo[1] === 1'b0;
            if (bit_index != 0) begin
                low_clocks = 0;
                while (uo[1] === 1'b0 && low_clocks < 6*SPI_DIV) begin
                    if (low_clocks >= (bit_index == 8 ? 3*SPI_DIV : 0))
                        passed = passed && uo[2] === payload[bit_index-1];
                    edge_sample;
                    low_clocks = low_clocks + 1;
                end
                passed = passed && uo[1] === 1'b1 &&
                         low_clocks == (bit_index == 8 ? 4*SPI_DIV : SPI_DIV);
            end
        end
        repeat (3*SPI_DIV) begin
            edge_sample; passed = passed && uo[1] === 1'b0;
        end
        read_register(16'h0f01, status);
        finish("SPI_MODE0_TWO_BYTES", passed && status[2:0] === 3'd4);
`elsif PVM_PROTOCOL_I2C
        write_word(0, 16'hf003); // Release both lines
        write_word(1, 16'hf083); // Enable open-drain owners
        write_word(2, 16'h308d); // WAIT SCL high
        write_word(3, 16'hf002); // START
        write_word(4, 16'he041); // SCL low; SET Y, 1
        write_word(5, 16'h80a0); // PULL BLOCK
        write_word(6, 16'he027); // SET X, 7
        write_word(7, 16'h6001); // SDA bit, SCL low
        write_word(8, 16'h308d); // Release SCL and wait for pad high
        write_word(9, 16'h1047); // Hold SCL high, JMP X--, 7
        write_word(10, 16'he001); // Release SDA for target ACK, SCL low
        write_word(11, 16'h308d); // Release SCL and wait for pad high
        write_word(12, 16'h300c); // WAIT SDA low for ACK
        write_word(13, 16'h0085); // SCL low, JMP Y--, 5
        write_word(14, 16'he000); // Pull SDA low before STOP
        write_word(15, 16'h308d); // Release SCL, await high
        write_word(16, 16'hf003); // STOP, release SDA
        write_word(17, 16'hd0c0);
        write_config(16'h0100, I2C_DIV[7:0]);
        write_config(16'h0102, 8'd12);
        write_config(16'h0103, 8'd1);
        write_config(16'h0104, 8'd12);
        write_config(16'h0105, 8'd2);
        write_config(16'h0107, 8'd13);
        write_config(16'h0108, 8'd1);
        write_config(16'h010b, 8'd17);
        write_config(16'h010c, 8'd0); // MSB first
        write_config(16'h040c, 8'h11);
        write_config(16'h040d, 8'h12);
        enable_image(8'ha0, 8'h3c, 1); // Address 0x50 plus write, then data
        passed = ready && sda === 1'b1 && scl === 1'b1;
        wait_bus(0, 0, reached);
        passed = passed && reached && scl === 1'b1 && uio_oe[0] === 1'b1;
        sample_i2c_byte(8'ha0, 1, bus_ok);
        passed = passed && bus_ok;
        sample_i2c_byte(8'h3c, 0, bus_ok);
        passed = passed && bus_ok;
        wait_bus(1, 1, reached);
        passed = passed && reached && sda === 1'b0;
        wait_bus(0, 1, reached);
        passed = passed && reached && scl === 1'b1;
        read_register(16'h0f01, status);
        finish("I2C_WRITE_OPEN_DRAIN_ACK_STRETCH",
               passed && !driven_high && uio_oe[1:0] === 2'b00 && status[2:0] === 3'd4);
`else
        $display("Select exactly one protocol build");
        $finish;
`endif
    end

    initial begin
        #20000000;
        $display("TB_TIMEOUT\nRESULT : FAIL");
        $finish;
    end
endmodule
`default_nettype wire
