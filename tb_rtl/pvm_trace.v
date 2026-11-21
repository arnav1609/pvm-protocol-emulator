`timescale 1ns/1ps
`default_nettype none

// Sample at the rising edge, before the engine commits its next state.
module pvm_trace (
    input wire clk,
    input wire [2:0] run_state,
    input wire [4:0] pc,
    input wire instr_valid,
    input wire [19:0] out_val,
    input wire [19:0] oe_val,
    input wire [3:0] fab_ctrl,
    input wire fab_wr,
    input wire tx_pop,
    input wire rx_push,
    input wire [7:0] rx_din,
    input wire fault_req,
    input wire [3:0] fault_code
);
    integer fd = 0;
    integer cycle = 0;

    initial begin
        if ($test$plusargs("TRACE")) begin
            fd = $fopen("trace.csv", "w");
            if (fd == 0) begin
                $display("TRACE_IO_ERROR");
                $finish;
            end
            $fdisplay(fd, "cycle,run_state,pc,instr_valid,out_val,oe_val,fab_ctrl,fab_wr,tx_pop,rx_push,rx_din,fault_req,fault_code");
        end
    end

    always @(posedge clk) begin
        if (fd != 0) begin
            $fdisplay(fd, "%0d,%0d,%0d,%b,%h,%h,%h,%b,%b,%b,%h,%b,%h",
                      cycle, run_state, pc, instr_valid, out_val, oe_val, fab_ctrl, fab_wr,
                      tx_pop, rx_push, rx_push ? rx_din : 8'd0, fault_req, fault_code);
            cycle = cycle + 1;
        end
    end
endmodule

`default_nettype wire
