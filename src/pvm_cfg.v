`timescale 1ns/1ps
`default_nettype none

// Decode the host byte bus and own configuration, lifecycle, and fault status.
// Owner: Kalash Bheda. PVM S06–S07. See 03_BUS_AND_REGMAP.md, 07_FAULTS_LIFECYCLE.md, D-012.
module pvm_cfg (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [15:0]  bus_addr,
    input  wire [7:0]   bus_wdata,
    input  wire         bus_we,
    input  wire         bus_re,
    input  wire         bus_rack,
    output reg  [7:0]   bus_rdata,

    output wire         imem_wr_en,
    output wire [5:0]   imem_wr_addr,
    output wire [7:0]   imem_wr_data,
    output wire         imem_clr_valid,
    output wire [5:0]   imem_bus_rd_addr,
    input  wire [7:0]   imem_bus_rd_data,
    input  wire         imem_entry_valid,

    output wire         tx_push,
    output wire [7:0]   tx_data,
    output wire         rx_pop,
    output wire         fifo_clr,
    input  wire [2:0]   tx_level,
    input  wire [2:0]   rx_level,
    input  wire [7:0]   rx_head,
    input  wire         tx_fifo_ovf,
    input  wire         rx_fifo_unf,

    input  wire         eng_done_req,
    input  wire         eng_fault_req,
    input  wire [3:0]   eng_fault_code,
    input  wire [4:0]   eng_pc,
    input  wire [7:0]   flags,
    output reg  [2:0]   state,
    output reg          enable_pulse,
    output wire         halt_pulse,
    output wire         clr_flags_pulse,

    output wire [15:0]  clkdiv,
    output wire [4:0]   out_base, out_cnt, set_base, in_base, side_base, jmp_pin,
    output wire [2:0]   set_cnt,
    output wire [1:0]   side_cnt,
    output wire [4:0]   wrap_bottom, wrap_top, shiftctrl, pull_thresh, push_thresh, entry_pc,
    output wire [15:0]  timeout,
    output wire [1:0]   to_presc,

    // LUT n: cfg_lut[32*n+:32] = {SEL3,SEL2,SEL1,SEL0,TT[15:0]}.
    // Its GROUP and output mode occupy cfg_mode[3*n+:3].
    output wire [127:0] cfg_lut,
    output wire [11:0]  cfg_mode,
    output wire [9:0]   cnt_reload,
    output wire         cnt_en, cnt_src, manch_en,
    output wire         arb_en,
    output wire [3:0]   arb_n,
    output wire [4:0]   arb_sda, arb_scl,

    output wire [191:0] cfg_entries,
    output wire [63:0]  cfg_k,
    output wire [15:0]  cfg_m,
    output wire         mon_en,
    output wire [1:0]   mon_presc,
    input  wire [15:0]  cnt_pass, cnt_viol, cnt_inc,
    input  wire [2:0]   mon_state,
    input  wire [159:0] log_flat,
    input  wire [1:0]   log_wptr,
    input  wire [5:0]   log_total,

    output wire [139:0] pin_cfg
);
    localparam [2:0] S_HALT = 3'd0, S_VALIDATING = 3'd1, S_READY = 3'd2,
                     S_RUN = 3'd3, S_DONE = 3'd4, S_FAULT = 3'd5;
    localparam [7:0] C_HALT = 8'h01, C_VALIDATE = 8'h02, C_ENABLE = 8'h03,
                     C_CLR_IMEM = 8'h04, C_CLR_FAULT = 8'h05, C_CLR_FLAGS = 8'h06;
    localparam [3:0] F_NONE = 4'd0, F_DONE = 4'd1, F_CRC_FAIL = 4'd5,
                     F_PIN_CONFLICT = 4'd6, F_CFG_INVALID = 4'd7;
    localparam [2:0] V_CRC = 3'd0, V_PINS = 3'd1, V_ENGINE = 3'd2,
                     V_FABRIC = 3'd3, V_MONITOR = 3'd4;
    localparam [2:0] V_START = V_CRC, V_AFTER_CRC = V_PINS, V_AFTER_PINS = V_ENGINE;

    reg [7:0] eng_cfg [0:18];
    reg [7:0] fab_cfg [0:38];
    reg [7:0] mon_cfg [0:42];
    reg [6:0] pins [0:19];
    reg [15:0] crc_expect_q;
    reg [7:0] image_ver_q, image_ver_committed_q;
    reg [15:0] image_crc_q;
    reg [2:0] validate_phase_q;
    reg [4:0] validate_index_q;
    reg [3:0] validation_fault;
    wire [2:0] validate_owner;
    wire [1:0] validate_mode;
    wire pin_bad_encoding, pin_od_on_uo, pin_output_on_ui, pin_owner_on_input;
    wire bad_engine, bad_fabric, bad_monitor;
    wire [2:0] monitor_valid_guard;
    wire [2:0] monitor_action;
    wire [15:0] crc_calc;
    reg [15:0] time_q, fault_time_q;
    reg [4:0] fault_pc_q;
    reg [3:0] fault_code_q;
    reg wr_rej_q, tx_ovf_q, rx_unf_q, crc_ok_q;
    reg [7:0] read_byte;
    wire [7:0] eng_mask, fab_mask, mon_mask;
    wire [7:0] offset;
    wire is_imem, is_eng, is_fab, is_mon, is_pin, is_crc_expect, is_image_ver;
    wire ctrl_write, wh_addr, wh_write, ctrl_ok, crc_en;
    wire [39:0] log_entry;
    integer i;
    genvar idx;

    function [7:0] eng_write_mask;
        input [7:0] addr;
        begin
            case (addr)
                8'h00, 8'h01, 8'h10, 8'h11: eng_write_mask = 8'hff;
                8'h02, 8'h03, 8'h04, 8'h06, 8'h07, 8'h09, 8'h0a,
                8'h0b, 8'h0c, 8'h0d, 8'h0e, 8'h0f: eng_write_mask = 8'h1f;
                8'h05: eng_write_mask = 8'h07;
                8'h08, 8'h12: eng_write_mask = 8'h03;
                default: eng_write_mask = 8'h00;
            endcase
        end
    endfunction

    function [7:0] fab_write_mask;
        input [7:0] addr;
        begin
            if (addr < 8'h20) begin
                case (addr[2:0])
                    3'd0, 3'd1, 3'd2, 3'd3: fab_write_mask = 8'hff;
                    3'd4: fab_write_mask = 8'h07;
                    default: fab_write_mask = 8'h00;
                endcase
            end else begin
                case (addr)
                    8'h20: fab_write_mask = 8'hff;
                    8'h21: fab_write_mask = 8'h03;
                    8'h22: fab_write_mask = 8'h07;
                    8'h24: fab_write_mask = 8'hf1;
                    8'h25, 8'h26: fab_write_mask = 8'h1f;
                    default: fab_write_mask = 8'h00;
                endcase
            end
        end
    endfunction

    function [7:0] mon_write_mask;
        input [7:0] addr;
        begin
            if (addr < 8'h20) begin
                case (addr[1:0])
                    2'd0, 2'd1: mon_write_mask = 8'hff;
                    2'd2: mon_write_mask = 8'h1f;
                    default: mon_write_mask = 8'h00;
                endcase
            end else if (addr < 8'h2a)
                mon_write_mask = 8'hff;
            else if (addr == 8'h2a)
                mon_write_mask = 8'h07;
            else
                mon_write_mask = 8'h00;
        end
    endfunction

    assign offset = bus_addr[7:0];
    assign eng_mask = eng_write_mask(offset);
    assign fab_mask = fab_write_mask(offset);
    assign mon_mask = mon_write_mask(offset);
    assign is_imem = bus_addr < 16'h0040;
    assign is_eng = (bus_addr[15:8] == 8'h01) && (eng_mask != 8'h00);
    assign is_fab = (bus_addr[15:8] == 8'h02) && (fab_mask != 8'h00);
    assign is_mon = (bus_addr[15:8] == 8'h03) && (mon_mask != 8'h00);
    assign is_pin = (bus_addr[15:8] == 8'h04) && (offset < 8'h14);
    assign is_crc_expect = bus_addr == 16'h0f08 || bus_addr == 16'h0f09;
    assign is_image_ver = bus_addr == 16'h0f0a;
    assign wh_addr = is_imem || is_eng || is_fab || is_mon || is_pin || is_crc_expect || is_image_ver;
    assign wh_write = bus_we && !ctrl_write && wh_addr && (state == S_HALT);

    assign ctrl_write = bus_we && (bus_addr == 16'h0f00);
    assign halt_pulse = rst_n && ctrl_write && (bus_wdata == C_HALT);
    assign clr_flags_pulse = rst_n && ctrl_write && (bus_wdata == C_CLR_FLAGS);
    assign ctrl_ok = halt_pulse || clr_flags_pulse ||
                     ((bus_wdata == C_VALIDATE || bus_wdata == C_CLR_IMEM) && state == S_HALT) ||
                     (bus_wdata == C_ENABLE && state == S_READY) ||
                     (bus_wdata == C_CLR_FAULT && (state == S_DONE || state == S_FAULT));
    assign fifo_clr = halt_pulse;
    assign imem_clr_valid = rst_n && ctrl_write && ctrl_ok && (bus_wdata == C_CLR_IMEM);
    assign imem_wr_en = rst_n && wh_write && is_imem;
    assign imem_wr_addr = bus_addr[5:0];
    assign imem_wr_data = bus_wdata;
    assign imem_bus_rd_addr = bus_addr[5:0];
    assign tx_push = rst_n && bus_we && (bus_addr == 16'h0f10);
    assign tx_data = bus_wdata;
    assign rx_pop = rst_n && bus_rack && (bus_addr == 16'h0f11);
    // CRC consumes the original accepted byte, before reserved bits are masked.
    assign crc_en = wh_write && !is_crc_expect;

    pvm_crc16 crc_accumulator (
        .clk(clk), .rst_n(rst_n), .clr(halt_pulse), .en(crc_en), .din(bus_wdata), .crc(crc_calc)
    );

    assign clkdiv = {eng_cfg[1], eng_cfg[0]};
    assign out_base = eng_cfg[2][4:0];
    assign out_cnt = eng_cfg[3][4:0];
    assign set_base = eng_cfg[4][4:0];
    assign set_cnt = eng_cfg[5][2:0];
    assign in_base = eng_cfg[6][4:0];
    assign side_base = eng_cfg[7][4:0];
    assign side_cnt = eng_cfg[8][1:0];
    assign jmp_pin = eng_cfg[9][4:0];
    assign wrap_bottom = eng_cfg[10][4:0];
    assign wrap_top = eng_cfg[11][4:0];
    assign shiftctrl = eng_cfg[12][4:0];
    assign pull_thresh = eng_cfg[13][4:0];
    assign push_thresh = eng_cfg[14][4:0];
    assign entry_pc = eng_cfg[15][4:0];
    assign timeout = {eng_cfg[17], eng_cfg[16]};
    assign to_presc = eng_cfg[18][1:0];

    generate
        for (idx = 0; idx < 4; idx = idx + 1) begin : lut_config
            assign cfg_lut[idx*32+:32] = {fab_cfg[8*idx+3], fab_cfg[8*idx+2], fab_cfg[8*idx+1], fab_cfg[8*idx]};
            assign cfg_mode[idx*3+:3] = fab_cfg[8*idx+4][2:0];
        end
        for (idx = 0; idx < 8; idx = idx + 1) begin : monitor_config
            assign cfg_entries[idx*24+:24] = {mon_cfg[4*idx+2], mon_cfg[4*idx+1], mon_cfg[4*idx]};
            assign cfg_k[idx*8+:8] = mon_cfg[32+idx];
        end
        for (idx = 0; idx < 20; idx = idx + 1) begin : pin_config
            assign pin_cfg[idx*7+:7] = pins[idx];
        end
    endgenerate
    assign cnt_reload = {fab_cfg[33][1:0], fab_cfg[32]};
    assign {manch_en, cnt_src, cnt_en} = fab_cfg[34][2:0];
    assign arb_en = fab_cfg[36][0];
    assign arb_n = fab_cfg[36][7:4];
    assign arb_sda = fab_cfg[37][4:0];
    assign arb_scl = fab_cfg[38][4:0];
    assign cfg_m = {mon_cfg[41], mon_cfg[40]};
    assign {mon_presc, mon_en} = mon_cfg[42][2:0];

    // Validate in register-map order, one pin and one monitor rule per cycle.
    assign validate_owner = pins[validate_index_q][2:0];
    assign validate_mode = pins[validate_index_q][4:3];
    assign pin_bad_encoding = validate_owner == 3'd7 || validate_mode == 2'd3;
    assign pin_od_on_uo = (validate_mode == 2'd2) &&
                          (validate_index_q >= 5'd5 && validate_index_q <= 5'd11);
    assign pin_output_on_ui = (validate_mode != 2'd0) && (validate_index_q < 5'd5);
    assign pin_owner_on_input = (validate_owner != 3'd0) && (validate_mode == 2'd0);

    assign bad_engine = (out_cnt > 5'd16) || (set_cnt > 3'd5) || (side_cnt == 2'd3) ||
                        (out_base > 5'd19) || (set_base > 5'd19) || (in_base > 5'd19) ||
                        (side_base > 5'd19) || (jmp_pin > 5'd19) ||
                        (wrap_bottom > wrap_top) || !imem_entry_valid;
    assign bad_fabric = (cfg_mode[1:0] == 2'd3) || (cfg_mode[4:3] == 2'd3) ||
                        (cfg_mode[7:6] == 2'd3) || (cfg_mode[10:9] == 2'd3) ||
                        (manch_en && !cnt_en) ||
                        (arb_en && ((arb_n == 4'd0) ||
                                    (arb_sda < 5'd12) || (arb_sda > 5'd19) ||
                                    (arb_scl < 5'd12) || (arb_scl > 5'd19) ||
                                    (pins[arb_sda][4:3] != 2'd2) || (pins[arb_scl][4:3] != 2'd2)));

    assign monitor_valid_guard = mon_cfg[{1'b0, validate_index_q[2:0], 2'd1}][7:5];
    assign monitor_action = mon_cfg[{1'b0, validate_index_q[2:0], 2'd2}][4:2];
    assign bad_monitor = monitor_valid_guard[2] && ((monitor_valid_guard[1:0] == 2'd3) || (monitor_action == 3'd7));

    always @(*) begin
        validation_fault = F_NONE;
        case (validate_phase_q)
            V_CRC: if (crc_calc != crc_expect_q)
                validation_fault = F_CRC_FAIL;
            V_PINS: begin
                if (pin_bad_encoding)
                    validation_fault = F_CFG_INVALID;
                else if (pin_od_on_uo || pin_output_on_ui || pin_owner_on_input)
                    validation_fault = F_PIN_CONFLICT;
            end
            V_ENGINE: if (bad_engine) validation_fault = F_CFG_INVALID;
            V_FABRIC: if (bad_fabric) validation_fault = F_CFG_INVALID;
            V_MONITOR: if (bad_monitor) validation_fault = F_CFG_INVALID;
            default: validation_fault = F_CFG_INVALID;
        endcase
    end

    assign log_entry = log_flat[40*bus_addr[4:3]+:40];

    always @(*) begin
        read_byte = 8'h00;
        if (is_imem)
            read_byte = imem_bus_rd_data;
        else if (is_eng)
            read_byte = eng_cfg[offset[4:0]];
        else if (is_fab)
            read_byte = fab_cfg[offset[5:0]];
        else if (is_mon)
            read_byte = mon_cfg[offset[5:0]];
        else if (is_pin)
            read_byte = {1'b0, pins[offset[4:0]]};
        else if (bus_addr >= 16'h0f80 && bus_addr <= 16'h0f9f && bus_addr[2:0] <= 3'd4)
            read_byte = log_entry[8*bus_addr[2:0]+:8];
        else begin
            case (bus_addr)
                16'h0330: read_byte = cnt_pass[7:0];
                16'h0331: read_byte = cnt_pass[15:8];
                16'h0332: read_byte = cnt_viol[7:0];
                16'h0333: read_byte = cnt_viol[15:8];
                16'h0334: read_byte = cnt_inc[7:0];
                16'h0335: read_byte = cnt_inc[15:8];
                16'h0336: read_byte = {5'b00000, mon_state};
                16'h0f01: read_byte = {1'b0, crc_ok_q, rx_unf_q, tx_ovf_q, wr_rej_q, state};
                16'h0f02: read_byte = {4'h0, fault_code_q};
                16'h0f03: read_byte = {3'b000, fault_pc_q};
                16'h0f04: read_byte = fault_time_q[7:0];
                16'h0f05: read_byte = fault_time_q[15:8];
                16'h0f06: read_byte = crc_calc[7:0];
                16'h0f07: read_byte = crc_calc[15:8];
                16'h0f08: read_byte = crc_expect_q[7:0];
                16'h0f09: read_byte = crc_expect_q[15:8];
                16'h0f0a: read_byte = image_ver_q;
                16'h0f0b: read_byte = flags;
                16'h0f0c: read_byte = {3'b000, eng_pc};
                16'h0f11: read_byte = (rx_level == 3'd0) ? 8'h00 : rx_head;
                16'h0f12: read_byte = {1'b0, rx_level, 1'b0, tx_level};
                16'h0f20: read_byte = image_crc_q[7:0];
                16'h0f21: read_byte = image_crc_q[15:8];
                16'h0f22: read_byte = image_ver_committed_q;
                16'h0fa0: read_byte = {log_total, log_wptr};
                default: read_byte = 8'h00;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            bus_rdata <= 8'h00;
            crc_expect_q <= 16'h0000;
            image_ver_q <= 8'h00;
            for (i = 0; i < 19; i = i + 1)
                eng_cfg[i] <= 8'h00;
            for (i = 0; i < 39; i = i + 1)
                fab_cfg[i] <= 8'h00;
            for (i = 0; i < 43; i = i + 1)
                mon_cfg[i] <= 8'h00;
            for (i = 0; i < 20; i = i + 1)
                pins[i] <= 7'h00;
        end else begin
            if (bus_re)
                bus_rdata <= read_byte;
            if (wh_write) begin
                if (is_eng)
                    eng_cfg[offset[4:0]] <= bus_wdata & eng_mask;
                else if (is_fab)
                    fab_cfg[offset[5:0]] <= bus_wdata & fab_mask;
                else if (is_mon)
                    mon_cfg[offset[5:0]] <= bus_wdata & mon_mask;
                else if (is_pin)
                    pins[offset[4:0]] <= bus_wdata[6:0];
                else if (is_crc_expect) begin
                    if (offset[0])
                        crc_expect_q[15:8] <= bus_wdata;
                    else
                        crc_expect_q[7:0] <= bus_wdata;
                end else if (is_image_ver)
                    image_ver_q <= bus_wdata;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_HALT;
            enable_pulse <= 1'b0;
            wr_rej_q <= 1'b0;
            tx_ovf_q <= 1'b0;
            rx_unf_q <= 1'b0;
            crc_ok_q <= 1'b0;
            time_q <= 16'h0000;
            fault_time_q <= 16'h0000;
            fault_pc_q <= 5'd0;
            fault_code_q <= F_NONE;
            image_crc_q <= 16'h0000;
            image_ver_committed_q <= 8'h00;
            validate_phase_q <= V_START;
            validate_index_q <= 5'd0;
        end else begin
            enable_pulse <= 1'b0;
            time_q <= time_q + 16'd1;
            if (halt_pulse) begin
                state <= S_HALT;
                wr_rej_q <= 1'b0;
                tx_ovf_q <= 1'b0;
                rx_unf_q <= 1'b0;
            end else begin
                if (bus_we && !(wh_write || tx_push || (ctrl_write && ctrl_ok)))
                    wr_rej_q <= 1'b1;
                if (tx_fifo_ovf)
                    tx_ovf_q <= 1'b1;
                if (rx_fifo_unf)
                    rx_unf_q <= 1'b1;

                case (state)
                    S_HALT: begin
                        if (ctrl_write && bus_wdata == C_VALIDATE) begin
                            state <= S_VALIDATING;
                            validate_phase_q <= V_START;
                            validate_index_q <= 5'd0;
                        end
                    end
                    S_VALIDATING: begin
                        if (validate_phase_q == V_CRC)
                            crc_ok_q <= crc_calc == crc_expect_q;
                        if (validation_fault != F_NONE) begin
                            state <= S_FAULT;
                            fault_code_q <= validation_fault;
                            fault_pc_q <= 5'd0;
                            fault_time_q <= time_q;
                        end else begin
                            case (validate_phase_q)
                                V_CRC: validate_phase_q <= V_AFTER_CRC;
                                V_PINS: begin
                                    if (validate_index_q == 5'd19) begin
                                        validate_phase_q <= V_AFTER_PINS;
                                        validate_index_q <= 5'd0;
                                    end else
                                        validate_index_q <= validate_index_q + 5'd1;
                                end
                                V_ENGINE: validate_phase_q <= V_FABRIC;
                                V_FABRIC: validate_phase_q <= V_MONITOR;
                                V_MONITOR: begin
                                    if (validate_index_q == 5'd7) begin
                                        state <= S_READY;
                                        {image_crc_q, image_ver_committed_q} <= {crc_expect_q, image_ver_q};
                                    end else
                                        validate_index_q <= validate_index_q + 5'd1;
                                end
                                default: validate_phase_q <= V_START;
                            endcase
                        end
                    end
                    S_READY: begin
                        if (ctrl_write && bus_wdata == C_ENABLE) begin
                            state <= S_RUN;
                            enable_pulse <= 1'b1;
                        end
                    end
                    S_RUN: begin
                        if (eng_fault_req || eng_done_req) begin
                            state <= eng_fault_req ? S_FAULT : S_DONE;
                            fault_code_q <= eng_fault_req ? eng_fault_code : F_DONE;
                            fault_pc_q <= eng_pc;
                            fault_time_q <= time_q;
                        end
                    end
                    S_DONE, S_FAULT: begin
                        if (ctrl_write && bus_wdata == C_CLR_FAULT) begin
                            state <= S_HALT;
                            fault_code_q <= F_NONE;
                            fault_pc_q <= 5'd0;
                            fault_time_q <= 16'h0000;
                        end
                    end
                    default: state <= S_HALT;
                endcase
            end
        end
    end
endmodule

`default_nettype wire
