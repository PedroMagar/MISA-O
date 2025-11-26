`timescale 1ns / 1ps
`include "testbench/misa-o_instructions.svh"

module tb_xmem;

    reg clk;
    reg rst;
    reg [7:0] mem_data_in;

    wire        mem_enable_read;
    wire        mem_enable_write;
    wire [14:0] mem_addr;
    wire        mem_rw;
    wire [7:0]  mem_data_out;
    wire [15:0] test_data;
    wire        test_carry;

    misao dut (
        .clk(clk), 
        .rst(rst), 
        .mem_enable_read(mem_enable_read), 
        .mem_enable_write(mem_enable_write), 
        .mem_data_in(mem_data_in), 
        .mem_addr(mem_addr), 
        .mem_rw(mem_rw), 
        .mem_data_out(mem_data_out), 
        .test_data(test_data),
        .test_carry(test_carry)
    );

    reg [7:0] memory [0:255];
    integer i;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (mem_enable_write) begin
            memory[mem_addr] <= mem_data_out;
            $display("MEM[%02h] <- %02h", mem_addr, mem_data_out);
        end
    end

    always @(*) begin
        if (mem_enable_read) mem_data_in = memory[mem_addr];
        else mem_data_in = 8'h00;
    end

    // Validation
    task automatic validate(input [14:0] addr, input integer cycles, input [15:0] expected_acc);
        begin
            @(negedge clk);
            while (!(mem_enable_read && mem_addr == addr)) @(negedge clk);
            if (mem_data_in !== memory[addr]) begin
                $display("FAIL READ @%0d: mem_data_in=%02h exp=%02h", addr, mem_data_in, memory[addr]);
                $fatal(1);
            end
            repeat (cycles) @(negedge clk);
            if (test_data !== expected_acc) begin
                $display("FAIL ACC @%0d: got=%h exp=%h", addr, test_data, expected_acc);
                $fatal(1);
            end
        end
    endtask

    task automatic check_mem_byte(input [7:0] addr8, input [7:0] expected);
        begin
            if (memory[addr8] !== expected) begin
                $display("FAIL MEM[%0h]: got=%02h exp=%02h", addr8, memory[addr8], expected);
                $fatal(1);
            end
        end
    endtask

    initial begin
        $dumpfile("waves_xmem.vcd");
        $dumpvars(0, tb_xmem);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // ================================================================
        // Test Sequence (XMEM)
        // ================================================================

        // Phase 1: Setup (LK16) - RA0=0x0080, RA1=0x0090
        memory[1]  = {CFG, XOP};
        memory[2]  = {4'h4, 4'hE};   // LK16
        memory[3]  = {4'h8, LDI};
        memory[4]  = {4'h0, 4'h0};
        memory[5]  = {4'h0, 4'h0};
        memory[6]  = {SA , XOP};     // RA0=0x0080
        memory[7]  = {4'h9, LDI};
        memory[8]  = {4'h0, 4'h0};
        memory[9]  = {4'h0, 4'h0};
        memory[10] = {SA , XOP};     // RA0=0x0090
        memory[11] = {RSA, XOP};     // RA1=0x0090, RA0=0x0080

        // Phase 2: UL store/load
        memory[12] = {CFG, XOP};
        memory[13] = {4'h4, 4'hC};   // UL
        memory[14] = {4'h5, LDI};
        memory[15] = {XMEM, 4'hC};   // store UL @RA0, post-inc
        memory[16] = {4'h3, LDI};
        memory[17] = {XMEM, 4'h8};   // store UL @RA0, no inc
        memory[18] = {XMEM, 4'h0};   // load UL @RA0

        // Phase 3: LK8 store/load
        memory[19] = {CFG, XOP};
        memory[20] = {4'h4, 4'hD};   // LK8
        memory[21] = {4'hB, LDI};
        memory[22] = {4'h5, 4'h5};   // ACC=0x5B
        memory[23] = {XMEM, 4'hC};   // store byte @RA0, post-inc
        memory[24] = {4'h0, LDI};
        memory[25] = {4'h0, 4'h0};   // ACC=0
        memory[26] = {XMEM, 4'h8};   // store byte @RA0
        memory[27] = {XMEM, 4'h4};   // load byte @RA0, post-inc
        memory[28] = {XMEM, 4'h6};   // load byte @RA0, post-dec

        // Phase 4: LK16 & RA1
        memory[29] = {CFG, XOP};
        memory[30] = {4'h4, 4'hE};   // LK16
        memory[31] = {4'h1, LDI};
        memory[32] = {4'h2, 4'h2};
        memory[33] = {4'h3, 4'h3};
        memory[34] = {4'h4, 4'h4};   // ACC=0x1234
        memory[35] = {XMEM, 4'hD};   // store word @RA1, post-inc, AR=1
        memory[36] = {4'h0, LDI};
        memory[37] = {4'h0, 4'h0};
        memory[38] = {4'h0, 4'h0};
        memory[39] = {4'h0, 4'h0};   // ACC=0
        memory[40] = {XMEM, 4'h6};   // load word @RA1, post-dec, AR=1

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        // Phase 2
        validate(15'h0013, 1, 16'h0003);
        check_mem_byte(8'h80, 8'h05);
        check_mem_byte(8'h81, 8'h03);

        // Phase 3
        validate(15'h001D, 1, 16'h0000);
        check_mem_byte(8'h81, 8'h5B);
        check_mem_byte(8'h82, 8'h00);

        // Phase 4
        validate(15'h0029, 1, 16'h1234);
        check_mem_byte(8'h90, 8'h34);
        check_mem_byte(8'h91, 8'h12);

        $display("XMEM TEST DONE (validations)");
        $finish;
    end

endmodule
