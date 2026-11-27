`timescale 1ns/1ps
`default_nettype none

module pvm_arty_top (
    input wire clk100, board_reset_n, usb_uart_rx, fixture_switch,
    output wire usb_uart_tx,
    input wire [4:0] protocol_in,
    output wire [6:0] protocol_out,
    inout wire [7:0] protocol_io,
    output wire [1:0] i2c_pullup,
    output wire [3:0] host_spi_probe,
    output wire [3:0] led
);
    wire clk50, locked;
`ifdef SIM
    reg sim_clk50;
    reg [4:0] sim_lock_delay;
    always @(posedge clk100 or negedge board_reset_n) begin
        if (!board_reset_n) begin
            sim_clk50 <= 1'b0;
            sim_lock_delay <= 0;
        end else begin
            sim_clk50 <= !sim_clk50;
            if (!sim_lock_delay[4]) sim_lock_delay <= sim_lock_delay + 1'b1;
        end
    end
    assign clk50 = sim_clk50;
    assign locked = sim_lock_delay[4];
`else
    wire raw_clk50, mmcm_feedback, buffered_feedback;
    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.0), .CLKOUT0_DIVIDE_F(20.0)
    ) mmcm (
        .CLKIN1(clk100), .RST(!board_reset_n), .PWRDWN(1'b0),
        .CLKFBIN(buffered_feedback), .CLKFBOUT(mmcm_feedback),
        .CLKOUT0(raw_clk50), .LOCKED(locked)
    );
    BUFG feedback_buf (.I(mmcm_feedback), .O(buffered_feedback));
    BUFG core_buf (.I(raw_clk50), .O(clk50));
`endif

    wire board_clock_ready = board_reset_n && locked;
    (* ASYNC_REG = "TRUE" *) reg [1:0] bridge_reset_release;
    always @(posedge clk50 or negedge board_clock_ready) begin
        if (!board_clock_ready) bridge_reset_release <= 0;
        else bridge_reset_release <= {bridge_reset_release[0], 1'b1};
    end
    wire bridge_reset_n = bridge_reset_release[1];

    wire host_reset_n, spi_sck, spi_cs_n, spi_mosi;
    wire [7:0] pvm_uo, pvm_uio_out, pvm_uio_oe, pvm_uio_in;
    uart_spi_bridge host_bridge (
        .clk(clk50), .rst_n(bridge_reset_n), .uart_rx(usb_uart_rx), .uart_tx(usb_uart_tx),
        .spi_sck(spi_sck), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .spi_miso(pvm_uo[7]), .host_reset_n(host_reset_n)
    );

    wire pvm_reset_request_n = board_clock_ready && host_reset_n;
    (* ASYNC_REG = "TRUE" *) reg [1:0] pvm_reset_release;
    reg [15:0] startup_hold;
    always @(posedge clk50 or negedge pvm_reset_request_n) begin
        if (!pvm_reset_request_n) begin
            pvm_reset_release <= 0;
            startup_hold <= 0;
        end else begin
            pvm_reset_release <= {pvm_reset_release[0], 1'b1};
            startup_hold <= {startup_hold[14:0], pvm_reset_release[1]};
        end
    end
    wire pvm_reset_n = startup_hold[15];

    (* ASYNC_REG = "TRUE" *) reg [1:0] fixture_select_sync;
    always @(posedge clk50) begin
        if (!bridge_reset_n) fixture_select_sync <= 0;
        else fixture_select_sync <= {fixture_select_sync[0], fixture_switch};
    end
    wire fixture_enabled = fixture_select_sync[1];
    wire fixture_sda_low, fixture_scl_low;
    i2c_target_fixture target (
        .clk(clk50), .rst_n(pvm_reset_n && fixture_enabled),
        .sda(pvm_uio_in[0]), .scl(pvm_uio_in[1]),
        .sda_low(fixture_sda_low), .scl_low(fixture_scl_low)
    );
    wire [7:0] fixture_low = fixture_enabled && pvm_reset_n ?
                            {6'b0,fixture_scl_low,fixture_sda_low} : 8'b0;
    genvar p;
    generate for(p=0;p<8;p=p+1) begin : pins
        wire pad_release = !(pvm_uio_oe[p] || fixture_low[p]);
        wire pad_drive = pvm_uio_out[p] && !fixture_low[p];
`ifdef SIM
        assign protocol_io[p] = pad_release ? 1'bz : pad_drive;
        assign pvm_uio_in[p] = protocol_io[p];
`else
        IOBUF buffer (.IO(protocol_io[p]), .T(pad_release), .I(pad_drive), .O(pvm_uio_in[p]));
`endif
    end endgenerate

    tt_um_arnav1609_pvm pvm (
        .ui_in({protocol_in,spi_mosi,spi_cs_n,spi_sck}), .uo_out(pvm_uo),
        .uio_in(pvm_uio_in), .uio_out(pvm_uio_out), .uio_oe(pvm_uio_oe),
        .ena(1'b1), .clk(clk50), .rst_n(pvm_reset_n)
    );
    assign protocol_out = pvm_uo[6:0];
    // These pins supply the resistor ends on J3. SDA/SCL use separate IOBUFs.
    assign i2c_pullup = 2'b11;
    assign host_spi_probe = {pvm_uo[7],spi_mosi,spi_cs_n,spi_sck};

    reg [24:0] heartbeat;
    reg [19:0] activity;
    always @(posedge clk50) begin
        if (!bridge_reset_n) begin heartbeat <= 0; activity <= 0; end
        else begin
            heartbeat <= heartbeat + 1'b1;
            if (!spi_cs_n) activity <= 20'hfffff;
            else if (activity != 0) activity <= activity - 1'b1;
        end
    end
    assign led = {|activity,heartbeat[24],pvm_reset_n,locked};

`ifndef SIM
    // Full-rate pad samples. Separate probes keep the export unambiguous.
    pvm_ila analyzer (
        .clk(clk50), .probe0(pvm_uo[0]), .probe1(pvm_uo[1]), .probe2(pvm_uo[2]),
        .probe3(pvm_uio_in[0]), .probe4(pvm_uio_in[1]), .probe5(spi_sck),
        .probe6(spi_cs_n), .probe7(spi_mosi), .probe8(pvm_uo[7]),
        .probe9(pvm_reset_n), .probe10(pvm_uio_oe), .probe11(pvm_uio_out)
    );
`endif
endmodule
`default_nettype wire
