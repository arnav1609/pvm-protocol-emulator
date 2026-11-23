`timescale 1ns/1ps
`default_nettype none

// Authorizes each authenticated command before the separate PVM bus sequencer.
// req is a one-cycle strobe after fixed-time MAC and complete command checks.
// The sequencer must keep accepting requests disabled until complete is pulsed.
module pvm_auth_policy (
    input wire clk, rst_n, trust_valid,
    input wire req, mac_ok, context_ok, grammar_ok,
    input wire [7:0] identity, op,
    input wire [31:0] sequence_number,
    input wire pvm_stopped, pvm_ready, pvm_running, pvm_terminal,
    input wire complete, effect_success, fresh_challenge,
    output wire issue,
    output reg pending, retire,
    output reg [7:0] owner,
    output reg [2:0] phase,
    output reg [31:0] next_seq, last_committed
);
    localparam LOCKED=0, LOAD=1, READY=2, OWNED_RUN=3, RELOAD=4;
    localparam OPEN=1, CHUNK=2, FINISH=3, START=4, CANCEL=5,
               TX_PUSH=6, RX_POP=7, CLEAR_FLAGS=8;
    reg [7:0] issued_op, issued_identity;
    reg challenge_live, permitted;
    assign issue = rst_n && trust_valid && challenge_live && !pending && req &&
                   mac_ok && context_ok && grammar_ok && permitted &&
                   identity>=1 && identity<=11 &&
                   sequence_number==next_seq && next_seq!=32'hffffffff;
    always @* begin
        permitted = 0;
        if (op==OPEN)
            permitted = phase==LOCKED && owner==0 && pvm_stopped && next_seq==0;
        else if (owner!=0 && (identity==owner || (op==CANCEL && identity==11))) begin
            case (op)
                CHUNK, FINISH: permitted=phase==LOAD && pvm_stopped;
                START: permitted=phase==READY && pvm_ready;
                CANCEL: permitted=1;
                TX_PUSH: permitted=phase==OWNED_RUN && pvm_running;
                RX_POP, CLEAR_FLAGS: permitted=phase==OWNED_RUN && (pvm_running || pvm_terminal);
                default: ;
            endcase
        end
    end
    always @(posedge clk) begin
        if (!rst_n || !trust_valid) begin
            owner<=0;
            phase<=LOCKED;
            next_seq<=0;
            last_committed<=32'hffffffff;
            challenge_live<=0;
            pending<=0;
            issued_op<=0;
            issued_identity<=0;
            retire<=0;
        end else begin
            retire<=0;
            if (fresh_challenge && phase==LOCKED && !pending && !challenge_live) begin
                challenge_live<=1;
                next_seq<=0;
                last_committed<=32'hffffffff;
            end
            if (issue) begin
                issued_op<=op;
                issued_identity<=identity;
                pending<=1;
            end
            if (pending && complete) begin
                pending<=0;
                if (effect_success) begin
                    last_committed<=next_seq;
                    next_seq<=next_seq+1'b1;
                    case (issued_op)
                        OPEN: begin owner<=issued_identity; phase<=LOAD; end
                        FINISH: phase<=READY;
                        START: phase<=OWNED_RUN;
                        CANCEL: begin
                            owner<=0;
                            phase<=LOCKED;
                            challenge_live<=0;
                            retire<=1;
                        end
                        default: ;
                    endcase
                end else begin
                    // A failed effect must be followed by the sequencer's safe HALT.
                    owner<=issued_op==OPEN ? issued_identity : owner;
                    phase<=RELOAD;
                end
            end
        end
    end
endmodule
`default_nettype wire
