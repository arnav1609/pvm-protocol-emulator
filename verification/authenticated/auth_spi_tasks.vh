    localparam [255:0] FIXTURE_MASTER = 256'h1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100;
    reg trust_valid=0, trust_challenge_valid=0;
    reg [127:0] trust_challenge=0;
    wire trust_challenge_ready, trust_challenge_retired;
    integer auth_cycles=0, writes_seen=0, enable_cycle=-1;
    integer last_write_cycle=0;
    integer acks_seen=0;
    reg [7:0] cached_first, cached_size;
    reg trace_write=0;

    pvm_top dut (
        .clk(clk),.rst_n(rst_n),.ui_in(ui),.uio_in({6'b0,scl,sda}),
        .uo_out(uo),.uio_out(uio_out),.uio_oe(uio_oe),.trust_valid(trust_valid),
        .trust_master_key(FIXTURE_MASTER),.trust_device_id(64'h0100000000000000),
        .trust_challenge_valid(trust_challenge_valid),.trust_challenge(trust_challenge),
        .trust_challenge_ready(trust_challenge_ready),.trust_challenge_retired(trust_challenge_retired)
    );

    always @(posedge clk) begin
        auth_cycles=auth_cycles+1;
        if (rst_n && dut.bus_rack) acks_seen=acks_seen+1;
        if (rst_n && dut.bus_we) begin
            if (dut.bus_re || dut.bus_rack)
                $fatal(1,"Overlapping authorized bus strobes");
            if (trace_write)
                $display("WRITE %04x %02x",dut.bus_addr,dut.bus_wdata);
            writes_seen=writes_seen+1;
            last_write_cycle=auth_cycles;
            if (dut.bus_addr==16'h0f00 && dut.bus_wdata==3)
                enable_cycle=auth_cycles;
        end
    end

    task auth_reset;
        begin
            @(negedge clk);
            rst_n=0; trust_valid=0; trust_challenge_valid=0; ui=8'h02;
            repeat (6) @(negedge clk);
            rst_n=1;
            repeat (6) @(negedge clk);
        end
    endtask

    task enroll(input [127:0] fresh);
        begin
            @(negedge clk);
            trust_valid=1; trust_challenge=fresh; trust_challenge_valid=1;
            #1;
            if (trust_challenge_ready!==1) $fatal(1,"Fresh challenge was not accepted");
            @(negedge clk);
            trust_challenge_valid=0;
        end
    endtask

    task secure_read(input [15:0] addr, output reg [7:0] value);
        reg [7:0] ignore;
        begin
            open_frame(8'ha2,addr);
            spi_byte(0,ignore);
            spi_byte(0,value);
            set_select(0);
        end
    endtask

    task snapshot(output reg [7:0] phase, result, owner,
                  output reg busy, output reg [31:0] last, next);
        reg [7:0] response [0:73];
        reg [7:0] ignore;
        integer i;
        begin
            set_select(1);
            spi_byte(8'ha1,ignore);
            spi_byte(0,ignore);
            for(i=0;i<74;i=i+1) spi_byte(0,response[i]);
            set_select(0);
            if(response[0]!==1) $fatal(1,"INFO version got %02x",response[0]);
            phase=response[1]; busy=(response[2]!==0); result=response[3]; owner=response[4];
            next={response[29],response[30],response[31],response[32]};
            last={response[33],response[34],response[35],response[36]};
            cached_size=response[69]; cached_first=response[70];
        end
    endtask

    // Each row supplies one complete wire frame and its committed outcome.
    // Mode 2 transmits START and returns at the accepted ENABLE edge.
    task run_auth_vectors;
        integer fd, step, records, length, mode, i, read_ok, before_writes, expected_writes, polls;
        integer frame_sent, frame_start_cycle, before_acks;
        reg [7:0] submit_bytes [0:152];
        reg [7:0] phase, result, owner, want_phase, want_result, want_owner, octet, ignore;
        reg [31:0] last, next, want_last;
        reg busy;
        reg [127:0] fresh;
        reg [1023:0] path;
        begin
            if (!$value$plusargs("VECTORS=%s",path)) $fatal(1,"Missing vectors");
            fd=$fopen(path,"r");
            if($fscanf(fd,"%d",records)!=1) $fatal(1,"Missing transaction count");
            for(step=0;step<records;step=step+1) begin
                read_ok=$fscanf(fd,"%d",mode);
                if(read_ok!=1) $fatal(1,"Missing mode at %0d",step);
                if(mode==0) begin
                    if($fscanf(fd,"%h",fresh)!=1) $fatal(1,"Missing challenge");
                    enroll(fresh);
                end else if(mode==3) auth_reset;
                else if(mode==4) begin
                    @(negedge clk); trust_valid=0;
                    repeat (4) @(negedge clk);
                    if (uio_oe!==0) $fatal(1,"Trust-loss pin release");
                end else if(mode==10) begin
                    before_acks=acks_seen;
                    secure_read(16'h0f11,octet);
                    if (octet!==0 || acks_seen!=before_acks)
                        $fatal(1,"Public RX read or acknowledgement");
                end else begin
                    read_ok=$fscanf(fd,"%d %h %h %h %h %d",length,want_phase,want_result,
                                   want_owner,want_last,expected_writes);
                    if(read_ok!=6) $fatal(1,"Missing transaction outcome at %0d",step);
                    before_writes=writes_seen;
                    before_acks=acks_seen;
                    frame_start_cycle=auth_cycles;
                    set_select(1);
                    for(i=0;i<length;i=i+1) begin
                        if($fscanf(fd,"%h",octet)!=1) $fatal(1,"Missing wire byte");
                        submit_bytes[i]=octet;
                        spi_byte(octet,ignore);
                    end
                    if(mode==5) begin
                        ui[2]=1; repeat(8) @(negedge clk); ui[0]=1;
                        repeat(8) @(negedge clk); ui[0]=0;
                    end
                    set_select(0);
                    frame_sent=auth_cycles;
                    if (mode==8) begin
                        set_select(1);
                        for(i=0;i<length;i=i+1)
                            spi_byte(submit_bytes[i],ignore);
                        set_select(0);
                    end
                    if(mode==2 || mode==7) begin
                        for(i=0;i<50000 && writes_seen==before_writes;i=i+1) @(negedge clk);
                        if(writes_seen!=before_writes+1 || auth_cycles-enable_cycle>1)
                            $fatal(1,"START did not issue one ENABLE");
                        ready=1;
                        if(mode==7)
                            check_dmx;
                    end else if(mode==6) begin
                        // Hardware reset overrides a retained, authenticated transaction in flight.
                        repeat(5000) @(negedge clk);
                        auth_reset;
                        if(writes_seen!=before_writes) $fatal(1,"Write during interrupted command");
                    end else begin
                        busy=1; polls=0;
                        while(busy && polls<8) begin
                            snapshot(phase,result,owner,busy,last,next);
                            polls=polls+1;
                        end
                        if(busy || phase!==want_phase || result!==want_result ||
                           owner!==want_owner || last!==want_last || writes_seen-before_writes!=expected_writes)
                            $fatal(1,"AUTH step=%0d phase=%0d result=%0d owner=%0d last=%08x writes=%0d expected=%0d,%0d,%0d,%08x,%0d",
                                   step,phase,result,owner,last,writes_seen-before_writes,
                                   want_phase,want_result,want_owner,want_last,expected_writes);
                        if(submit_bytes[2]==7 && submit_bytes[0]==8'ha0 && result==0) begin
                            if(acks_seen-before_acks!=submit_bytes[65] || cached_size!==submit_bytes[65] ||
                               cached_first!==8'h17)
                                $fatal(1,"Authenticated RX cache or ACK mismatch");
                        end else if(acks_seen!=before_acks) $fatal(1,"Unexpected RX acknowledgement");
                        $display("AUTH_CHECK %0d %0d %0d %0d %08x %0d",
                                 step,phase,result,owner,last,writes_seen-before_writes);
                    end
                    if(writes_seen>before_writes)
                        $display("LATENCY %0d %0d %0d %0d",step,submit_bytes[2],
                                 last_write_cycle-frame_sent,last_write_cycle-frame_start_cycle);
                end
            end
            $fclose(fd);
        end
    endtask

    task auth_image;
        reg [7:0] id;
        begin
            auth_reset;
            set_select(1); spi_byte(8'h9f,id); spi_byte(0,id); set_select(0);
            if (id!==8'h50) $fatal(1,"PVM ID compatibility");
            trace_write=1;
            run_auth_vectors;
        end
    endtask

    task auth_control;
        reg [7:0] value;
        begin
            auth_reset;
            trace_write=1;
            run_auth_vectors;
            secure_read(16'h0f11,value);
            if (value!==0) $fatal(1,"SAFE_READ exposes RX");
            secure_read(16'h0000,value);
            if (value!==0) $fatal(1,"SAFE_READ exposes IMEM");
        end
    endtask

    task check_dmx;
        integer fd, scan, prior, count, start_cycle, sample_cycle, want_cycle, want_bit;
        reg [1023:0] path;
        begin
            if(!$value$plusargs("DMX=%s",path)) $fatal(1,"Missing DMX reference");
            fd=$fopen(path,"r");
            prior=uo[0]; count=0; start_cycle=-1;
            for(sample_cycle=0;sample_cycle<139000;sample_cycle=sample_cycle+1) begin
                edge_sample;
                if(uo[0]!==prior[0]) begin
                    if(start_cycle<0) begin
                        start_cycle=sample_cycle;
                        if(auth_cycles-enable_cycle!=602)
                            $fatal(1,"DMX first BREAK from ENABLE got %0d clocks",auth_cycles-enable_cycle);
                    end
                    scan=$fscanf(fd,"%d %d",want_cycle,want_bit);
                    if(scan!=2 || want_cycle!=sample_cycle-start_cycle || want_bit[0]!==uo[0]) begin
                        if(count==2 && sample_cycle-start_cycle < 7000) $fatal(1,"DMX_MAB_MIN");
                        $fatal(1,"DMX edge %0d elapsed %0d expected %0d",count,sample_cycle-start_cycle,want_cycle);
                    end
                    $display("EDGE %0d %0d",sample_cycle-start_cycle,uo[0]);
                    count=count+1; prior=uo[0];
                end
            end
            if(count!=392 || $fscanf(fd,"%d %d",want_cycle,want_bit)==2)
                $fatal(1,"DMX edge count %0d",count);
            secure_read(16'h0f01,status);
            if(status[2:0]!==3'd4) $fatal(1,"DMX did not complete");
            $display("DMX 392 edges match frozen RTL");
        end
    endtask
