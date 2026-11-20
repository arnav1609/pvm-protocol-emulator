`timescale 1ns/1ps
`default_nettype none

// 8 frozen instruction-memory checks, frozen 2026-11-20 before registration. Stage S03.
module tb_imem;
    localparam integer N_CHECKS = 8;
    reg clk = 1'b0, rst_n = 1'b0, wr_en = 1'b0, clr_valid = 1'b0;
    reg [5:0] wr_addr = 6'd0, bus_rd_addr = 6'd0;
    reg [7:0] wr_data = 8'h00;
    reg [4:0] rd_pc = 5'd0;
    wire [15:0] instr;
    wire instr_valid;
    wire [7:0] bus_rd_data;
    integer checks = 0, errors = 0;
    integer i;
    reg ok;

    always #10 clk = ~clk;
    pvm_imem dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .clr_valid(clr_valid), .rd_pc(rd_pc), .bus_rd_addr(bus_rd_addr),
        .instr(instr), .instr_valid(instr_valid), .bus_rd_data(bus_rd_data)
    );

    task write_byte(input [5:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            wr_en = 1'b1;
            wr_addr = addr;
            wr_data = data;
            @(posedge clk);
            #1;
        end
    endtask

    task select_read(input [4:0] pc, input which_byte);
        begin
            @(negedge clk);
            wr_en = 1'b0;
            rd_pc = pc;
            bus_rd_addr = {pc, which_byte};
            #1;
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

    initial begin
        $display("CONFIG: TOP=tb_imem CHECKS=%0d", N_CHECKS);
        if ($test$plusargs("WAVES")) begin
            $dumpfile("tb_imem.vcd");
            $dumpvars(0, tb_imem);
        end
        @(posedge clk);
        #1;
        ok = 1'b1;
        for (i = 0; i < 32; i = i + 1) begin
            select_read(i[4:0], 1'b0);
            ok = ok && (instr_valid === 1'b0);
        end
        check("RESET_INVALID", ok);
        @(negedge clk);
        rst_n = 1'b1;

        select_read(5'd0, 1'b0);
        write_byte(6'd0, 8'h01);
        check("LOWBYTE_NOT_VALID", instr_valid === 1'b0);
        check("BUS_READ_MASK", bus_rd_data === 8'h00);
        write_byte(6'd1, 8'h67);
        ok = (instr_valid === 1'b1) && (instr === 16'h6701) && (bus_rd_data === 8'h01);
        select_read(5'd0, 1'b1);
        check("HIGHBYTE_SETS_VALID", ok && (bus_rd_data === 8'h67));

        for (i = 0; i < 32; i = i + 1) begin
            write_byte({i[4:0], 1'b0}, 8'h20 + i[7:0]);
            write_byte({i[4:0], 1'b1}, 8'h80 + i[7:0]);
        end
        ok = 1'b1;
        for (i = 0; i < 32; i = i + 1) begin
            select_read(i[4:0], 1'b0);
            ok = ok && (instr_valid === 1'b1) &&
                 (instr === {(8'h80 + i[7:0]), (8'h20 + i[7:0])}) &&
                 (bus_rd_data === (8'h20 + i[7:0]));
            select_read(i[4:0], 1'b1);
            ok = ok && (bus_rd_data === (8'h80 + i[7:0]));
        end
        check("ALL32_PATTERN", ok);
        check("BOUNDARY_WORD31", (instr === 16'h9f3f) && (bus_rd_data === 8'h9f));

        select_read(5'd9, 1'b0);
        write_byte(6'd18, 8'h77);
        ok = (instr_valid === 1'b1) && (instr === 16'h8977);
        write_byte(6'd19, 8'h56);
        select_read(5'd9, 1'b1);
        check("REWRITE_SAME_WORD", ok && (instr === 16'h5677) && (bus_rd_data === 8'h56));

        @(negedge clk);
        clr_valid = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        clr_valid = 1'b0;
        ok = 1'b1;
        for (i = 0; i < 32; i = i + 1) begin
            select_read(i[4:0], 1'b1);
            ok = ok && (instr_valid === 1'b0) && (bus_rd_data === 8'h00);
        end
        check("CLR_VALID", ok);

        $display("CHECKS : %0d", checks);
        $display("ERRORS : %0d", errors);
        $display("RESULT : %0s", (errors == 0 && checks == N_CHECKS) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #20000;
        $display("TB_TIMEOUT imem");
        $display("RESULT : FAIL");
        $finish;
    end
endmodule

`default_nettype wire
