`timescale 1ns/1ps
`default_nettype none

// Measure the frozen DMX first BREAK from the native ENABLE bus beat.
module tb_dmx_reference;
    reg clk=0, rst_n=0;
    reg [7:0] ui=8'h02;
    wire [7:0] uo, uio_out, uio_oe;
    integer cycle=0, enabled=-1, fd, address, data, i, scanned;
    reg [1023:0] fixture;
    always #10 clk=~clk;
    tt_um_arnav1609_pvm dut (
        .clk(clk),.rst_n(rst_n),.ena(1'b1),.ui_in(ui),.uio_in(8'b0),
        .uo_out(uo),.uio_out(uio_out),.uio_oe(uio_oe)
    );
    always @(posedge clk) begin
        cycle=cycle+1;
        if(dut.pvm.bus_we && dut.pvm.bus_addr==16'h0f00 && dut.pvm.bus_wdata==3)
            enabled=cycle;
        #1;
        if(enabled>=0 && uo[0]===0) begin
            $display("FROZEN first BREAK from ENABLE %0d core cycles",cycle-enabled);
            if(cycle-enabled!=602) $fatal(1,"Frozen DMX ENABLE alignment");
            $finish;
        end
    end
    task send_byte(input [7:0] data);
        integer bit_index;
        begin
            for(bit_index=7;bit_index>=0;bit_index=bit_index-1) begin
                ui[2]=data[bit_index];
                repeat(8) @(negedge clk);
                ui[0]=1;
                repeat(8) @(negedge clk);
                ui[0]=0;
            end
        end
    endtask
    task write_byte(input [15:0] address,input [7:0] data);
        begin
            ui[1]=0;
            repeat(8) @(negedge clk);
            send_byte(2);
            send_byte(address[15:8]);
            send_byte(address[7:0]);
            send_byte(data);
            ui[1]=1;
            repeat(8) @(negedge clk);
        end
    endtask
    initial begin
        if(!$value$plusargs("WRITES=%s",fixture)) $fatal(1,"Missing frozen writes");
        fd=$fopen(fixture,"r");
        repeat(8) @(negedge clk);
        rst_n=1;
        repeat(8) @(negedge clk);
        for(i=0;i<165;i=i+1) begin
            scanned=$fscanf(fd,"%h %h",address,data);
            if(scanned!=2) $fatal(1,"Missing frozen write");
            write_byte(address[15:0],data[7:0]);
        end
        repeat(1000) @(negedge clk);
        $fatal(1,"Frozen DMX did not reach BREAK");
    end
endmodule

`default_nettype wire
