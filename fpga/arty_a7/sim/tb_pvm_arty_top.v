`timescale 1ns/1ps
module tb_pvm_arty_top;
localparam integer uart_period=8680;
reg clk100=0, reset_n=0, rx=1, fixture=0;
reg [4:0] inputs=0;
wire [6:0] outputs;
wire [3:0] leds, spi;
wire [1:0] i2c_pullup;
wire tx;
tri [7:0] pads;
// The shield resistors let either I2C driver sink the bus while the supply pins stay high.
assign (pull1, pull0) pads[0] = i2c_pullup[0];
assign (pull1, pull0) pads[1] = i2c_pullup[1];
assign (pull1, highz0) pads[7:2] = 6'b111111;
reg [7:0] external_low=0;
genvar bit_index;
generate for (bit_index=0;bit_index<8;bit_index=bit_index+1) begin : stimulus
    assign pads[bit_index]=external_low[bit_index] ? 1'b0 : 1'bz;
end endgenerate
pvm_arty_top dut (.clk100(clk100), .board_reset_n(reset_n), .usb_uart_rx(rx),
    .usb_uart_tx(tx), .fixture_switch(fixture), .protocol_in(inputs),
    .protocol_out(outputs), .protocol_io(pads), .i2c_pullup(i2c_pullup), .host_spi_probe(spi), .led(leds));
always #5 clk100=~clk100;

integer fd, n, index, value, expected, rc, sequence_id=0;
integer csv, cap_length, cap_index=0, cap_number=0, port_index, pass_checks=0;
reg [1023:0] trace_path;
reg arm_capture=0, capture=0;
reg [7:0] response;
integer fixture_mode, probe_only, reset_seen=0;
time start_edge;

always @(negedge spi[1]) begin
    if (arm_capture) begin capture=1; arm_capture=0; end
end
always @(negedge dut.clk50) begin
    if (!dut.pvm_reset_n) reset_seen=reset_seen+1;
    if (capture) begin
        $fdisplay(csv,"%0d,%b,%b,%b,%b,%b,%0d,%0d",cap_index,outputs[0],outputs[1],
                  outputs[2],pads[0],pads[1],dut.pvm_uio_out,dut.pvm_uio_oe);
        cap_index=cap_index+1;
        if(cap_index==cap_length) begin capture=0; $fclose(csv); end
    end
end

task uart_put(input [7:0] byte_value);
integer i;
begin
    rx=0; #(uart_period);
    for (i=0;i<8;i=i+1) begin rx=byte_value[i]; #(uart_period); end
    rx=1; #(uart_period);
end
endtask

task uart_get(output reg [7:0] byte_value);
integer i;
begin
    // Status replies begin after the bridge consumes a complete UART request.
    if(!tx) $fatal(1,"RESPONSE_ALIGNMENT");
    fork : reply_start
        wait(tx==0);
        begin
            #12000000;
            $fatal(1,"UART_REPLY_TIMEOUT transaction %0d byte %0d",sequence_id,index);
        end
    join_any
    disable reply_start;
    #(uart_period+uart_period/2);
    for (i=0;i<8;i=i+1) begin byte_value[i]=tx; #(uart_period); end
    if(tx!==1) $fatal(1,"UART_REPLY_FRAMING");
end
endtask

initial begin
    if (!$value$plusargs("fixture=%d",fixture_mode)) fixture_mode=0;
    if (!$value$plusargs("probe_only=%d",probe_only)) probe_only=0;
    fixture=fixture_mode!=0;
    #1 reset_n=1; #2 reset_n=0; #500 reset_n=1;
    @(posedge dut.clk50); start_edge=$time;
    repeat(4) @(posedge dut.clk50);
    if($time-start_edge!=80) $fatal(1,"MMCM_RATIO");
    wait(dut.pvm_reset_n===1'b1);
    if(reset_seen<16) $fatal(1,"STARTUP_RESET");
    if(i2c_pullup!==2'b11)
        $fatal(1,"BOARD_I2C_PULLUP_IDLE");
    if (probe_only!=0) begin
        force dut.pvm_uio_oe=0;
        force dut.pvm_uio_out=0;
        for(port_index=0;port_index<8;port_index=port_index+1) begin
            external_low=8'b1<<port_index; #1;
            if(dut.pvm_uio_in!==~external_low || pads!==~external_low)
                $fatal(1,"PAD_INPUT_MAPPING");
        end
        external_low=0;
        release dut.pvm_uio_oe;
        release dut.pvm_uio_out;
        #1;
    end
    if(pads[1:0]!==2'b11)
        $fatal(1,"BOARD_I2C_PULLUP_IDLE");
    if (probe_only!=0) begin
        $display("PASS MMCM_RATIO STARTUP_RESET PAD_INPUT_MAPPING_8 BOARD_I2C_PULLUP_IDLE_2");
        $finish;
    end
    fd=$fopen("frames.txt","r");
    if(fd==0) $fatal(1,"FRAME_INPUT");
    rc=$fscanf(fd,"%d",n);
    while(rc==1) begin
        if (n==-1) begin
            reset_seen=0;
            fork uart_put(8'h02); uart_get(response); join
            if(response!==0 || reset_seen<16 || dut.pvm_reset_n!==1'b1)
                $fatal(1,"HOST_RESET");
            $display("PASS HOST_RESET");
            $fflush;
        end else if (n==-2) begin
            rc=$fscanf(fd,"%d",cap_length);
            if(rc!=1) $fatal(1,"CAPTURE_LENGTH");
            cap_number=cap_number+1;
            $sformat(trace_path,"capture_%0d.csv",cap_number);
            csv=$fopen(trace_path,"w");
            if(csv==0) $fatal(1,"CAPTURE_FILE");
            $fdisplay(csv,"core_cycle,P5,P6,P7,SDA,SCL,uio_out,uio_oe");
            cap_index=0; arm_capture=1;
        end else if (n==-3) begin
            wait(!arm_capture && !capture);
            $display("PASS CAPTURE_FRAME %0d",cap_number);
            $fflush;
        end else begin
            if(n<1 || n>260) $fatal(1,"INPUT_RANGE");
            sequence_id=sequence_id+1;
            uart_put(1); uart_put(n>>8); uart_put(n);
            for(index=0;index<n;index=index+1) begin
                rc=$fscanf(fd,"%h",value);
                if(rc!=1) $fatal(1,"FRAME_DATA");
                uart_put(value);
            end
            uart_get(response);
            if(response!==0) $fatal(1,"UART_TRANSACTION_STATUS");
            for(index=0;index<n;index=index+1) begin
                rc=$fscanf(fd,"%d",expected);
                if(rc!=1) $fatal(1,"EXPECTED_DATA");
                uart_get(response);
                if(expected>=0 && response!==expected[7:0])
                    $fatal(1,"SPI_READBACK transaction %0d byte %0d got %02x expect %02x",
                           sequence_id,index,response,expected);
                if(expected>=0) pass_checks=pass_checks+1;
            end
        end
        rc=$fscanf(fd,"%d",n);
    end
    $display("PASS UART_TO_SPI transactions=%0d checked_bytes=%0d captures=%0d",
             sequence_id,pass_checks,cap_number);
    $finish;
end
initial begin
    #1000000000;
    $fatal(1,"WRAPPER_TIMEOUT");
end
endmodule
