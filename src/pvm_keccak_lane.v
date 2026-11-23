// Keccak-f[1600] over a single 25 x 64-bit working memory.
// Lane number is x + 5*y. Byte 0 is the least-significant byte of lane 0.
// This is a private sponge datapath. It does not parse or authenticate commands.
module pvm_keccak_lane (
    input wire clk,
    input wire rst_ni,
    input wire cmd_valid_i,
    output wire cmd_ready_o,
    input wire [1:0] cmd_i,
    input wire [4:0] lane_i,
    input wire [63:0] lane_data_i,
    output wire response_valid_o,
    output wire [63:0] lane_data_o,
    output reg done_o,
    output reg error_o
);
    localparam [1:0] CMD_CLEAR = 2'd0, CMD_XOR = 2'd1,
                     CMD_READ = 2'd2, CMD_PERMUTE = 2'd3;

    localparam [3:0] SCRUB = 4'd0, IDLE = 4'd1, XOR_WRITE = 4'd2,
                     RESPONSE = 4'd3, PARITY_READ = 4'd4, PARITY_ACC = 4'd5,
                     THETA_READ = 4'd6, THETA_WRITE = 4'd7,
                     RHO_SEED_READ = 4'd8, RHO_SEED_SAVE = 4'd9,
                     RHO_READ = 4'd10, RHO_WRITE = 4'd11,
                     CHI_READ = 4'd12, CHI_SAVE = 4'd13, CHI_WRITE = 4'd14;

    reg [3:0] phase;
    reg [4:0] lane, round, rho_step;
    reg [2:0] column;
    reg [63:0] xor_word;
    // A rotating bank serves as theta parities, rho's carried lane, or chi's row.
    reg [63:0] scratch0, scratch1, scratch2, scratch3, scratch4;
    reg [63:0] scratch_tail;
    reg shift_scratch;

    reg [4:0] read_address, write_address;
    reg [63:0] write_data;
    reg read_enable, write_enable;

    wire accept = cmd_valid_i && cmd_ready_o;
    wire valid_lane = lane_i < 5'd25;
    wire finish = phase == CHI_WRITE && lane == 5'd24 && round == 5'd23;
    assign cmd_ready_o = rst_ni && phase == IDLE;
    assign response_valid_o = rst_ni && phase == RESPONSE;
    assign lane_data_o = read_lane;

    // Each stage selects one constant rotation. The two mux inputs use the
    // same bits, so only one barrel shifter is needed.
    function [63:0] rotate_left;
        input [63:0] value;
        input [5:0] amount;
        reg [63:0] by1, by2, by4, by8, by16;
        begin
            by1 = amount[0] ? {value[62:0], value[63]} : value;
            by2 = amount[1] ? {by1[61:0], by1[63:62]} : by1;
            by4 = amount[2] ? {by2[59:0], by2[63:60]} : by2;
            by8 = amount[3] ? {by4[55:0], by4[63:56]} : by4;
            by16 = amount[4] ? {by8[47:0], by8[63:48]} : by8;
            rotate_left = amount[5] ? {by16[31:0], by16[63:32]} : by16;
        end
    endfunction

    // Rho/Pi walks all nonzero lanes, starting with the saved lane (1,0).
    // Each table row holds the destination and rotation for that saved lane.
    function [10:0] rho_operation;
        input [4:0] step;
        begin
            case (step)
                5'd0: rho_operation = {5'd10, 6'd1};
                5'd1: rho_operation = {5'd7, 6'd3};
                5'd2: rho_operation = {5'd11, 6'd6};
                5'd3: rho_operation = {5'd17, 6'd10};
                5'd4: rho_operation = {5'd18, 6'd15};
                5'd5: rho_operation = {5'd3, 6'd21};
                5'd6: rho_operation = {5'd5, 6'd28};
                5'd7: rho_operation = {5'd16, 6'd36};
                5'd8: rho_operation = {5'd8, 6'd45};
                5'd9: rho_operation = {5'd21, 6'd55};
                5'd10: rho_operation = {5'd24, 6'd2};
                5'd11: rho_operation = {5'd4, 6'd14};
                5'd12: rho_operation = {5'd15, 6'd27};
                5'd13: rho_operation = {5'd23, 6'd41};
                5'd14: rho_operation = {5'd19, 6'd56};
                5'd15: rho_operation = {5'd13, 6'd8};
                5'd16: rho_operation = {5'd12, 6'd25};
                5'd17: rho_operation = {5'd2, 6'd43};
                5'd18: rho_operation = {5'd20, 6'd62};
                5'd19: rho_operation = {5'd14, 6'd18};
                5'd20: rho_operation = {5'd22, 6'd39};
                5'd21: rho_operation = {5'd9, 6'd61};
                5'd22: rho_operation = {5'd6, 6'd20};
                5'd23: rho_operation = {5'd1, 6'd44};
                default: rho_operation = 11'd0;
            endcase
        end
    endfunction

    function [63:0] round_constant;
        input [4:0] index;
        begin
            case (index)
                5'd0:  round_constant = 64'h0000000000000001;
                5'd1:  round_constant = 64'h0000000000008082;
                5'd2:  round_constant = 64'h800000000000808A;
                5'd3:  round_constant = 64'h8000000080008000;
                5'd4:  round_constant = 64'h000000000000808B;
                5'd5:  round_constant = 64'h0000000080000001;
                5'd6:  round_constant = 64'h8000000080008081;
                5'd7:  round_constant = 64'h8000000000008009;
                5'd8:  round_constant = 64'h000000000000008A;
                5'd9:  round_constant = 64'h0000000000000088;
                5'd10: round_constant = 64'h0000000080008009;
                5'd11: round_constant = 64'h000000008000000A;
                5'd12: round_constant = 64'h000000008000808B;
                5'd13: round_constant = 64'h800000000000008B;
                5'd14: round_constant = 64'h8000000000008089;
                5'd15: round_constant = 64'h8000000000008003;
                5'd16: round_constant = 64'h8000000000008002;
                5'd17: round_constant = 64'h8000000000000080;
                5'd18: round_constant = 64'h000000000000800A;
                5'd19: round_constant = 64'h800000008000000A;
                5'd20: round_constant = 64'h8000000080008081;
                5'd21: round_constant = 64'h8000000000008080;
                5'd22: round_constant = 64'h0000000080000001;
                5'd23: round_constant = 64'h8000000080008008;
                default: round_constant = 64'd0;
            endcase
        end
    endfunction

    wire [10:0] rho = rho_operation(rho_step);
    wire [63:0] theta_delta = scratch4 ^ {scratch1[62:0], scratch1[63]};
    wire [63:0] chi_lane = scratch0 ^ ((~scratch1) & scratch2);
    wire [63:0] iota = lane == 0 ? round_constant(round) : 64'd0;

    // There is at most one working-memory access per clock.
