`timescale 1ns / 1ps
`include "testbench/misa-o_instructions.svh"

module tb_alu;

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

    // Validation task: wait for read of addr, check mem_data_in, then after cycles check ACC.
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

    initial begin
        $dumpfile("waves_alu.vcd");
        $dumpvars(0, tb_alu);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // ================================================================
        // Test Sequence (ALU)
        // ================================================================

        // Phase 1: UL arithmetic
        memory[1]  = {CFG, XOP};     // XOP CFG
        memory[2]  = {4'h4, 4'hC};   // cfg=0x4C (UL, CEN=1)
        memory[3]  = {4'h5, LDI};    // ACC=5
        memory[4]  = {SS , NOP};     // RS0=5
        memory[5]  = {4'h3, LDI};    // ACC=3
        memory[6]  = {ADD, NOP};     // ACC=8, C=0
        memory[7]  = {ADD, NOP};     // ACC=D, C=0
        memory[8]  = {ADD, NOP};     // ACC=2 (overflow), C=1
        memory[9]  = {CC , NOP};     // C=0
        memory[10] = {INC, NOP};     // ACC=3
        memory[11] = {SUB, XOP};     // ACC=E, C=1 (borrow)

        // Phase 2: UL logic & shifts
        memory[12] = {4'hC, LDI};    // ACC=C
        memory[13] = {SS , NOP};     // RS0=C
        memory[14] = {4'hA, LDI};    // ACC=A
        memory[15] = {AND, NOP};     // ACC=8
        memory[16] = {OR , NOP};     // ACC=C
        memory[17] = {XOR, XOP};     // ACC=0
        memory[18] = {INV, XOP};     // ACC=F
        memory[19] = {SHL, NOP};     // ACC=E, C=1
        memory[20] = {SHR, XOP};     // ACC=7, C=0

        // Phase 3: LK8 arithmetic
        memory[21] = {CFG, XOP};     // XOP CFG
        memory[22] = {4'h4, 4'hD};   // cfg=0x4D (LK8)
        memory[23] = {4'h1, LDI};    // ACC=0x01
        memory[24] = {NOP, 4'h0};    // NOP
        memory[25] = {SS , NOP};     // RS0=0x01
        memory[26] = {4'hF, LDI};    // ACC=0x0F
        memory[27] = {NOP, 4'hF};    // ACC=0xFF
        memory[28] = {ADD, NOP};     // ACC=0x00, C=1

        // Phase 4: LK16 arithmetic
        memory[29] = {CFG, XOP};     // XOP CFG
        memory[30] = {4'h4, 4'hE};   // cfg=0x4E (LK16)
        memory[31] = {4'h1, LDI};    // ACC=0x0001
        memory[32] = {4'h0, 4'h0};   // imm1/imm2
        memory[33] = {NOP, 4'h0};    // ACC=0x0001
        memory[34] = {SS , NOP};     // RS0=0x0001
        memory[35] = {4'hF, LDI};    // ACC=0x000F
        memory[36] = {4'hF, 4'hF};   // imm1/imm2
        memory[37] = {NOP, 4'hF};    // ACC=0xFFFF
        memory[38] = {ADD, NOP};     // ACC=0x0000, C=1

        // Phase 5: DEC with CEN variations, SHL/SHR in LK8/LK16
        memory[39] = {CFG, XOP};     // cfg 0x4C (UL, CEN=1)
        memory[40] = {4'h4, 4'hC};
        memory[41] = {4'h3, LDI};    // ACC=3
        memory[42] = {DEC, XOP};     // ACC=2, C=0
        memory[43] = {CFG, XOP};     // cfg 0x44 (UL, CEN=0)
        memory[44] = {4'h4, 4'h4};
        memory[45] = {DEC, XOP};     // ACC=1, C=1 (borrow)
        // LK8 shifts
        memory[46] = {CFG, XOP};
        memory[47] = {4'h4, 4'hD};   // LK8
        memory[48] = {4'hF, LDI};    // ACC=0x0F
        memory[49] = {SHL, NOP};     // ACC=0x1E, C from bit7=0
        memory[50] = {SHR, XOP};     // ACC=0x0F, C=0
        // LK16 shifts
        memory[51] = {CFG, XOP};
        memory[52] = {4'h4, 4'hE};   // LK16
        memory[53] = {4'h1, LDI};    // ACC=0x0001
        memory[54] = {SHL, NOP};     // ACC=0x0002, C=0
        memory[55] = {SHR, XOP};     // ACC=0x0001, C=0

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        // Phase 1 (UL arithmetic)
        validate(3, 1, 16'h0005, 1'b0); // LDI -> ACC=5
        validate(4, 1, 16'h0000, 1'b0); // SS  -> ACC=0, RS0=5
        validate(5, 1, 16'h0003, 1'b0); // LDI -> ACC=3
        validate(6, 1, 16'h0008, 1'b0); // ADD -> ACC=8
        validate(7, 1, 16'h000D, 1'b0); // ADD -> ACC=D
        validate(8, 1, 16'h0002, 1'b1); // ADD -> ACC=2, C=1
        validate(9, 1, 16'h0002, 1'b0); // CC  -> C=0 (ACC unchanged)
        validate(10,1, 16'h0003, 1'b0); // INC -> ACC=3
        validate(11,1, 16'h000E, 1'b1); // SUB -> ACC=E, C=1

        // Phase 2 (UL logic/shifts)
        validate(12,1, 16'h000C, 1'b1); // LDI -> ACC=C
        validate(13,1, 16'h0005, 1'b1); // SS  -> ACC=5, RS0=C
        validate(14,1, 16'h000A, 1'b1); // LDI -> ACC=A
        validate(15,1, 16'h0008, 1'b0); // AND -> ACC=8
        validate(16,1, 16'h000C, 1'b0); // OR  -> ACC=C
        validate(17,1, 16'h0000, 1'b0); // XOR -> ACC=0
        validate(18,1, 16'h000F, 1'b1); // INV -> ACC=F, C=1
        validate(19,1, 16'h000E, 1'b1); // SHL -> ACC=E, C=1
        validate(20,1, 16'h0007, 1'b0); // SHR -> ACC=7, C=0

        // Phase 3 (LK8 arithmetic)
        validate(23,1, 16'h0001, 1'b0); // LDI -> ACC=0x01
        validate(25,1, 16'h000C, 1'b0); // SS  -> ACC=0x0C, RS0=1
        validate(26,1, 16'h000F, 1'b0); // LDI -> ACC=0x0F
        validate(27,1, 16'h00FF, 1'b0); // NOP extend -> ACC=0x00FF
        validate(28,1, 16'h0000, 1'b1); // ADD RS0=1 -> ACC=0x00, C=1

        // Phase 4 (LK16 arithmetic)
        validate(33,1, 16'h0001, 1'b1); // LDI -> ACC=0x0001
        validate(34,1, 16'h0001, 1'b1); // SS  -> ACC=0x0001 (RS0=1)
        validate(37,1, 16'hFFFF, 1'b1); // LDI -> ACC=0xFFFF
        validate(38,1, 16'h0000, 1'b1); // ADD RS0=1 -> ACC=0x0000, C=1

        // Phase 5 (DEC/shift variations)
        validate(41,1, 16'h0003, 1'b1); // LDI -> ACC=3
        validate(42,1, 16'h0002, 1'b0); // DEC (CEN=1) -> ACC=2, C=0
        validate(45,1, 16'h0001, 1'b1); // DEC (CEN=0) -> ACC=1, borrow sets C
        validate(48,1, 16'h000F, 1'b1); // LDI (LK8) -> ACC=0x0F
        validate(49,1, 16'h001E, 1'b0); // SHL (LK8) -> ACC=0x1E
        validate(50,1, 16'h000F, 1'b0); // SHR (LK8) -> ACC=0x0F
        validate(53,1, 16'h0001, 1'b0); // LDI (LK16) -> ACC=0x0001
        validate(54,1, 16'h0002, 1'b0); // SHL (LK16) -> ACC=0x0002
        validate(55,1, 16'h0001, 1'b0); // SHR (LK16) -> ACC=0x0001

        $display("ALL ALU TESTS (validations) DONE");
        $finish;
    end

endmodule
