`timescale 1ns/1ps
`default_nettype none

// Frame KMAC proof checker. Policy, image-chain verification and bus authorization
// remain in the caller. Reuses the externally shared pvm_auth_hash instance.
module pvm_auth_mac (
    input wire clk, rst_n, start, trust_valid,
    input wire [255:0] master_key,
    input wire [63:0] device_id,  // wire byte zero is [7:0]
    input wire [7:0] identity, body_length,
    output reg [7:0] frame_read_index,
    input wire [7:0] frame_read_byte,
    output wire hash_start, hash_release,
    output wire [1:0] hash_mode,
    output wire [255:0] hash_key,
    output wire [15:0] hash_length,
    output wire [7:0] hash_data,
    output wire hash_data_valid,
    input wire hash_idle, hash_ready, hash_valid,
    output wire [4:0] hash_read_index,
    input wire [7:0] hash_read_byte,
    output reg done, authenticated
);
    localparam IDLE=0, DERIVE=1, DERIVE_BYTES=2, DERIVE_READ=3,
               COMMAND=4, COMMAND_BYTES=5, COMPARE=6;
    reg [2:0] state;
    reg [255:0] employee_key;
    reg [7:0] index, user_id, body_size;
    reg different;
    wire derive = state==DERIVE || state==DERIVE_BYTES || state==DERIVE_READ;
    assign hash_start = (state==DERIVE || state==COMMAND) && hash_idle && trust_valid;
    assign hash_release = hash_valid && index==31 && (state==DERIVE_READ || state==COMPARE);
    assign hash_mode = derive ? 2'd1 : 2'd2;
    assign hash_key = derive ? master_key : employee_key;
    assign hash_length = derive ? 16'd9 : {8'b0,body_size};
    assign hash_data = state==DERIVE_BYTES ? (index==8 ? user_id : (device_id >> {index[2:0],3'b000})) :
                       frame_read_byte;
    assign hash_data_valid = state==DERIVE_BYTES || state==COMMAND_BYTES;
    assign hash_read_index = index[4:0];
    always @* begin
        frame_read_index=0;
        if (state==COMMAND_BYTES) frame_read_index=8'd1+index;
        else if (state==COMPARE) frame_read_index=8'd1+body_size+index;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            index <= 0;
            user_id <= 0;
            body_size <= 0;
            done <= 0;
            authenticated <= 0;
            different <= 0;
            employee_key <= 0;
        end else begin
            done <= 0;
            authenticated <= 0;
            case (state)
                IDLE: if (start) begin
                    if (trust_valid && identity>=1 && identity<=11 &&
                        body_length>=64 && body_length<=120) begin
                        user_id <= identity;
                        body_size <= body_length;
                        index <= 0;
                        different <= 0;
                        state <= DERIVE;
                    end else done <= 1;
                end
                DERIVE: if (hash_start) state <= DERIVE_BYTES;
                DERIVE_BYTES: if (hash_ready) begin
                    index <= index + 1'b1;
                    if (index==8) begin index<=0; state<=DERIVE_READ; end
                end
                DERIVE_READ: if (hash_valid) begin
                    employee_key <= {hash_read_byte,employee_key[255:8]};
                    index <= index + 1'b1;
                    if (index==31) begin index<=0; state<=COMMAND; end
                end
                COMMAND: if (hash_start) begin
                    employee_key<=0;
                    state<=COMMAND_BYTES;
                end
                COMMAND_BYTES: if (hash_ready) begin
                    index<=index+1'b1;
                    if (index==body_size-1'b1) begin index<=0; state<=COMPARE; end
                end
                COMPARE: if (hash_valid) begin
                    different <= different || (hash_read_byte != frame_read_byte);
                    index <= index + 1'b1;
                    if (index==31) begin
                        authenticated <= trust_valid && !different && hash_read_byte==frame_read_byte;
                        done<=1;
                        state<=IDLE;
                    end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
