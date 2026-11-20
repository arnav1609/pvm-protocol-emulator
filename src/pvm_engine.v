`timescale 1ns/1ps
`default_nettype none

// Execute PVM control-flow and register instructions on synchronous engine ticks.
// Owner: Kalash Bheda. PVM S09. See 04_ISA.md sections 2–5 and D-013.
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
    input  wire [15:0] instr,
    input  wire        instr_valid,
    input  wire [19:0] pin_in,
    input  wire [3:0]  lut_out,
    input  wire        arb_lost,
    input  wire        underrun,
    input  wire        tx_empty,
    input  wire        rx_full,
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
    localparam [2:0] OP_JMP = 3'b000, OP_MOV = 3'b101, OP_EVT = 3'b110, OP_SET = 3'b111;
    localparam [3:0] FAULT_NONE = 4'd0, FAULT_ILLEGAL_OP = 4'd3, FAULT_INVALID_WORD = 4'd4;
    localparam [4:0] OSR_COUNT_RESET = 5'd16;

    reg [4:0] pc_q, delayed_pc_q, delay_q, osr_cnt_q;
    reg [15:0] x_q, y_q;
    reg stopped_q;
    reg [4:0] pc_d;
    reg [15:0] x_d, y_d;
    reg [19:0] out_d, oe_d;
    reg [3:0] fab_d;
    reg [7:2] flags_d;
    reg illegal, done, write_fab, clear_arb, clear_unf;
    reg [15:0] mov_src, mov_data, sampled_pins;
    reg jump_taken;
    reg [4:0] pin_index;
    integer index;

    wire [4:0] instruction_delay;
    wire [4:0] second_side_pin = protocol_pin(side_base, 5'd1);
    wire [4:0] pull_limit = pull_thresh != 5'd0 ? pull_thresh : (wide ? 5'd16 : 5'd8);
    wire osr_empty = osr_cnt_q >= pull_limit;
    // These fabric flags are consumed in S11 by WAIT FLAG.
    wire [1:0] unused_fabric_flags = {arb_lost, underrun};

    assign rd_pc = pc_q;
    assign eng_pc = pc_q;
    assign instruction_delay = side_cnt == 2'd1 ? {1'b0, instr[11:8]} :
                               side_cnt == 2'd2 ? {2'b00, instr[10:8]} : instr[12:8];

    pvm_tick tick_divider (
        .clk(clk), .rst_n(rst_n), .run(run && !stopped_q),
        .restart(enable_pulse), .div(clkdiv), .tick(engine_tick)
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

    always @(*) begin
        for (index = 0; index < 16; index = index + 1) begin
            pin_index = protocol_pin(in_base, index[4:0]);
            sampled_pins[index] = pin_in[pin_index];
        end

        case (instr[2:0])
            3'd0: mov_src = sampled_pins;
            3'd1: mov_src = x_q;
            3'd2: mov_src = y_q;
            3'd3: mov_src = 16'h0000;
            3'd4: mov_src = {13'd0, tx_empty, rx_full, osr_empty};
            3'd7: mov_src = {12'd0, lut_out};
            default: mov_src = 16'h0000;
        endcase
        case (instr[4:3])
            2'd1: mov_data = ~mov_src;
            2'd2: begin
                for (index = 0; index < 16; index = index + 1)
                    mov_data[index] = mov_src[15-index];
            end
            default: mov_data = mov_src;
        endcase

        pc_d = pc_q == wrap_top ? wrap_bottom : pc_q + 5'd1;
        x_d = x_q;
        y_d = y_q;
        out_d = out_val;
        oe_d = oe_val;
        fab_d = fab_ctrl;
        flags_d = user_flags;
        illegal = 1'b0;
        done = 1'b0;
        write_fab = 1'b0;
        clear_arb = 1'b0;
        clear_unf = 1'b0;
        jump_taken = 1'b0;

        case (instr[15:13])
            OP_JMP: begin
                case (instr[7:5])
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
                    pc_d = instr[4:0];
            end
            OP_MOV: begin
                if (instr[4:3] == 2'd3 || instr[2:0] == 3'd5 || instr[2:0] == 3'd6)
                    illegal = 1'b1;
                else begin
                    case (instr[7:5])
                        3'd0: begin
                            for (index = 0; index < 16; index = index + 1) begin
                                pin_index = protocol_pin(out_base, index[4:0]);
                                if (index[4:0] < out_cnt)
                                    out_d[pin_index] = mov_data[index];
                            end
                        end
                        3'd1: x_d = mov_data;
                        3'd2: y_d = mov_data;
                        3'd4: pc_d = mov_data[4:0];
                        3'd7: begin
                            fab_d = mov_data[3:0];
                            write_fab = 1'b1;
                        end
                        default: illegal = 1'b1;
                    endcase
                end
            end
            OP_EVT: begin
                if (instr[5:3] != 3'd0)
                    illegal = 1'b1;
                else begin
                    case (instr[7:6])
                        2'd0: begin
                            if (instr[2:0] < 3'd2)
                                illegal = 1'b1;
                            else
                                flags_d[instr[2:0]] = 1'b1;
                        end
                        2'd1: begin
                            case (instr[2:0])
                                3'd0: clear_arb = 1'b1;
                                3'd1: clear_unf = 1'b1;
                                default: flags_d[instr[2:0]] = 1'b0;
                            endcase
                        end
                        2'd3: done = 1'b1;
                        default: illegal = 1'b1;
                    endcase
                end
            end
            OP_SET: begin
                case (instr[7:5])
                    3'd0, 3'd4: begin
                        for (index = 0; index < 5; index = index + 1) begin
                            pin_index = protocol_pin(set_base, index[4:0]);
                            if (index[2:0] < set_cnt) begin
                                if (instr[7:5] == 3'd0)
                                    out_d[pin_index] = instr[index];
                                else
                                    oe_d[pin_index] = instr[index];
                            end
                        end
                    end
                    3'd1: x_d = {11'd0, instr[4:0]};
                    3'd2: y_d = {11'd0, instr[4:0]};
                    3'd6: begin
                        fab_d = instr[3:0];
                        write_fab = 1'b1;
                    end
                    default: illegal = 1'b1;
                endcase
            end
            default: illegal = 1'b1;
        endcase

        // Side-set is applied after the decoded PINS write so it has priority.
        if (side_cnt == 2'd1)
            out_d[side_base] = instr[12];
        else if (side_cnt == 2'd2) begin
            out_d[side_base] = instr[11];
            out_d[second_side_pin] = instr[12];
        end
    end

    always @(posedge clk) begin
        if (!rst_n || enable_pulse) begin
            pc_q <= rst_n ? entry_pc : 5'd0;
            delayed_pc_q <= 5'd0;
            delay_q <= 5'd0;
            osr_cnt_q <= OSR_COUNT_RESET;
            x_q <= 16'h0000;
            y_q <= 16'h0000;
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
            if (engine_tick) begin
                if (delay_q != 5'd0) begin
                    delay_q <= delay_q - 5'd1;
                    if (delay_q == 5'd1)
                        pc_q <= delayed_pc_q;
                end else if (!instr_valid || illegal) begin
                    eng_fault_req <= 1'b1;
                    eng_fault_code <= instr_valid ? FAULT_ILLEGAL_OP : FAULT_INVALID_WORD;
                    stopped_q <= 1'b1;
                end else begin
                    x_q <= x_d;
                    y_q <= y_d;
                    out_val <= out_d;
                    oe_val <= oe_d;
                    fab_ctrl <= fab_d;
                    fab_wr <= write_fab;
                    user_flags <= flags_d;
                    evt_clr_arb <= clear_arb;
                    evt_clr_unf <= clear_unf;

                    if (done) begin
                        eng_done_req <= 1'b1;
                        stopped_q <= 1'b1;
                    end else if (instruction_delay == 5'd0)
                        pc_q <= pc_d;
                    else begin
                        delay_q <= instruction_delay;
                        delayed_pc_q <= pc_d;
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
