`timescale 1ns/1ps
`default_nettype none

// Store 32 instructions and publish each word on its high-byte write.
// Owner: Kalash Bheda. PVM S03. See 03_BUS_AND_REGMAP.md section 3.1.
module pvm_imem (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr_en,
    input  wire [5:0]  wr_addr,
    input  wire [7:0]  wr_data,
    input  wire        clr_valid,
    input  wire [4:0]  rd_pc,
    input  wire [4:0]  entry_pc,
    input  wire [5:0]  bus_rd_addr,
    output wire [15:0] instr,
    output wire        instr_valid,
    output wire        entry_valid,
    output wire [7:0]  bus_rd_data
);
    // A reset or clear invalidates storage without resetting its data.
    reg [15:0] words [0:31];
    reg [31:0] valid_q;
    wire [4:0] write_word, bus_word;
    wire [7:0] bus_byte;

    assign write_word = wr_addr[5:1];
    assign bus_word = bus_rd_addr[5:1];
    assign instr = words[rd_pc];
    assign instr_valid = valid_q[rd_pc];
    assign entry_valid = valid_q[entry_pc];
    assign bus_byte = bus_rd_addr[0] ? words[bus_word][15:8] : words[bus_word][7:0];
    assign bus_rd_data = valid_q[bus_word] ? bus_byte : 8'h00;

    always @(posedge clk) begin
        if (!rst_n || clr_valid)
            valid_q <= 32'h00000000;
        else if (wr_en) begin
            if (wr_addr[0]) begin
                words[write_word][15:8] <= wr_data;
                valid_q[write_word] <= 1'b1;
            end else
                words[write_word][7:0] <= wr_data;
        end
    end
endmodule

`default_nettype wire
