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
            $display("SUCCESS AT @%0d: got=%b exp=%b", addr, {test_carry, test_data}, {expected_carry,expected_acc});
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
        memory[1]  = {CFG, XOP};     // XOP CFG
        memory[2]  = {4'h4, 4'hE};   // cfg=0x4E (LK16)
        memory[3]  = {LDI, 4'h0};    // LDI opcode
        memory[4]  = {4'h8, 4'h0};   // imm0=8, imm1=0
        memory[5]  = {4'h0, 4'h0};   // imm2=0, imm3=0 -> ACC=0x0080
        memory[6]  = {SA , XOP};     // RA0=0x0080
        memory[7]  = {LDI, 4'h0};    // LDI opcode
        memory[8]  = {4'h9, 4'h0};   // imm0=9, imm1=0
        memory[9]  = {4'h0, 4'h0};   // imm2=0, imm3=0 -> ACC=0x0090
        memory[10] = {SA , XOP};     // RA0=0x0090
        memory[11] = {RSA, XOP};     // RA1=0x0090, RA0=0x0080

        // Phase 2: UL store/load
        memory[12] = {CFG, XOP};     // XOP CFG
        memory[13] = {4'h4, 4'hC};   // cfg=0x4C (UL)
        memory[14] = {4'h5, LDI};    // ACC=5
        memory[15] = {XMEM, 4'hC};   // store nibble @RA0 (0x80), post-inc -> RA0=0x81
        memory[16] = {4'h3, LDI};    // ACC=3
        memory[17] = {XMEM, 4'h8};   // store nibble @RA0 (0x81), no inc
        memory[18] = {XMEM, 4'h0};   // load nibble @RA0 (0x81) -> ACC=3

        // Phase 3: LK8 store/load
        memory[19] = {CFG, XOP};     // XOP CFG
        memory[20] = {4'h4, 4'hD};   // cfg=0x4D (LK8)
        memory[21] = {4'hB, LDI};    // ACC=0x0B
        memory[22] = {4'h5, 4'h5};   // ACC=0x5B
        memory[23] = {XMEM, 4'hC};   // store byte @RA0 (0x81), post-inc -> RA0=0x82
        memory[24] = {4'h0, LDI};    // ACC=0
        memory[25] = {4'h0, 4'h0};   // ACC=0
        memory[26] = {XMEM, 4'h8};   // store byte @RA0 (0x82)
        memory[27] = {XMEM, 4'h4};   // load byte @RA0 (0x82), post-inc -> ACC=0, RA0=0x83
        memory[28] = {XMEM, 4'h6};   // load byte @RA0 (0x83), post-dec -> ACC=0, RA0=0x82

        // Phase 4: LK16 & RA1
        memory[29] = {CFG, XOP};     // XOP CFG
        memory[30] = {4'h4, 4'hE};   // cfg=0x4E (LK16)
        memory[31] = {LDI, 4'h0};    // LDI 0x1234
        memory[32] = {4'h3, 4'h4};   // imm0=1, imm1=2
        memory[33] = {4'h1, 4'h2};   // imm2=3, imm3=4 -> ACC=0x1234
        memory[35] = {XMEM, 4'hD};   // store word @RA1 (0x0090/91), post-inc AR=1
        memory[36] = {4'h0, LDI};    // ACC=0
        memory[37] = {4'h0, 4'h0};
        memory[38] = {NOP, 4'h0};
        memory[39] = {NOP, NOP};   // ACC=0
        memory[40] = {XMEM, 4'h6};   // load word @RA1 (post-dec AR=1) -> ACC=0x1234

        // Phase 5: Advanced XMEM (AR=RA1 in UL, DIR=dec in UL, store endianness)
        memory[41] = {CFG, XOP};     // UL (default)
        memory[42] = {4'h4, 4'hC};
        memory[43] = {4'h5, LDI};    // ACC=5
        memory[44] = {XMEM, 4'hC};   // Store UL @RA1 (AR=1, DIR=0, AM=0)
        memory[45] = {XMEM, 4'h0};   // Load UL @RA1 (confirm)
        memory[46] = {XMEM, 4'hE};   // Store UL @RA1 with DIR=1, AM=1 (post-dec)
        memory[47] = {XMEM, 4'hE};   // Load UL @RA1 after dec
        // Store-word endianness check in LK16
        memory[48] = {CFG, XOP};
        memory[49] = {4'h4, 4'hE};   // LK16
        memory[50] = {4'h1, LDI};    // imm0
        memory[51] = {4'h2, 4'h2};   // imm1/imm2
        memory[52] = {4'h3, 4'h3};
        memory[53] = {4'h4, 4'h4};   // ACC=0x1234
        memory[54] = {XMEM, 4'hD};   // Store word @RA1 (post-inc, AR=1)
        memory[55] = {XMEM, 4'h6};   // Load word back (post-dec, AR=1)

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        // Phase 1 (initial LDIs to set RA0/RA1) - ACC loads
        validate(5, 1, 16'h0080, 1'b0);  // after LDI 0x0080
        validate(9, 1, 16'h0090, 1'b0);  // after LDI 0x0090

        // Phase 2 (UL nibble ops)
        validate(14, 1, 16'h0005, 1'b0); // after LDI 5
        validate(16, 1, 16'h0003, 1'b0); // after LDI 3
        validate(18, 1, 16'h0003, 1'b0); // after load nibble -> ACC=3
        check_mem_byte(128, 8'h05);
        check_mem_byte(129, 8'h03);

        // Phase 3 (LK8 byte ops)
        validate(21, 1, 16'h005B, 1'b0); // after forming 0x5B
        validate(24, 1, 16'h0000, 1'b0); // after clearing ACC
        validate(27, 1, 16'h0000, 1'b0); // after load byte (ACC=0)
        validate(28, 1, 16'h0000, 1'b0); // after post-dec load (ACC=0)
        check_mem_byte(129, 8'h5B);
        check_mem_byte(130, 8'h00);

        // Phase 4 (LK16 word ops, AR=RA1)
        validate(33, 1, 16'h1234, 1'b0); // after LDI 0x1234
        validate(36, 1, 16'h0000, 1'b0); // after clearing ACC
        validate(40, 1, 16'h1234, 1'b0); // after load word back
        check_mem_byte(144, 8'h34);
        check_mem_byte(145, 8'h12);

        // Phase 5 (AR=RA1 in UL, DIR=dec, store endianness)
        validate(43, 1, 16'h0005, 1'b0); // ACC=5 store to RA1
        validate(45, 1, 16'h0005, 1'b0); // load back via RA1
        validate(47, 1, 16'h0005, 1'b0); // after DIR=dec load
        validate(53, 1, 16'h1234, 1'b0); // after LDI 0x1234 (store)
        validate(55, 1, 16'h1234, 1'b0); // after load word back
        check_mem_byte(144, 8'h34);
        check_mem_byte(145, 8'h12);

        $display("XMEM TEST DONE (validations)");
        $finish;
    end

endmodule
