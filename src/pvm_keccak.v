`timescale 1ns/1ps
`default_nettype none

// Pack eight sponge bytes per lane operation. All rate blocks contain 136 bytes.
// Squeeze the first four lanes into a digest after each permutation so the
// existing fixed-time consumer can index its result without an extra handshake.
module pvm_keccak (
    input wire clk, rst_n, clear, permute, squeeze, absorb,
    input wire [7:0] absorb_index, absorb_byte, read_index,
    output wire [7:0] read_byte,
    output wire busy, absorb_ready,
    output reg done
);
    localparam FEED=0, WAIT_PERM=1, READ_LANE=2, WAIT_LANE=3;
    reg [1:0] phase;
    reg [1:0] result_lane;
    reg squeeze_q;
    reg [55:0] staging;
    reg [255:0] digest;
    wire lane_ready, lane_done, response;
    wire [63:0] lane_data;
    wire send_byte = absorb && absorb_ready && absorb_index[2:0]==7;
    wire start_permutation = phase==FEED && lane_ready && permute;
    wire issue_read = phase==READ_LANE && lane_ready;
    wire issue_clear = phase==FEED && lane_ready && clear;
    assign absorb_ready = phase==FEED && lane_ready;
    assign busy = !absorb_ready;
    assign read_byte = read_index < 32 ? digest[8*read_index[4:0]+:8] : 8'd0;

    pvm_keccak_lane lane_core (
        .clk(clk), .rst_ni(rst_n),
        .cmd_valid_i(issue_clear || start_permutation || issue_read || send_byte),
        .cmd_ready_o(lane_ready),
        .cmd_i(issue_clear ? 2'd0 : start_permutation ? 2'd3 : issue_read ? 2'd2 : 2'd1),
        .lane_i(issue_read ? {3'b0,result_lane} : absorb_index[7:3]),
        .lane_data_i({absorb_byte,staging}), .response_valid_o(response),
        .lane_data_o(lane_data), .done_o(lane_done), .error_o()
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            phase<=FEED;
            result_lane<=0;
            staging<=0;
            squeeze_q<=0;
            digest<=0;
            done<=0;
        end else begin
            done<=0;
            case (phase)
                FEED: begin
                    if (issue_clear) begin
                        digest<=0;
                        staging<=0;
                    end else if (start_permutation) begin
                        squeeze_q<=squeeze;
                        phase<=WAIT_PERM;
                    end
                    else if (absorb && absorb_ready && absorb_index[2:0]!=7)
                        staging[8*absorb_index[2:0]+:8]<=absorb_byte;
                end
                WAIT_PERM: if (lane_done) begin
                    if (squeeze_q) begin result_lane<=0; phase<=READ_LANE; end
                    else begin done<=1; phase<=FEED; end
                end
                READ_LANE: if (issue_read) phase<=WAIT_LANE;
                WAIT_LANE: if (response) begin
                    digest[64*result_lane+:64]<=lane_data;
                    result_lane<=result_lane+1'b1;
                    if (result_lane==3) begin done<=1; phase<=FEED; end
                    else phase<=READ_LANE;
                end
                default: phase<=FEED;
            endcase
        end
    end
endmodule
`default_nettype wire
