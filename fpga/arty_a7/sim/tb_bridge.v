`timescale 1ns/1ps
`default_nettype none

module tb_bridge;
    localparam integer UART_BIT = 434;
    reg clk = 0;
    always #10 clk = !clk;
    reg rst_n = 0;
    reg uart_rx = 1;
    wire uart_tx, spi_sck, spi_cs_n, spi_mosi, host_reset_n;
    reg spi_miso = 0;

    uart_spi_bridge #(.RX_TIMEOUT_CLKS(12000)) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .spi_sck(spi_sck), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .spi_miso(spi_miso), .host_reset_n(host_reset_n)
    );

    integer cases, frames, bit_count, wanted_length;
    integer spi_last_edge, starts, total_edges;
    reg [7:0] wanted_byte, wanted_reply;
    reg first_exchange;

    function [7:0] outgoing;
        input integer index;
        begin
            outgoing = first_exchange ? (index == 0 ? 8'h9f : 8'd0) : index ^ 8'h5a;
        end
    endfunction

    function [7:0] response_byte;
        input integer index;
        begin
            response_byte = 8'h96 ^ index;
        end
    endfunction

    task fail;
        input [8*48-1:0] explanation;
        begin
            $display("FAIL %0s at %0t", explanation, $time);
            $finish_and_return(1);
        end
    endtask

    always @(negedge spi_cs_n) if (rst_n) begin
        if (spi_sck !== 1'b0 || wanted_length == 0)
            fail("BRIDGE_CS_UNEXPECTED");
        starts = starts + 1;
        bit_count = 0;
        spi_last_edge = $time;
        wanted_reply = response_byte(0);
        spi_miso = wanted_reply[7];
    end

    always @(posedge spi_sck) if (rst_n) begin
        if (spi_cs_n !== 1'b0 || bit_count >= wanted_length * 8)
            fail("BRIDGE_SPI_UNEXPECTED");
        if ($time - spi_last_edge != 2000)
            fail("BRIDGE_SPI_HALF_PERIOD");
        wanted_byte = outgoing(bit_count / 8);
        if (spi_mosi !== wanted_byte[7 - (bit_count % 8)])
            fail("BRIDGE_SPI_MOSI_ORDER");
        bit_count = bit_count + 1;
        total_edges = total_edges + 1;
        spi_last_edge = $time;
    end

    always @(negedge spi_sck) if (rst_n) begin
        if (spi_cs_n !== 1'b0 || $time - spi_last_edge != 2000)
            fail("BRIDGE_SPI_FALLING_EDGE");
        wanted_reply = response_byte(bit_count / 8);
        spi_miso = wanted_reply[7 - (bit_count % 8)];
        spi_last_edge = $time;
    end

    always @(posedge spi_cs_n) if (rst_n) begin
        if (spi_sck !== 1'b0 || bit_count != wanted_length * 8 ||
            $time - spi_last_edge != 2000)
            fail("BRIDGE_CS_FRAME_LENGTH");
        frames = frames + 1;
    end

    task send;
        input [7:0] value;
        input good_stop;
        integer i;
        begin
            uart_rx = 0;
            repeat (UART_BIT) @(negedge clk);
            for (i=0; i<8; i=i+1) begin
                uart_rx = value[i];
                repeat (UART_BIT) @(negedge clk);
            end
            uart_rx = good_stop;
            repeat (UART_BIT) @(negedge clk);
            uart_rx = 1;
        end
    endtask

    task expect_uart;
        input [7:0] expected;
        input verify_spi_data;
        reg [7:0] actual;
        integer i;
        begin
            @(negedge uart_tx);
            repeat (UART_BIT / 2) @(negedge clk);
            if (uart_tx !== 1'b0)
                fail("BRIDGE_UART_START");
            for (i=0; i<8; i=i+1) begin
                repeat (UART_BIT) @(negedge clk);
                actual[i] = uart_tx;
            end
            repeat (UART_BIT) @(negedge clk);
            if (uart_tx !== 1'b1)
                fail("BRIDGE_UART_STOP");
            if (actual !== expected) begin
                $display("UART received %02x expected %02x",actual,expected);
                if (verify_spi_data)
                    fail("BRIDGE_MISO");
                else
                    fail("BRIDGE_STATUS");
            end
        end
    endtask

    task check;
        input [8*48-1:0] name;
        begin
            $display("PASS %0s", name);
            cases = cases + 1;
            repeat (UART_BIT) @(negedge clk);
        end
    endtask

    task exchange;
        input integer count;
        integer ti, ri, old_frames, old_starts, old_edges;
        begin
            wanted_length = count;
            old_frames = frames;
            old_starts = starts;
            old_edges = total_edges;
            fork
                begin
                    send(8'h01, 1);
                    send(count[15:8], 1);
                    send(count[7:0], 1);
                    for (ti=0; ti<count; ti=ti+1) begin
                        if (starts != old_starts)
                            fail("BRIDGE_SPI_BEFORE_COMPLETE_FRAME");
                        send(outgoing(ti),1);
                    end
                end
                begin
                    expect_uart(8'h00,0);
                    for (ri=0; ri<count; ri=ri+1)
                        expect_uart(response_byte(ri),1);
                end
            join
            if (frames != old_frames+1 || starts != old_starts+1 ||
                total_edges != old_edges+count*8)
                fail("BRIDGE_SPI_FRAME_COUNT");
            wanted_length = 0;
        end
    endtask

    integer start_time;
    initial begin
        cases=0; frames=0; starts=0; total_edges=0;
        wanted_length=0; first_exchange=1;
        repeat (4) @(negedge clk);
        rst_n=1;
        repeat (4) @(negedge clk);
        if ({spi_cs_n,spi_sck,spi_mosi,uart_tx,host_reset_n} !== 5'b10011)
            fail("BRIDGE_RESET_IDLE");
        check("BRIDGE_RESET_IDLE");
        exchange(5);
        check("BRIDGE_FIVE_BYTE_EXCHANGE");
        first_exchange=0;
        exchange(260);
        check("BRIDGE_MAXIMUM_LENGTH");

        fork
            send(8'h02,1);
            expect_uart(8'h00,0);
            begin
                @(negedge host_reset_n);
                start_time=$time;
                @(posedge host_reset_n);
                if ($time-start_time != 640)
                    fail("BRIDGE_HOST_RESET_WIDTH");
            end
        join
        check("BRIDGE_HOST_RESET");

        fork send(8'h13,1); expect_uart(8'hff,0); join
        check("BRIDGE_UNKNOWN_OPCODE");

        fork
            begin send(8'h01,1); send(8'h00,1); send(8'h00,1); end
            expect_uart(8'hff,0);
        join
        repeat (UART_BIT) @(negedge clk);
        fork
            begin send(8'h01,1); send(8'h01,1); send(8'h05,1); end
            expect_uart(8'hff,0);
        join
        check("BRIDGE_INVALID_LENGTHS");

        fork
            begin send(8'h01,1); send(8'h00,1); send(8'h02,1); send(8'h9f,1); end
            expect_uart(8'hff,0);
        join
        check("BRIDGE_TRUNCATED_FRAME");

        fork send(8'h01,0); expect_uart(8'hff,0); join
        check("BRIDGE_BAD_STOP");
        if (starts != 2 || frames != 2)
            fail("BRIDGE_BAD_REQUEST_SPI");

        exchange(1);
        check("BRIDGE_RECOVERY");
        if (cases != 9)
            fail("BRIDGE_FROZEN_COUNT");
        $display("RESULT PASS CHECKS %0d",cases);
        $finish;
    end

    initial begin
        #80000000;
        fail("BRIDGE_TIMEOUT");
    end
endmodule

`default_nettype wire
