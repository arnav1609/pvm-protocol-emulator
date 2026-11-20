`timescale 1ns/1ps
`default_nettype none

// PVM pad mapping, host bus, and configuration datapath.
// Owner: Kalash Bheda. PVM S08/S11. See 02_PINS_AND_TOP.md and 03_BUS_AND_REGMAP.md.
module pvm_top (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       clk,
    input  wire       rst_n
);
    wire [2:0] host_in;
    wire [4:0] protocol_ui;
    wire [7:0] protocol_uio;
    wire [6:0] uo_readback;
    wire [19:0] pin_in = {protocol_uio, uo_readback, protocol_ui};
    wire [19:0] unused_od_release_intent;
    wire [15:0] bus_addr;
    wire [7:0] bus_wdata, bus_rdata;
    wire bus_we, bus_re, bus_rack;
    wire imem_wr_en, imem_clr_valid, instr_valid, entry_valid;
    wire engine_running = state == 3'd3;
    wire [4:0] engine_pc, engine_rd_pc;
    wire eng_done_req, eng_fault_req;
    wire [3:0] eng_fault_code;
    wire [19:0] engine_out, engine_oe;
    wire [7:2] user_flags;
    wire engine_tx_pop, engine_rx_push;
    wire [7:0] engine_rx_data;
    wire unused_engine_tick, unused_fab_wr, unused_evt_clr_arb, unused_evt_clr_unf;
    wire [3:0] unused_fab_ctrl;
    wire [5:0] imem_wr_addr, imem_bus_rd_addr;
    wire [7:0] imem_wr_data, imem_bus_rd_data;
    wire [15:0] instr;
    wire [4:0] entry_pc;
    wire tx_push, rx_pop, fifo_clr, tx_fifo_ovf, rx_fifo_unf;
    wire [2:0] tx_level, rx_level, state;
    wire [7:0] tx_data, rx_head, tx_head;
    wire tx_empty, unused_tx_full, unused_tx_unf;
    wire unused_rx_empty, rx_full, unused_rx_ovf;
    wire [139:0] pin_cfg;
    wire arb_en;
    wire [4:0] arb_sda, arb_scl;

    // Configuration fields for the engine and the later fabric and monitor.
    wire enable_pulse;
    wire unused_halt_pulse;
    wire unused_clr_flags_pulse;
    wire [15:0] clkdiv;
    wire [4:0] out_base;
    wire [4:0] out_cnt;
    wire [4:0] set_base;
    wire [4:0] in_base;
    wire [4:0] side_base;
    wire [4:0] jmp_pin;
    wire [2:0] set_cnt;
    wire [1:0] side_cnt;
    wire [4:0] wrap_bottom;
    wire [4:0] wrap_top;
    wire [4:0] shiftctrl;
    wire [4:0] pull_thresh;
    wire [4:0] push_thresh;
    wire [15:0] timeout;
    wire [1:0] to_presc;
    wire [127:0] unused_cfg_lut;
    wire [11:0] unused_cfg_mode;
    wire [9:0] unused_cnt_reload;
    wire unused_cnt_en;
    wire unused_cnt_src;
    wire unused_manch_en;
    wire [3:0] unused_arb_n;
    wire [191:0] unused_cfg_entries;
    wire [63:0] unused_cfg_k;
    wire [15:0] unused_cfg_m;
    wire unused_mon_en;
    wire [1:0] unused_mon_presc;

    // Host select resets to its inactive level. Every external input is sampled once.
    pvm_sync2 #(.W(3), .RST_VAL(3'b010)) host_inputs (
        .clk(clk), .rst_n(rst_n), .d(ui_in[2:0]), .q(host_in)
    );
    pvm_sync2 #(.W(5)) protocol_ui_inputs (
        .clk(clk), .rst_n(rst_n), .d(ui_in[7:3]), .q(protocol_ui)
    );
    pvm_sync2 #(.W(8)) protocol_uio_inputs (
        .clk(clk), .rst_n(rst_n), .d(uio_in), .q(protocol_uio)
    );

    pvm_hostif host (
        .clk(clk), .rst_n(rst_n), .sck(host_in[0]), .cs_n(host_in[1]), .mosi(host_in[2]),
        .miso(uo_out[7]), .bus_addr(bus_addr), .bus_wdata(bus_wdata), .bus_we(bus_we),
        .bus_re(bus_re), .bus_rdata(bus_rdata), .bus_rack(bus_rack)
    );

    pvm_imem memory (
        .clk(clk), .rst_n(rst_n), .wr_en(imem_wr_en), .wr_addr(imem_wr_addr),
        .wr_data(imem_wr_data), .clr_valid(imem_clr_valid), .rd_pc(engine_rd_pc),
        .entry_pc(entry_pc), .entry_valid(entry_valid),
        .bus_rd_addr(imem_bus_rd_addr), .bus_rd_data(imem_bus_rd_data),
        .instr(instr), .instr_valid(instr_valid)
    );

    pvm_fifo tx_fifo (
        .clk(clk), .rst_n(rst_n), .clr(fifo_clr), .push(tx_push), .din(tx_data), .pop(engine_tx_pop),
        .dout(tx_head), .full(unused_tx_full), .empty(tx_empty),
        .level(tx_level), .ovf(tx_fifo_ovf), .unf(unused_tx_unf)
    );

    pvm_fifo rx_fifo (
        .clk(clk), .rst_n(rst_n), .clr(fifo_clr), .push(engine_rx_push), .din(engine_rx_data), .pop(rx_pop),
        .dout(rx_head), .full(rx_full), .empty(unused_rx_empty),
        .level(rx_level), .ovf(unused_rx_ovf), .unf(rx_fifo_unf)
    );

    pvm_engine engine (
        .clk(clk), .rst_n(rst_n), .run(engine_running), .enable_pulse(enable_pulse),
        .clkdiv(clkdiv), .entry_pc(entry_pc), .wrap_bottom(wrap_bottom), .wrap_top(wrap_top),
        .out_base(out_base), .out_cnt(out_cnt), .set_base(set_base), .set_cnt(set_cnt),
        .in_base(in_base), .side_base(side_base), .side_cnt(side_cnt), .jmp_pin(jmp_pin),
        .wide(shiftctrl[4]), .pull_thresh(pull_thresh), .push_thresh(push_thresh),
        .out_shr(shiftctrl[0]), .in_shr(shiftctrl[1]),
        .autopull(shiftctrl[2]), .autopush(shiftctrl[3]), .timeout(timeout), .to_presc(to_presc),
        .instr(instr), .instr_valid(instr_valid), .pin_in(pin_in), .lut_out(4'd0),
        .arb_lost(1'b0), .underrun(1'b0), .tx_empty(tx_empty), .rx_full(rx_full),
        .tx_level(tx_level), .rx_level(rx_level), .tx_dout(tx_head), .tx_pop(engine_tx_pop),
        .rx_push(engine_rx_push), .rx_din(engine_rx_data), .rd_pc(engine_rd_pc),
        .out_val(engine_out), .oe_val(engine_oe), .fab_ctrl(unused_fab_ctrl),
        .fab_wr(unused_fab_wr), .user_flags(user_flags), .evt_clr_arb(unused_evt_clr_arb),
        .evt_clr_unf(unused_evt_clr_unf), .engine_tick(unused_engine_tick), .eng_pc(engine_pc),
        .eng_done_req(eng_done_req), .eng_fault_req(eng_fault_req), .eng_fault_code(eng_fault_code)
    );

    pvm_pin_guard pin_guard (
        .clk(clk), .rst_n(rst_n), .state(state), .pin_cfg(pin_cfg),
        .out_val(engine_out), .oe_val(engine_oe), .lut_out(4'd0),
        .arb_en(arb_en), .arb_lost(1'b0), .arb_sda(arb_sda), .arb_scl(arb_scl),
        .uo_pins(uo_out[6:0]), .uio_out(uio_out), .uio_oe(uio_oe),
        .uo_readback(uo_readback), .od_release_intent(unused_od_release_intent)
    );

    pvm_cfg config_bank (
        .clk(clk),
        .rst_n(rst_n),
        .bus_addr(bus_addr),
        .bus_wdata(bus_wdata),
        .bus_we(bus_we),
        .bus_re(bus_re),
        .bus_rack(bus_rack),
        .bus_rdata(bus_rdata),
        .imem_wr_en(imem_wr_en),
        .imem_wr_addr(imem_wr_addr),
        .imem_wr_data(imem_wr_data),
        .imem_clr_valid(imem_clr_valid),
        .imem_bus_rd_addr(imem_bus_rd_addr),
        .imem_bus_rd_data(imem_bus_rd_data),
        .imem_entry_valid(entry_valid),
        .tx_push(tx_push),
        .tx_data(tx_data),
        .rx_pop(rx_pop),
        .fifo_clr(fifo_clr),
        .tx_level(tx_level),
        .rx_level(rx_level),
        .rx_head(rx_head),
        .tx_fifo_ovf(tx_fifo_ovf),
        .rx_fifo_unf(rx_fifo_unf),
        .eng_done_req(eng_done_req),
        .eng_fault_req(eng_fault_req),
        .eng_fault_code(eng_fault_code),
        .eng_pc(engine_pc),
        .flags({user_flags, 2'b00}),
        .state(state),
        .enable_pulse(enable_pulse),
        .halt_pulse(unused_halt_pulse),
        .clr_flags_pulse(unused_clr_flags_pulse),
        .clkdiv(clkdiv),
        .out_base(out_base),
        .out_cnt(out_cnt),
        .set_base(set_base),
        .in_base(in_base),
        .side_base(side_base),
        .jmp_pin(jmp_pin),
        .set_cnt(set_cnt),
        .side_cnt(side_cnt),
        .wrap_bottom(wrap_bottom),
        .wrap_top(wrap_top),
        .shiftctrl(shiftctrl),
        .pull_thresh(pull_thresh),
        .push_thresh(push_thresh),
        .entry_pc(entry_pc),
        .timeout(timeout),
        .to_presc(to_presc),
        .cfg_lut(unused_cfg_lut),
        .cfg_mode(unused_cfg_mode),
        .cnt_reload(unused_cnt_reload),
        .cnt_en(unused_cnt_en),
        .cnt_src(unused_cnt_src),
        .manch_en(unused_manch_en),
        .arb_en(arb_en),
        .arb_n(unused_arb_n),
        .arb_sda(arb_sda),
        .arb_scl(arb_scl),
        .cfg_entries(unused_cfg_entries),
        .cfg_k(unused_cfg_k),
        .cfg_m(unused_cfg_m),
        .mon_en(unused_mon_en),
        .mon_presc(unused_mon_presc),
        .cnt_pass(16'h0000),
        .cnt_viol(16'h0000),
        .cnt_inc(16'h0000),
        .mon_state(3'd0),
        .log_flat(160'd0),
        .log_wptr(2'd0),
        .log_total(6'd0),
        .pin_cfg(pin_cfg)
    );
endmodule

`default_nettype wire