`ifdef PVM_KECCAK_IHP_SRAM
    wire [63:0] memory_output;
    reg memory_output_valid;
    wire [63:0] read_lane = memory_output_valid ? memory_output : 64'd0;
    // Flush the macro's latched read port with the last zero write.
    wire clear_memory_output = phase == SCRUB && lane == 5'd24;
    RM_IHPSG13_1P_64x64_c2_bm_bist working_memory (
        .A_CLK(clk), .A_MEN(rst_ni && (read_enable || write_enable)),
        .A_WEN(write_enable), .A_REN(read_enable || clear_memory_output),
        .A_ADDR({1'b0, write_enable ? write_address : read_address}),
        .A_DIN(write_data), .A_DLY(1'b1), .A_DOUT(memory_output), .A_BM({64{1'b1}}),
        .A_BIST_CLK(1'b0), .A_BIST_EN(1'b0), .A_BIST_MEN(1'b0),
        .A_BIST_WEN(1'b0), .A_BIST_REN(1'b0), .A_BIST_ADDR(6'd0),
        .A_BIST_DIN(64'd0), .A_BIST_BM(64'd0)
    );
    always @(posedge clk) begin
        if (!rst_ni || phase == SCRUB || finish)
            memory_output_valid <= 1'b0;
        else if (read_enable)
            memory_output_valid <= 1'b1;
    end
`else
    // A scrub writes the 25 used lanes, allowing inference without a RAM reset.
    reg [63:0] lanes [0:24];
    reg [63:0] read_lane;
    always @(posedge clk) begin
        if (rst_ni && write_enable)
            lanes[write_address] <= write_data;
        if (!rst_ni || phase == SCRUB || finish)
            read_lane <= 64'd0;
        else if (read_enable)
            read_lane <= lanes[read_address];
    end
