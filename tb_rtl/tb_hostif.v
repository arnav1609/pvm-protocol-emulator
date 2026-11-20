`timescale 1ns/1ps
`default_nettype none

// 11 frozen SPI frame and byte bus checks, frozen 2026-11-20 before registration.
// SEED 0x679D
module tb_hostif;
    localparam integer N_CHECKS = 11;
    localparam [2:0] WRITE_EVENT = 3'b100, READ_EVENT = 3'b010, ACK_EVENT = 3'b001;

    reg clk = 1'b0, rst_n = 1'b0;
    reg sck_pad = 1'b0, cs_n_pad = 1'b1, mosi_pad = 1'b0;
    wire sck, cs_n, mosi, miso, bus_we, bus_re, bus_rack;
    wire [15:0] bus_addr;
    wire [7:0] bus_wdata;
    reg [7:0] bus_rdata = 8'h00;
    reg [7:0] mem [0:65535];

    reg [2:0] event_kind [0:127];
    reg [15:0] event_addr [0:127];
    reg [7:0] event_data [0:127];
    integer event_cycle [0:127];
    integer cycles = 0, events = 0, origin, i;
    reg strobe_ok = 1'b1;
    reg [7:0] host_in;
    reg [15:0] rng = 16'h679d;
    reg [15:0] test_addr;
    reg [7:0] generated_byte;
    reg ok, seq_ok, unused_miso;
    integer read_start, checks = 0, errors = 0;

    always #10 clk = ~clk;

    pvm_sync2 sync_sck (.clk(clk), .rst_n(rst_n), .d(sck_pad), .q(sck));
    pvm_sync2 #(.RST_VAL(1'b1)) sync_cs (.clk(clk), .rst_n(rst_n), .d(cs_n_pad), .q(cs_n));
    pvm_sync2 sync_mosi (.clk(clk), .rst_n(rst_n), .d(mosi_pad), .q(mosi));
    pvm_hostif dut (
        .clk(clk), .rst_n(rst_n), .sck(sck), .cs_n(cs_n), .mosi(mosi), .miso(miso),
        .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_we(bus_we),
        .bus_re(bus_re), .bus_rdata(bus_rdata), .bus_rack(bus_rack)
    );

    // Register the bus response exactly one edge after the request was presented.
    always @(posedge clk) begin
        if (!rst_n)
            bus_rdata <= 8'h00;
        else begin
            cycles = cycles + 1;
            case ({bus_we, bus_re, bus_rack})
                3'b000, WRITE_EVENT, READ_EVENT, ACK_EVENT: begin end
                default: strobe_ok = 1'b0;
            endcase
            if (bus_we || bus_re || bus_rack) begin
                event_kind[events] = {bus_we, bus_re, bus_rack};
                event_addr[events] = bus_addr;
                event_data[events] = bus_wdata;
                event_cycle[events] = cycles;
                events = events + 1;
            end
            if (bus_we)
                mem[bus_addr] <= bus_wdata;
            if (bus_re)
                bus_rdata <= mem[bus_addr];
        end
    end

    task select_chip(input selected);
        begin
            @(negedge clk);
            cs_n_pad = !selected;
            repeat (8) @(negedge clk);
        end
    endtask

    task spi_bit(input bit_out, output reg bit_in);
        begin
            mosi_pad = bit_out;
            repeat (8) @(negedge clk);
            sck_pad = 1'b1;
            #1;
            bit_in = miso;
            repeat (8) @(negedge clk);
            sck_pad = 1'b0;
        end
    endtask

    task spi_xfer(input [7:0] byte_out, output reg [7:0] byte_in);
        integer n;
        reg bit_in;
        begin
            for (n = 7; n >= 0; n = n - 1) begin
                spi_bit(byte_out[n], bit_in);
                byte_in[n] = bit_in;
            end
        end
    endtask

    task send_header(input [7:0] cmd, input [15:0] addr);
        reg [7:0] received;
        begin
            select_chip(1'b1);
            spi_xfer(cmd, received);
            spi_xfer(addr[15:8], received);
            spi_xfer(addr[7:0], received);
        end
    endtask

    function saw_write;
        input integer index;
        input [15:0] addr;
        input [7:0] data;
        begin
            saw_write = (event_kind[index] === WRITE_EVENT) &&
                        (event_addr[index] === addr) && (event_data[index] === data);
        end
    endfunction

    function saw_read;
        input integer index;
        input [15:0] addr;
        begin
            saw_read = (event_kind[index] === READ_EVENT) && (event_addr[index] === addr);
        end
    endfunction

    function saw_ack_then_read;
        input integer index;
        input [15:0] addr;
        begin
            saw_ack_then_read = (event_kind[index] === ACK_EVENT) &&
                (event_addr[index] === addr) && saw_read(index+1, addr+16'd1) &&
                (event_cycle[index+1] == event_cycle[index]+1);
        end
    endfunction

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

    initial begin
        $display("CONFIG: TOP=tb_hostif CHECKS=%0d", N_CHECKS);
        $display("SEED %04h", rng);
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_hostif.vcd");
            $dumpvars(0, tb_hostif);
        end
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        origin = events;
        send_header(8'h02, 16'h0400);
        spi_xfer(8'h32, host_in);
        select_chip(1'b0);
        check("WRITE_SINGLE", (host_in === 8'h00) && (events == origin+1) &&
              saw_write(origin, 16'h0400, 8'h32));

        origin = events;
        test_addr = rng;
        send_header(8'h02, test_addr);
        ok = 1'b1;
        for (i = 0; i < 16; i = i + 1) begin
            rng = {rng[14:0], rng[15] ^ rng[13] ^ rng[12] ^ rng[10]};
            generated_byte = rng[7:0];
            spi_xfer(generated_byte, host_in);
            ok = ok && saw_write(origin+i, test_addr + i[15:0], generated_byte) &&
                 (host_in === 8'h00);
        end
        select_chip(1'b0);
        check("WRITE_BURST_16", ok && (events == origin+16));

        origin = events;
        send_header(8'h02, 16'hffff);
        spi_xfer(8'h3d, host_in);
        spi_xfer(8'h88, host_in);
        select_chip(1'b0);
        check("WRITE_ADDR_WRAP_FFFF", (events == origin+2) &&
              saw_write(origin, 16'hffff, 8'h3d) && saw_write(origin+1, 16'h0000, 8'h88));

        mem[16'h0f01] = 8'h29;
        mem[16'h0f02] = 8'h72;
        read_start = events;
        send_header(8'h03, 16'h0f01);
        spi_xfer(8'hcc, host_in);
        ok = host_in === 8'h00;
        spi_xfer(8'h00, host_in);
        select_chip(1'b0);
        check("READ_SINGLE", ok && (host_in === 8'h29));
        seq_ok = (events == read_start+3) && saw_read(read_start, 16'h0f01) &&
                 saw_ack_then_read(read_start+1, 16'h0f01);

        test_addr = 16'h0717;
        for (i = 0; i <= 8; i = i + 1)
            mem[test_addr+i[15:0]] = 8'hd4 ^ (i[7:0] * 8'd23);
        read_start = events;
        send_header(8'h03, test_addr);
        spi_xfer(8'ha9, host_in);
        ok = host_in === 8'h00;
        seq_ok = seq_ok && saw_read(read_start, test_addr);
        for (i = 0; i < 8; i = i + 1) begin
            spi_xfer(8'h5a, host_in);
            ok = ok && (host_in === (8'hd4 ^ (i[7:0] * 8'd23)));
            seq_ok = seq_ok && saw_ack_then_read(read_start+1+2*i, test_addr+i[15:0]);
        end
        select_chip(1'b0);
        check("READ_BURST_8", ok);
        check("READ_RACK_SEQUENCE", seq_ok && (events == read_start+17));

        origin = events;
        select_chip(1'b1);
        spi_xfer(8'h9f, host_in);
        ok = host_in === 8'h00;
        spi_xfer(8'h00, host_in);
        ok = ok && (host_in === 8'h50);
        spi_xfer(8'h00, host_in);
        ok = ok && (host_in === 8'h56);
        spi_xfer(8'h00, host_in);
        ok = ok && (host_in === 8'h4d);
        spi_xfer(8'h00, host_in);
        ok = ok && (host_in === 8'h21);
        spi_xfer(8'h00, host_in);
        select_chip(1'b0);
        check("ID_BYTES", ok && (events == origin) && (host_in === 8'h00));

        select_chip(1'b1);
        spi_xfer(8'hb2, host_in);
        ok = host_in === 8'h00;
        spi_xfer(8'h02, host_in);
        ok = ok && (host_in === 8'h00);
        spi_xfer(8'h9f, host_in);
        select_chip(1'b0);
        check("UNKNOWN_CMD_IGNORED", ok && (events == origin) && (host_in === 8'h00));

        select_chip(1'b1);
        spi_xfer(8'h02, host_in);
        spi_xfer(8'h70, host_in);
        spi_bit(1'b1, unused_miso);
        spi_bit(1'b0, unused_miso);
        spi_bit(1'b1, unused_miso);
        select_chip(1'b0);
        check("ABORT_IN_ADDR", events == origin);

        send_header(8'h02, 16'h09a3);
        spi_xfer(8'hcd, host_in);
        spi_bit(1'b0, unused_miso);
        spi_bit(1'b1, unused_miso);
        spi_bit(1'b1, unused_miso);
        select_chip(1'b0);
        check("ABORT_IN_DATA", (events == origin+1) && saw_write(origin, 16'h09a3, 8'hcd));
        check("ONE_STROBE_PER_CYCLE", strobe_ok);

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == N_CHECKS) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #400000;
        $display("TB_TIMEOUT hostif");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
