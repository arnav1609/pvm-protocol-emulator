`timescale 1ns/1ps
`default_nettype none

// Execute PVM control-flow and register instructions on synchronous engine ticks.
// Owner: Kalash Bheda. PVM S09–S10. See 04_ISA.md and D-013 through D-015.
module pvm_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        run,
    input  wire        enable_pulse,
    input  wire [15:0] clkdiv,
    input  wire [4:0]  entry_pc,
    input  wire [4:0]  wrap_bottom,
    input  wire [4:0]  wrap_top,
    input  wire [4:0]  out_base,
    input  wire [4:0]  out_cnt,
    input  wire [4:0]  set_base,
    input  wire [2:0]  set_cnt,
    input  wire [4:0]  in_base,
    input  wire [4:0]  side_base,
    input  wire [1:0]  side_cnt,
    input  wire [4:0]  jmp_pin,
    input  wire        wide,
    input  wire [4:0]  pull_thresh,
    input  wire [4:0]  push_thresh,
    input  wire        out_shr,
    input  wire        in_shr,
    input  wire        autopull,
    input  wire        autopush,
    input  wire [15:0] timeout,
    input  wire [1:0]  to_presc,
    input  wire [15:0] instr,
    input  wire        instr_valid,
    input  wire [19:0] pin_in,
    input  wire [3:0]  lut_out,
    input  wire        arb_lost,
    input  wire        underrun,
    input  wire        tx_empty,
    input  wire        rx_full,
    input  wire [2:0]  tx_level,
    input  wire [2:0]  rx_level,
    input  wire [7:0]  tx_dout,
    output wire        tx_pop,
    output wire        rx_push,
    output wire [7:0]  rx_din,
    output wire [4:0]  rd_pc,
    output reg  [19:0] out_val,
    output reg  [19:0] oe_val,
    output reg  [3:0]  fab_ctrl,
    output reg         fab_wr,
    output reg  [7:2]  user_flags,
    output reg         evt_clr_arb,
    output reg         evt_clr_unf,
    output wire        engine_tick,
    output wire [4:0]  eng_pc,
    output reg         eng_done_req,
    output reg         eng_fault_req,
    output reg  [3:0]  eng_fault_code
);
    localparam [2:0] OP_JMP = 3'd0, OP_WAIT = 3'd1, OP_IN = 3'd2, OP_OUT = 3'd3,
                     OP_FIFO = 3'd4, OP_MOV = 3'd5, OP_EVT = 3'd6, OP_SET = 3'd7;
    localparam [3:0] FAULT_NONE = 4'd0, FAULT_TIMEOUT = 4'd2,
                     FAULT_ILLEGAL_OP = 4'd3, FAULT_INVALID_WORD = 4'd4;
    localparam [4:0] OSR_COUNT_RESET = 5'd16;

    reg [4:0] pc_q, delayed_pc_q, delay_q, osr_cnt_q, isr_cnt_q;
    reg [15:0] x_q, y_q, osr_q, isr_q, word_q, timeout_count_q;
    reg [7:0] wide_byte_q;
    reg word_valid_q;
    reg stopped_q, stalled_q, wide_pending_q, exec_pending_q;

    reg [4:0] pc_d, osr_cnt_d, isr_cnt_d;
    reg [15:0] x_d, y_d, osr_d, isr_d, exec_word_d;
    wire [19:0] out_d, oe_d;
    reg [3:0] fab_d;
    reg [7:2] flags_d;
    reg illegal, done, write_fab, clear_arb, clear_unf, launch_exec;
    reg waiting, transfer_more, fifo_pop, fifo_push, push_request;
    reg [7:0] next_wide_byte, fifo_rx_data;
    reg [15:0] mov_src, mov_data, in_data;
    wire [15:0] sampled_pins;
    genvar sample_index, pin;
    reg jump_taken;
    integer index;

    wire [15:0] word = word_q;
    wire [2:0] opcode = word[15:13];
    wire [7:0] flags = {user_flags, underrun, arb_lost};
    wire [4:0] instruction_delay;
    wire [4:0] default_threshold = wide ? 5'd16 : 5'd8;
    wire [4:0] pull_limit = pull_thresh != 5'd0 ? pull_thresh : default_threshold;
    wire [4:0] push_limit = push_thresh != 5'd0 ? push_thresh : default_threshold;
    wire osr_empty = osr_cnt_q >= pull_limit;
    wire isr_full = isr_cnt_q >= push_limit;
    wire [4:0] shift_count = word[4:0] == 5'd0 ? 5'd16 : word[4:0];
    wire [4:0] opposite_shift = 5'd16 - shift_count;
    wire [15:0] shift_mask = 16'hffff >> opposite_shift;
    wire tx_ready = wide ? tx_level >= 3'd2 : !tx_empty;
    wire rx_ready = wide ? rx_level <= 3'd2 : !rx_full;
    wire [15:0] pull_data = wide ? {tx_dout, wide_byte_q} :
                            out_shr ? {8'h00, tx_dout} : {tx_dout, 8'h00};
    wire refill = autopull && osr_empty;
    wire [15:0] out_source = refill ? pull_data : osr_q;
    wire [15:0] out_data = out_shr ? (out_source & shift_mask) : (out_source >> opposite_shift);
    wire [15:0] in_bits = in_data & shift_mask;
    wire [15:0] shifted_isr = in_shr ? ((isr_q >> shift_count) | (in_bits << opposite_shift)) :
                                     ((isr_q << shift_count) | in_bits);
    wire [5:0] in_count_sum = {1'b0, isr_cnt_q} + {1'b0, shift_count};
    wire [4:0] shifted_in_count = in_count_sum >= 6'd16 ? 5'd16 : in_count_sum[4:0];
    wire [5:0] out_count_sum = (refill ? 6'd0 : {1'b0, osr_cnt_q}) + {1'b0, shift_count};
    wire [15:0] push_data = opcode == OP_IN ? shifted_isr : isr_q;
    wire issue_cycle = engine_tick && delay_q == 5'd0;
    wire invalid_fetch = !exec_pending_q && !word_valid_q;
    wire issue_fault = invalid_fetch || illegal;
    wire timeout_tick;
    wire timeout_counts = timeout != 16'd0 && timeout_tick &&
                          (issue_cycle ? (!issue_fault && waiting) : stalled_q);
    wire timeout_due = timeout_counts && timeout_count_q == timeout - 16'd1;

    // Prefetch at issue completion, including at CLKDIV=1. The word waits
    // in the register while the current instruction's delay runs.
    assign rd_pc = !rst_n ? 5'd0 : enable_pulse ? entry_pc : pc_d;
    assign eng_pc = pc_q;
    assign tx_pop = issue_cycle && !issue_fault && fifo_pop;
    assign rx_push = issue_cycle && !issue_fault && fifo_push;
    assign rx_din = fifo_rx_data;
    assign instruction_delay = side_cnt == 2'd1 ? {1'b0, word[11:8]} :
                               side_cnt == 2'd2 ? {2'b00, word[10:8]} : word[12:8];

    pvm_tick tick_divider (
        .clk(clk), .rst_n(rst_n), .run(run && !stopped_q),
        .restart(enable_pulse), .div(clkdiv), .tick(engine_tick)
    );

    pvm_presc timeout_prescaler (
        .clk(clk), .rst_n(rst_n), .run(run && !stopped_q),
        .restart(enable_pulse), .sel(to_presc), .en(timeout_tick)
    );

    function [4:0] protocol_pin;
        input [4:0] base, offset;
        reg [5:0] sum;
        begin
            sum = {1'b0, base} + {1'b0, offset};
            if (sum >= 6'd20)
                sum = sum - 6'd20;
            protocol_pin = sum[4:0];
        end
    endfunction

    function [4:0] pin_offset;
        input [4:0] base, pin_number;
        reg [5:0] wrapped;
        begin
            wrapped = {1'b0, pin_number} + 6'd20 - {1'b0, base};
            if (wrapped >= 6'd20)
                wrapped = wrapped - 6'd20;
            pin_offset = wrapped[4:0];
        end
    endfunction

    wire out_writes_pins = opcode == OP_OUT && !illegal && !waiting && !transfer_more;
    wire mov_writes_pins = opcode == OP_MOV && !illegal && word[7:5] == 3'd0;
    wire set_writes_pins = opcode == OP_SET;
    wire first_issue = !stalled_q && !wide_pending_q;
    wire [15:0] pin_write_data = mov_writes_pins ? mov_data : out_data;
    wire [4:0] set_data = word[4:0];

    generate
        // VALIDATE checks the bases and the configuration stays fixed in RUN.
        // Compute the pin selectors at ENABLE instead of feeding dynamic
        // writes through a chain of position decoders on each issue tick.
        for (sample_index = 0; sample_index < 16; sample_index = sample_index + 1) begin : input_pins
            reg [4:0] source_pin;
            always @(posedge clk)
                if (!rst_n || enable_pulse)
                    source_pin <= protocol_pin(in_base, sample_index[4:0]);
            assign sampled_pins[sample_index] = pin_in[source_pin];
        end
        for (pin = 0; pin < 20; pin = pin + 1) begin : output_pins
            wire [4:0] out_offset = pin_offset(out_base, pin[4:0]);
            wire [4:0] set_offset = pin_offset(set_base, pin[4:0]);
            reg [3:0] out_lane;
            reg [2:0] set_lane;
            reg out_mapped, set_mapped, side_first, side_second;

            always @(posedge clk) begin
                if (!rst_n || enable_pulse) begin
                    out_lane <= out_offset[3:0];
                    set_lane <= set_offset[2:0];
                    out_mapped <= out_offset < out_cnt && out_offset < 5'd16;
                    set_mapped <= set_offset < {2'b00, set_cnt} && set_offset < 5'd5;
                    side_first <= side_base == pin[4:0];
                    side_second <= protocol_pin(side_base, 5'd1) == pin[4:0];
                end
            end

            wire out_active = out_mapped && out_writes_pins && {1'b0, out_lane} < shift_count;
            wire mov_active = out_mapped && mov_writes_pins;
            wire set_active = set_mapped && set_writes_pins;
            wire out_data_active = out_active && word[7:5] == 3'd0;
            wire out_direction_active = out_active && word[7:5] == 3'd4;
            wire set_data_active = set_active && word[7:5] == 3'd0;
            wire set_direction_active = set_active && word[7:5] == 3'd4;
            // Side-set overrides normal pin data, including on a stalled tick.
            wire side_high = first_issue &&
                             ((side_cnt == 2'd1 && side_first) || (side_cnt == 2'd2 && side_second));
            wire side_low = first_issue && side_cnt == 2'd2 && side_first;

            assign out_d[pin] = side_high ? word[12] :
                                side_low ? word[11] :
                                set_data_active ? set_data[set_lane] :
                                (out_data_active || mov_active) ? pin_write_data[out_lane] : out_val[pin];
            assign oe_d[pin] = set_direction_active ? set_data[set_lane] :
                               out_direction_active ? out_data[out_lane] : oe_val[pin];
        end
    endgenerate

    always @(*) begin
        case (word[7:5])
            3'd0: in_data = sampled_pins;
            3'd1: in_data = x_q;
            3'd2: in_data = y_q;
            3'd4: in_data = isr_q;
            3'd5: in_data = osr_q;
            3'd6: in_data = {12'd0, lut_out};
            default: in_data = 16'h0000;
        endcase
    end

    always @(*) begin
        index = 0;
        case (word[2:0])
            3'd0: mov_src = sampled_pins;
            3'd1: mov_src = x_q;
            3'd2: mov_src = y_q;
            3'd3: mov_src = 16'h0000;
            3'd4: mov_src = {13'd0, tx_empty, rx_full, osr_empty};
            3'd5: mov_src = isr_q;
            3'd6: mov_src = osr_q;
            3'd7: mov_src = {12'd0, lut_out};
            default: mov_src = 16'h0000;
        endcase
        case (word[4:3])
            2'd1: mov_data = ~mov_src;
            2'd2: begin
                for (index = 0; index < 16; index = index + 1)
                    mov_data[index] = mov_src[15-index];
            end
            default: mov_data = mov_src;
        endcase

        pc_d = pc_q == wrap_top ? wrap_bottom : pc_q + 5'd1;
        x_d = x_q;
        osr_d = osr_q;
        isr_d = isr_q;
        osr_cnt_d = osr_cnt_q;
        isr_cnt_d = isr_cnt_q;
        exec_word_d = 16'h0000;
        launch_exec = 1'b0;
        waiting = 1'b0;
        transfer_more = 1'b0;
        next_wide_byte = 8'h00;
        fifo_pop = 1'b0;
        fifo_push = 1'b0;
        fifo_rx_data = 8'h00;
        push_request = 1'b0;
        y_d = y_q;
        fab_d = fab_ctrl;
        flags_d = user_flags;
        illegal = 1'b0;
        done = 1'b0;
        write_fab = 1'b0;
        clear_arb = 1'b0;
        clear_unf = 1'b0;
        jump_taken = 1'b0;

        case (opcode)
            OP_JMP: begin
                case (word[7:5])
                    3'd0: jump_taken = 1'b1;
                    3'd1: jump_taken = x_q == 16'h0000;
                    3'd2: begin
                        jump_taken = x_q != 16'h0000;
                        x_d = x_q - 16'd1;
                    end
                    3'd3: jump_taken = y_q == 16'h0000;
                    3'd4: begin
                        jump_taken = y_q != 16'h0000;
                        y_d = y_q - 16'd1;
                    end
                    3'd5: jump_taken = x_q != y_q;
                    3'd6: jump_taken = pin_in[jmp_pin];
                    3'd7: jump_taken = !osr_empty;
                    default: illegal = 1'b1;
                endcase
                if (jump_taken)
                    pc_d = word[4:0];
            end
            OP_WAIT: begin
                case (word[6:5])
                    2'd0: begin
                        illegal = word[4:0] >= 5'd20;
                        waiting = !illegal && (pin_in[word[4:0]] != word[7]);
                    end
                    2'd1: begin
                        illegal = word[4:2] != 3'd0;
                        waiting = !illegal && (lut_out[word[1:0]] != word[7]);
                    end
                    2'd2: begin
                        illegal = word[4:3] != 2'd0;
                        waiting = !illegal && (flags[word[2:0]] != word[7]);
                    end
                    default: illegal = 1'b1;
                endcase
            end
            OP_IN: begin
                if (shift_count > 5'd16 || word[7:5] == 3'd7)
                    illegal = 1'b1;
                else if (wide_pending_q || (autopush && shifted_in_count >= push_limit))
                    push_request = 1'b1;
                else begin
                    isr_d = shifted_isr;
                    isr_cnt_d = shifted_in_count;
                end
            end
            OP_OUT: begin
                if (shift_count > 5'd16 ||
                    (word[7:5] == 3'd7 && (shift_count != 5'd16 || exec_pending_q)))
                    illegal = 1'b1;
                else if (refill && !wide_pending_q && !tx_ready)
                    waiting = 1'b1;
                else if (refill && wide && !wide_pending_q) begin
                    fifo_pop = 1'b1;
                    next_wide_byte = tx_dout;
                    transfer_more = 1'b1;
                end else begin
                    fifo_pop = refill;
                    osr_d = out_shr ? (out_source >> shift_count) : (out_source << shift_count);
                    osr_cnt_d = out_count_sum >= 6'd31 ? 5'd31 : out_count_sum[4:0];
                    case (word[7:5])
                        3'd0, 3'd4: begin end
                        3'd1: x_d = out_data;
                        3'd2: y_d = out_data;
                        3'd3: begin end
                        3'd5: pc_d = out_data[4:0];
                        3'd6: begin
                            fab_d = out_data[3:0];
                            write_fab = 1'b1;
                        end
                        3'd7: begin
                            launch_exec = 1'b1;
                            exec_word_d = out_data;
                        end
                        default: illegal = 1'b1;
                    endcase
                end
            end
            OP_FIFO: begin
                if (word[4:0] != 5'd0)
                    illegal = 1'b1;
                else if (word[7]) begin
                    if (wide_pending_q || !word[6] || osr_empty) begin
                        if (wide_pending_q || tx_ready) begin
                            fifo_pop = 1'b1;
                            if (wide && !wide_pending_q) begin
                                next_wide_byte = tx_dout;
                                transfer_more = 1'b1;
                            end else begin
                                osr_d = pull_data;
                                osr_cnt_d = 5'd0;
                            end
                        end else if (wide || word[5])
                            waiting = 1'b1;
                        else begin
                            osr_d = x_q;
                            osr_cnt_d = 5'd0;
                        end
                    end
                end else if (wide_pending_q || !word[6] || isr_full)
                    push_request = 1'b1;
            end
            OP_MOV: begin
                if (word[4:3] == 2'd3 || (word[7:5] == 3'd3 && exec_pending_q))
                    illegal = 1'b1;
                else begin
                    case (word[7:5])
                        3'd0: begin end
                        3'd1: x_d = mov_data;
                        3'd2: y_d = mov_data;
                        3'd3: begin
                            launch_exec = 1'b1;
                            exec_word_d = mov_data;
                        end
                        3'd4: pc_d = mov_data[4:0];
                        3'd5: begin
                            isr_d = mov_data;
                            isr_cnt_d = 5'd0;
                        end
                        3'd6: begin
                            osr_d = mov_data;
                            osr_cnt_d = 5'd0;
                        end
                        3'd7: begin
                            fab_d = mov_data[3:0];
                            write_fab = 1'b1;
                        end
                        default: illegal = 1'b1;
                    endcase
                end
            end
            OP_EVT: begin
                if (word[5:3] != 3'd0)
                    illegal = 1'b1;
                else begin
                    case (word[7:6])
                        2'd0: begin
                            if (word[2:0] < 3'd2)
                                illegal = 1'b1;
                            else
                                flags_d[word[2:0]] = 1'b1;
                        end
                        2'd1: begin
                            case (word[2:0])
                                3'd0: clear_arb = 1'b1;
                                3'd1: clear_unf = 1'b1;
                                default: flags_d[word[2:0]] = 1'b0;
                            endcase
                        end
                        2'd3: done = 1'b1;
                        default: illegal = 1'b1;
                    endcase
                end
            end
            OP_SET: begin
                case (word[7:5])
                    3'd0, 3'd4: begin end
                    3'd1: x_d = {11'd0, word[4:0]};
                    3'd2: y_d = {11'd0, word[4:0]};
                    3'd6: begin
                        fab_d = word[3:0];
                        write_fab = 1'b1;
                    end
                    default: illegal = 1'b1;
                endcase
            end
            default: illegal = 1'b1;
        endcase

        // Capacity is reserved before the first beat. Only the high byte is buffered.
        if (push_request) begin
            if (wide_pending_q || rx_ready) begin
                fifo_push = 1'b1;
                fifo_rx_data = wide_pending_q ? wide_byte_q : push_data[7:0];
                if (wide && !wide_pending_q) begin
                    next_wide_byte = push_data[15:8];
                    transfer_more = 1'b1;
                end else begin
                    isr_d = 16'h0000;
                    isr_cnt_d = 5'd0;
                end
            end else if (wide || opcode == OP_IN || word[5])
                waiting = 1'b1;
            else begin
                isr_d = 16'h0000;
                isr_cnt_d = 5'd0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n || enable_pulse) begin
            pc_q <= rst_n ? entry_pc : 5'd0;
            delayed_pc_q <= 5'd0;
            delay_q <= 5'd0;
            osr_cnt_q <= OSR_COUNT_RESET;
            isr_cnt_q <= 5'd0;
            osr_q <= 16'h0000;
            isr_q <= 16'h0000;
            x_q <= 16'h0000;
            y_q <= 16'h0000;
            word_q <= instr;
            word_valid_q <= instr_valid;
            exec_pending_q <= 1'b0;
            wide_byte_q <= 8'h00;
            wide_pending_q <= 1'b0;
            timeout_count_q <= 16'h0000;
            stalled_q <= 1'b0;
            out_val <= 20'd0;
            oe_val <= 20'd0;
            fab_ctrl <= 4'd0;
            fab_wr <= 1'b0;
            user_flags <= 6'd0;
            evt_clr_arb <= 1'b0;
            evt_clr_unf <= 1'b0;
            eng_done_req <= 1'b0;
            eng_fault_req <= 1'b0;
            eng_fault_code <= FAULT_NONE;
            stopped_q <= 1'b0;
        end else begin
            fab_wr <= 1'b0;
            evt_clr_arb <= 1'b0;
            evt_clr_unf <= 1'b0;
            eng_done_req <= 1'b0;
            eng_fault_req <= 1'b0;

            if (timeout_counts)
                timeout_count_q <= timeout_count_q + 16'd1;
            else if (issue_cycle && !waiting)
                timeout_count_q <= 16'h0000;

            if (timeout_due) begin
                if (issue_cycle)
                    out_val <= out_d;
                eng_fault_req <= 1'b1;
                eng_fault_code <= FAULT_TIMEOUT;
                stopped_q <= 1'b1;
            end else if (engine_tick && delay_q != 5'd0) begin
                delay_q <= delay_q - 5'd1;
                if (delay_q == 5'd1)
                    pc_q <= delayed_pc_q;
            end else if (issue_cycle) begin
                if (issue_fault) begin
                    eng_fault_req <= 1'b1;
                    eng_fault_code <= invalid_fetch ? FAULT_INVALID_WORD : FAULT_ILLEGAL_OP;
                    stopped_q <= 1'b1;
                end else begin
                    out_val <= out_d;
                    stalled_q <= waiting;
                    wide_pending_q <= transfer_more;
                    if (transfer_more)
                        wide_byte_q <= next_wide_byte;
                    if (!waiting && !transfer_more) begin
                        x_q <= x_d;
                        y_q <= y_d;
                        osr_q <= osr_d;
                        isr_q <= isr_d;
                        osr_cnt_q <= osr_cnt_d;
                        isr_cnt_q <= isr_cnt_d;
                        oe_val <= oe_d;
                        fab_ctrl <= fab_d;
                        fab_wr <= write_fab;
                        user_flags <= flags_d;
                        evt_clr_arb <= clear_arb;
                        evt_clr_unf <= clear_unf;
                        exec_pending_q <= launch_exec;
                        if (launch_exec)
                            word_q <= exec_word_d;
                        else begin
                            word_q <= instr;
                            word_valid_q <= instr_valid;
                        end

                        // The parent PC is held through both instructions and both delays.
                        if (done) begin
                            eng_done_req <= 1'b1;
                            stopped_q <= 1'b1;
                        end else if (instruction_delay == 5'd0) begin
                            if (!launch_exec)
                                pc_q <= pc_d;
                        end else begin
                            delay_q <= instruction_delay;
                            delayed_pc_q <= launch_exec ? pc_q : pc_d;
                        end
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
