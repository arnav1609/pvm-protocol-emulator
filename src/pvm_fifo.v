`timescale 1ns/1ps
`default_nettype none

// Synchronous FIFO with a non-destructive combinational head.
// Owner: Kalash Bheda. PVM S02. See STAGE_02 and 03_BUS_AND_REGMAP.md section 3.6.
module pvm_fifo #(
    parameter integer DW = 8,
    parameter integer DEPTH = 4
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          clr,
    input  wire                          push,
    input  wire [DW-1:0]                 din,
    input  wire                          pop,
    output wire [DW-1:0]                 dout,
    output wire                          full,
    output wire                          empty,
    output reg  [$clog2(DEPTH+1)-1:0]     level,
    output reg                           ovf,
    output reg                           unf
);
    localparam integer INDEX_W = DEPTH > 1 ? $clog2(DEPTH) : 1;
    localparam integer LEVEL_W = $clog2(DEPTH+1);
    localparam [INDEX_W-1:0] LAST_INDEX = DEPTH[INDEX_W-1:0] - 1'b1;

    // Equal index and phase means empty. Equal index with opposite phase means full.
    reg [INDEX_W:0] wr_ptr_q, rd_ptr_q;
    wire [INDEX_W-1:0] wr_index, rd_index;
    wire push_ok, pop_ok;
    // Storage is unreset. Reset pointers and the empty guard hide stale data.
    reg [DW-1:0] mem [0:DEPTH-1];

    assign wr_index = wr_ptr_q[INDEX_W-1:0];
    assign rd_index = rd_ptr_q[INDEX_W-1:0];
    assign empty = wr_ptr_q == rd_ptr_q;
    assign full = wr_ptr_q == {~rd_ptr_q[INDEX_W], rd_index};
    assign dout = empty ? {DW{1'b0}} : mem[rd_index];
    assign pop_ok = pop && !empty;
    assign push_ok = push && (!full || pop_ok);

    function [INDEX_W:0] advance;
        input [INDEX_W:0] ptr;
        begin
            if (ptr[INDEX_W-1:0] == LAST_INDEX)
                advance = {~ptr[INDEX_W], {INDEX_W{1'b0}}};
            else
                advance = ptr + 1'b1;
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n || clr) begin
            wr_ptr_q <= {(INDEX_W+1){1'b0}};
            rd_ptr_q <= {(INDEX_W+1){1'b0}};
            level <= {LEVEL_W{1'b0}};
            ovf <= 1'b0;
            unf <= 1'b0;
        end else begin
            ovf <= push && !push_ok;
            unf <= pop && !pop_ok;
            if (push_ok) begin
                mem[wr_index] <= din;
                wr_ptr_q <= advance(wr_ptr_q);
            end
            if (pop_ok)
                rd_ptr_q <= advance(rd_ptr_q);

            case ({push_ok, pop_ok})
                2'b10: level <= level + 1'b1;
                2'b01: level <= level - 1'b1;
                default: begin end
            endcase
        end
    end
endmodule

`default_nettype wire
