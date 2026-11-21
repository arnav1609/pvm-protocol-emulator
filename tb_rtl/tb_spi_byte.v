`timescale 1ns/1ps
`default_nettype none

// 8 frozen mode-0 SPI byte checks, frozen 2026-11-20 before registration. Stage S04.
// SEED 0x9D67
module tb_spi_byte;
    localparam integer N_CHECKS = 8;
    reg clk = 1'b0, rst_n = 1'b0;
    reg sck_pad = 1'b0, cs_n_pad = 1'b1, mosi_pad = 1'b0;
    wire sck, cs_n, mosi, miso, rx_valid, frame_start, frame_end;
    wire [7:0] rx_byte;
    reg tx_load = 1'b0;
    reg [7:0] tx_byte = 8'h00;
    reg respond = 1'b0;
    reg [7:0] received [0:31];
    reg [7:0] host_in;
    reg [15:0] rng = 16'h9d67;
    reg burst_ok;
    integer rx_count = 0, starts = 0, ends = 0;
    integer checks = 0, errors = 0, i, bit_index, half_period = 8;

    always #10 clk = ~clk;

    pvm_sync2 sync_sck (.clk(clk), .rst_n(rst_n), .d(sck_pad), .q(sck));
    pvm_sync2 #(.RST_VAL(1'b1)) sync_cs (.clk(clk), .rst_n(rst_n), .d(cs_n_pad), .q(cs_n));
    pvm_sync2 sync_mosi (.clk(clk), .rst_n(rst_n), .d(mosi_pad), .q(mosi));
    pvm_spi_byte dut (
        .clk(clk), .rst_n(rst_n), .sck(sck), .cs_n(cs_n), .mosi(mosi),
        .tx_byte(tx_byte), .tx_load(tx_load), .rx_byte(rx_byte), .rx_valid(rx_valid),
        .frame_start(frame_start), .frame_end(frame_end), .miso(miso)
    );

    always @(posedge clk) begin
        #1;
        if (rx_valid) begin
            if (rx_count < 32)
                received[rx_count] = rx_byte;
            rx_count = rx_count + 1;
        end
        if (frame_start)
            starts = starts + 1;
        if (frame_end)
            ends = ends + 1;
    end

    always @(negedge clk) begin
        tx_load <= respond && rx_valid && (rx_byte == 8'ha5);
        tx_byte <= 8'h96;
    end

    task select_chip(input selected);
        begin
            @(negedge clk);
            cs_n_pad = !selected;
            repeat (half_period) @(negedge clk);
        end
    endtask

    task spi_bit(input bit_out, output reg bit_in);
        begin
            mosi_pad = bit_out;
            repeat (half_period) @(negedge clk);
            sck_pad = 1'b1;
            #1;
            bit_in = miso;
            repeat (half_period) @(negedge clk);
            sck_pad = 1'b0;
        end
    endtask

    task spi_xfer(input [7:0] byte_out, output reg [7:0] byte_in);
        integer bit_index;
        reg bit_in;
        begin
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                spi_bit(byte_out[bit_index], bit_in);
                byte_in[bit_index] = bit_in;
            end
            repeat (half_period) @(negedge clk);
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

    reg unused_miso;
    initial begin
        $display("CONFIG: TOP=tb_spi_byte CHECKS=%0d", N_CHECKS);
        $display("SEED %04h", rng);
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_spi_byte.vcd");
            $dumpvars(0, tb_spi_byte);
        end
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        respond = 1'b1;

        select_chip(1'b1);
        spi_xfer(8'ha5, host_in);
        check("RX_A5", (rx_count == 1) && (received[0] === 8'ha5));
        burst_ok = (host_in === 8'h00);
        spi_xfer(8'h3c, host_in);
        check("TX_LOAD_96", host_in === 8'h96);
        spi_xfer(8'h00, host_in);
        check("TX_DEFAULT_ZERO", burst_ok && (host_in === 8'h00));
        select_chip(1'b0);
        check("FRAME_START_END", (starts == 1) && (ends == 1) && (miso === 1'b0));
        respond = 1'b0;

        select_chip(1'b1);
        // Keep SCK at clk/16 throughout the receive burst, including byte boundaries.
        burst_ok = 1'b1;
        for (i = 0; i < 16; i = i + 1) begin
            rng = {rng[14:0], rng[15] ^ rng[13] ^ rng[12] ^ rng[10]};
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1)
                spi_bit(rng[bit_index], unused_miso);
            // The core has processed the final rising edge by this falling edge.
            burst_ok = burst_ok && (received[3+i] === rng[7:0]);
        end
        select_chip(1'b0);
        check("RX_BACK_TO_BACK_16BYTES", burst_ok && (rx_count == 19));

        select_chip(1'b1);
        spi_bit(1'b1, unused_miso);
        spi_bit(1'b0, unused_miso);
        spi_bit(1'b1, unused_miso);
        select_chip(1'b0);
        burst_ok = (rx_count == 19);
        select_chip(1'b1);
        spi_xfer(8'h4e, host_in);
        select_chip(1'b0);
        check("CS_ABORT_MIDBYTE", burst_ok && (rx_count == 20) && (received[19] === 8'h4e));
        spi_xfer(8'hff, host_in);
        check("SCK_GLITCH_WHEN_CS_HIGH", (rx_count == 20) && (host_in === 8'h00));

        half_period = 32;
        select_chip(1'b1);
        spi_xfer(8'h63, host_in);
        select_chip(1'b0);
        check("SLOWEST_SCK", (rx_count == 21) && (received[20] === 8'h63));

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == N_CHECKS) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #200000;
        $display("TB_TIMEOUT spi_byte");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
