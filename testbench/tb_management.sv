`timescale 1ns / 1ps
`include "testbench/misa-o_instructions.svh"

module tb_management;

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

    // Validation task
    task automatic validate(input [14:0] addr, input integer cycles, input [15:0] expected_acc, input expected_carry);
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
            if (test_carry !== expected_carry) begin
                $display("FAIL CARRY @%0d: got=%b exp=%b", addr, test_carry, expected_carry);
                $fatal(1);
            end
            $display("SUCCESS AT @%0d: got=%h exp=%h", addr, {test_carry, test_data}, {expected_carry,expected_acc});
        end
    endtask

    initial begin
        $dumpfile("waves_management.vcd");
        $dumpvars(0, tb_management);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // ================================================================
        // Test Sequence (Management)
        // ================================================================
        
        // Phase 1: Setup & Pattern Loading (LK16) -> ACC = 0xAAAA
        memory[1] = {CFG, XOP};       // XOP CFG
        memory[2] = {4'h4, 4'hE};     // cfg=0x4E (LK16)
        memory[3] = {LDI, 4'h0};      // LDI opcode (imm follows)
        memory[4] = {4'hA, 4'hA};     // imm0=0xA, imm1=0xA
        memory[5] = {4'hA, 4'hA};     // imm2=0xA, imm3=0xA -> ACC=0xAAAA

        // Phase 2: SS in UL, exercising low-nibble swaps
        memory[6] = {CFG, XOP};       // XOP CFG
        memory[7] = {4'h4, 4'hC};     // cfg=0x4C (UL)
        memory[8] = {4'h1, LDI};      // ACC[0]=1 -> 0xAAA1
        memory[9] = {SS , NOP};       // swap low nibble with RS0 (0) -> ACC=0xAAA0, RS0=1
        memory[10]= {4'h2, LDI};      // ACC[0]=2 -> 0xAAA2
        memory[11]= {SS , 4'h0};      // swap low nibble with RS0 (1) -> ACC=0xAAA1, RS0=2

        // Phase 3: SA in UL, full 16-bit swap with RA0
        memory[12]= {SA , XOP};       // swap ACC(0xAAA1) <-> RA0(0) -> ACC=0x0000, RA0=0xAAA1
        memory[13]= {4'h5, LDI};      // ACC[0]=5 -> 0x0005
        memory[14]= {SA , XOP};       // swap ACC(0x0005) <-> RA0(0xAAA1) -> ACC=0xAAA1, RA0=0x0005

        // Phase 4: RSS (LK16), rotate RS0/RS1
        memory[15]= {CFG, XOP};       // XOP CFG
        memory[16]= {4'h4, 4'hE};     // cfg=0x4E (LK16)
        memory[17]= {LDI, 4'h0};      // LDI 0xBBBB
        memory[18]= {4'hB, 4'hB};     // imm0/imm1
        memory[19]= {4'hB, 4'hB};     // imm2/imm3
        memory[20]= {SS , NOP};       // swap ACC(0xBBBB) <-> RS0 -> RS0=0xBBBB
        memory[21]= {RSS, NOP};       // rotate RS stack -> RS0=0, RS1=0xBBBB
        memory[22]= {LDI, 4'h0};      // LDI 0xCCCC
        memory[23]= {4'hC, 4'hC};     // imm0/imm1
        memory[24]= {4'hC, 4'hC};     // imm2/imm3
        memory[25]= {SS , NOP};       // RS0=0xCCCC
        memory[26]= {RSS, NOP};       // RS0=0xBBBB, RS1=0xCCCC
        memory[27]= {SS , NOP};       // ACC=0xBBBB

        // Phase 5: RSA, rotate RA0/RA1 full 16b
        memory[28]= {LDI, 4'h0};      // LDI 0x1111
        memory[29]= {4'h1, 4'h1};     // imm0/imm1
        memory[30]= {4'h1, 4'h1};     // imm2/imm3
        memory[31]= {SA , XOP};       // RA0=0x1111
        memory[32]= {RSA, XOP};       // RA0<->RA1 (RA1=0x1111)
        memory[33]= {LDI, 4'h0};      // LDI 0x2222
        memory[34]= {4'h2, 4'h2};     // imm0/imm1
        memory[35]= {4'h2, 4'h2};     // imm2/imm3
        memory[36]= {SA , XOP};       // RA0=0x2222
        memory[37]= {RSA, XOP};       // RA0=0x1111, RA1=0x2222
        memory[38]= {SA , XOP};       // ACC=0x1111

        // Phase 6: RRS in UL (rotate RS0 low nibble away)
        memory[39]= {CFG, XOP};       // XOP CFG
        memory[40]= {4'h4, 4'hC};     // cfg=0x4C (UL)
        memory[41]= {4'h4, LDI};      // ACC[0]=4
        memory[42]= {SS , NOP};       // RS0 low nibble =4
        memory[43]= {4'h1, LDI};      // ACC[0]=1
        memory[44]= {SS , NOP};       // RS0 low nibble =1
        memory[45]= {RRS, XOP};       // rotate RS0 >>4 -> low nibble becomes 0
        memory[46]= {SS , NOP};       // swap low nibble back -> ACC[0]=0

        // Phase 7: RRS NOP in LK16 (RS0/ACC unchanged)
        memory[47]= {CFG, XOP};       // XOP CFG
        memory[48]= {4'h4, 4'hE};     // cfg=0x4E (LK16)
        memory[49]= {4'h5, LDI};      // ACC=0x0005
        memory[50]= {SS , NOP};       // RS0=0x0005
        memory[51]= {RRS, XOP};       // NOP in LK16
        memory[52]= {SS , NOP};       // ACC should remain 0x0005

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        // Validations (mem_addr in decimal, cycles>=1 after read)
        validate( 5, 1, 16'hAAAA, 1'b0); // after LDI 0xAAAA
        validate( 8, 1, 16'hAAA1, 1'b0); // LDI 1
        validate( 9, 1, 16'hAAA0, 1'b0); // SS -> low nibble out
        validate(10, 1, 16'hAAA2, 1'b0); // LDI 2
        validate(11, 1, 16'hAAA1, 1'b0); // SS swap back (RS0=2)
        validate(12, 1, 16'h0000, 1'b0); // SA -> ACC cleared, RA0=AAA1
        validate(14, 1, 16'h0005, 1'b0); // LDI 5
        validate(15, 1, 16'hAAA1, 1'b0); // SA restore ACC
        validate(20, 1, 16'hBBBB, 1'b0); // RS0=BBBB after SS
        validate(21, 1, 16'hBBBB, 1'b0); // after RSS rotation (ACC unchanged yet)
        validate(25, 1, 16'hCCCC, 1'b0); // after loading 0xCCCC
        validate(27, 1, 16'hBBBB, 1'b0); // after RSS/SS -> ACC=BBBB
        validate(31, 1, 16'h0000, 1'b0); // after SA -> ACC cleared, RA0=1111
        validate(33, 1, 16'h2222, 1'b0); // after LDI 2222
        validate(38, 1, 16'h1111, 1'b0); // after RSA swaps -> ACC=1111
        validate(45, 1, 16'h0000, 1'b0); // after RRS UL low nibble cleared
        validate(46, 1, 16'h0000, 1'b0); // SS brings RS0 low nibble (0) -> ACC low=0
        validate(50, 1, 16'h0005, 1'b0); // LK16 LDI 5 / SS into RS0
        validate(52, 1, 16'h0005, 1'b0); // RRS NOP in LK16, ACC unchanged

        $display("MANAGEMENT TEST DONE (validations)");
        $finish;
    end

endmodule