`endif

    always @* begin
        read_address = lane;
        write_address = lane;
        write_data = 64'd0;
        read_enable = 1'b0;
        write_enable = 1'b0;
        scratch_tail = scratch0;
        shift_scratch = 1'b0;

        case (phase)
            SCRUB: write_enable = 1'b1;
            IDLE: begin
                read_enable = accept && valid_lane && (cmd_i == CMD_XOR || cmd_i == CMD_READ);
                read_address = lane_i;
            end
            XOR_WRITE: begin
                write_enable = 1'b1;
                write_data = read_lane ^ xor_word;
            end
            PARITY_READ, THETA_READ, CHI_READ: read_enable = 1'b1;
            PARITY_ACC: begin
                // First row initializes all five parities.
                shift_scratch = 1'b1;
                scratch_tail = lane < 5 ? read_lane : scratch0 ^ read_lane;
            end
            THETA_WRITE: begin
                shift_scratch = 1'b1;
                write_enable = 1'b1;
                write_data = read_lane ^ theta_delta;
            end
            RHO_SEED_READ: begin
                read_enable = 1'b1;
                read_address = 5'd1;
            end
            RHO_READ: begin
                read_enable = 1'b1;
                read_address = rho[10:6];
            end
            RHO_WRITE: begin
                write_enable = 1'b1;
                write_address = rho[10:6];
                write_data = rotate_left(scratch0, rho[5:0]);
            end
            CHI_SAVE: begin
                shift_scratch = 1'b1;
                scratch_tail = read_lane;
            end
            CHI_WRITE: begin
                shift_scratch = 1'b1;
                write_enable = 1'b1;
                write_data = chi_lane ^ iota;
            end
            default: begin end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_ni || phase == SCRUB || finish) begin
            scratch0 <= 64'd0;
            scratch1 <= 64'd0;
            scratch2 <= 64'd0;
            scratch3 <= 64'd0;
            scratch4 <= 64'd0;
        end else if (shift_scratch) begin
            scratch0 <= scratch1;
            scratch1 <= scratch2;
            scratch2 <= scratch3;
            scratch3 <= scratch4;
            scratch4 <= scratch_tail;
        end else if (phase == RHO_SEED_SAVE || phase == RHO_WRITE) begin
            scratch0 <= read_lane;
        end
    end

    always @(posedge clk) begin
        if (!rst_ni) begin
            phase <= SCRUB;
            lane <= 5'd0;
            round <= 5'd0;
            rho_step <= 5'd0;
            column <= 3'd0;
            xor_word <= 64'd0;
            done_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            error_o <= 1'b0;
            case (phase)
                SCRUB: begin
                    lane <= lane + 5'd1;
                    if (lane == 5'd24)
                        phase <= IDLE;
                end
                IDLE: if (accept) begin
                    case (cmd_i)
                        CMD_CLEAR: begin
                            lane <= 5'd0;
                            phase <= SCRUB;
                        end
                        CMD_XOR: if (valid_lane) begin
                            lane <= lane_i;
                            xor_word <= lane_data_i;
                            phase <= XOR_WRITE;
                        end else
                            error_o <= 1'b1;
                        CMD_READ: if (valid_lane)
                            phase <= RESPONSE;
                        else
                            error_o <= 1'b1;
                        CMD_PERMUTE: begin
                            lane <= 5'd0;
                            round <= 5'd0;
                            phase <= PARITY_READ;
                        end
                    endcase
                end
                XOR_WRITE: begin
                    xor_word <= 64'd0;
                    phase <= IDLE;
                end
                RESPONSE: phase <= IDLE;
                PARITY_READ: phase <= PARITY_ACC;
                PARITY_ACC: begin
                    if (lane == 5'd24) begin
                        lane <= 5'd0;
                        phase <= THETA_READ;
                    end else begin
                        lane <= lane + 5'd1;
                        phase <= PARITY_READ;
                    end
                end
                THETA_READ: phase <= THETA_WRITE;
                THETA_WRITE: begin
                    if (lane == 5'd24)
                        phase <= RHO_SEED_READ;
                    else begin
                        lane <= lane + 5'd1;
                        phase <= THETA_READ;
                    end
                end
                RHO_SEED_READ: phase <= RHO_SEED_SAVE;
                RHO_SEED_SAVE: begin
                    rho_step <= 5'd0;
                    phase <= RHO_READ;
                end
                RHO_READ: phase <= RHO_WRITE;
                RHO_WRITE: begin
                    if (rho_step == 5'd23) begin
                        lane <= 5'd0;
                        column <= 3'd0;
                        phase <= CHI_READ;
                    end else begin
                        rho_step <= rho_step + 5'd1;
                        phase <= RHO_READ;
                    end
                end
                CHI_READ: phase <= CHI_SAVE;
                CHI_SAVE: begin
                    if (column == 3'd4) begin
                        lane <= lane - 5'd4;
                        column <= 3'd0;
                        phase <= CHI_WRITE;
                    end else begin
                        lane <= lane + 5'd1;
                        column <= column + 3'd1;
                        phase <= CHI_READ;
                    end
                end
                CHI_WRITE: begin
                    lane <= lane + 5'd1;
                    if (column == 3'd4) begin
                        column <= 3'd0;
                        if (lane != 5'd24)
                            phase <= CHI_READ;
                        else if (finish) begin
                            done_o <= 1'b1;
                            phase <= IDLE;
                        end else begin
                            lane <= 5'd0;
                            round <= round + 5'd1;
                            phase <= PARITY_READ;
                        end
                    end else
                        column <= column + 3'd1;
                end
                default: begin
                    lane <= 5'd0;
                    xor_word <= 64'd0;
                    phase <= SCRUB;
                end
            endcase
        end
    end
endmodule
