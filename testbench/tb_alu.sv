`timescale 1ns / 1ps
`include "testbench/misa-o_instructions.svh"

module tb_misao;

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
    reg [14:0] last_addr;
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
        // Keep instruction bus driven; core fetches once per byte.
        mem_data_in = memory[mem_addr];
    end

    // Validation task: wait for fetch of addr, then after cycles check ACC/C.
    task automatic validate(input [14:0] addr, input integer cycles, input [15:0] expected_acc, input expected_carry);
        begin
            if (last_addr != addr) begin
                // Sample mem_addr right after the negedge update so we catch the fetch.
                @(negedge clk); #0;
                while (mem_addr != addr) begin
                    @(negedge clk); #0;
                end
            end
            last_addr = addr;
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
        $dumpfile("waves_misao.vcd");
        $dumpvars(0, tb_misao);

        rst = 1;
        last_addr = 15'h7fff;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // ================================================================
        // Test Sequence (ALU)
        // ================================================================

        // Phase 1: UL arithmetic (ADD, SUB, INC, DEC)
        memory[1]  = {4'h4, CFG};    // CFG 0x44 (UL, CI=0, IMM=0)
        memory[2]  = {NOP, 4'h4};
        memory[3]  = {4'h5, LDI};    // LDI 0x5
        memory[4]  = {NOP, SS};      // SS -> RS0=0x5
        memory[5]  = {4'h3, LDI};    // LDI 0x3
        memory[6]  = {NOP, ADD};     // ADD  -> ACC=0x8
        memory[7]  = {4'h3, LDI};    // LDI 0x3
        memory[8]  = {SUB, XOP};     // SUB  -> ACC=0xE, C=1
        memory[9]  = {NOP, INC};     // INC  -> ACC=0xF
        memory[10] = {DEC, XOP};     // DEC  -> ACC=0xE

        memory[11] = {4'hC, CFG};    // CFG 0x4C (UL, IMM=1, CI=0)
        memory[12] = {NOP, 4'h4};
        memory[13] = {4'h0, LDI};    // LDI 0x0
        memory[14] = {NOP, SS};      // SS -> RS0=0x0
        memory[15] = {4'h1, LDI};    // LDI 0x1
        memory[16] = {4'h2, ADD};    // ADDI #2 -> ACC=0x3
        memory[17] = {4'h1, LDI};    // LDI 0x1
        memory[18] = {SUB, XOP};     // SUBI prefix
        memory[19] = {NOP, 4'h2};    // imm=2 -> ACC=0xF, C=1

        memory[20] = {4'h4, CFG};    // CFG 0xC4 (UL, CI=1, IMM=0)
        memory[21] = {NOP, 4'hC};
        memory[22] = {4'h1, LDI};    // LDI 0x1
        memory[23] = {NOP, SS};      // SS -> RS0=0x1
        memory[24] = {4'h0, LDI};    // LDI 0x0
        memory[25] = {NOP, SHL};     // SHL -> C=0
        memory[26] = {4'h1, LDI};    // LDI 0x1
        memory[27] = {NOP, ADD};     // ADD (CI=1, C=0) -> ACC=0x2
        memory[28] = {4'h8, LDI};    // LDI 0x8
        memory[29] = {NOP, SHL};     // SHL -> C=1
        memory[30] = {4'h1, LDI};    // LDI 0x1
        memory[31] = {NOP, ADD};     // ADD (CI=1, C=1) -> ACC=0x3
        memory[32] = {4'h1, LDI};    // LDI 0x1
        memory[33] = {SUB, XOP};     // SUB (CI=1, C=0) -> ACC=0x0
        memory[34] = {4'h8, LDI};    // LDI 0x8
        memory[35] = {NOP, SHL};     // SHL -> C=1
        memory[36] = {4'h1, LDI};    // LDI 0x1
        memory[37] = {SUB, XOP};     // SUB (CI=1, C=1) -> ACC=0xF, C=1

        // Phase 1: UL logic & shifts (AND, INV, OR, XOR, SHL, SHR)
        memory[38] = {4'h4, CFG};    // CFG 0x44 (UL, CI=0, IMM=0)
        memory[39] = {NOP, 4'h4};
        memory[40] = {4'h0, LDI};    // LDI 0x0
        memory[41] = {NOP, SHL};     // SHL -> C=0
        memory[42] = {4'hC, LDI};    // LDI 0xC
        memory[43] = {NOP, SS};      // SS -> RS0=0xC
        memory[44] = {4'hA, LDI};    // LDI 0xA
        memory[45] = {NOP, AND};     // AND -> ACC=0x8
        memory[46] = {NOP, OR};      // OR  -> ACC=0xC
        memory[47] = {XOR, XOP};     // XOR -> ACC=0x0
        memory[48] = {INV, XOP};     // INV -> ACC=0xF
        memory[49] = {NOP, SHL};     // SHL -> ACC=0xE, C=1
        memory[50] = {SHR, XOP};     // SHR -> ACC=0x7, C=0

        memory[51] = {4'hC, CFG};    // CFG 0x4C (UL, IMM=1)
        memory[52] = {NOP, 4'h4};
        memory[53] = {4'h8, LDI};    // LDI 0x8
        memory[54] = {NOP, SHL};     // SHL -> C=1
        memory[55] = {4'h0, LDI};    // LDI 0x0
        memory[56] = {NOP, SS};      // SS -> RS0=0x0
        memory[57] = {4'h5, LDI};    // LDI 0x5
        memory[58] = {4'h3, AND};    // ANDI #3 -> ACC=0x1
        memory[59] = {4'h2, OR};     // ORI  #2 -> ACC=0x3
        memory[60] = {XOR, XOP};     // XORI prefix
        memory[61] = {NOP, 4'h7};    // imm=7 -> ACC=0x4

        // Phase 2: LK8 arithmetic (ADD, SUB, INC, DEC)
        memory[62] = {4'h5, CFG};    // CFG 0x45 (LK8, CI=0, IMM=0)
        memory[63] = {NOP, 4'h4};
        memory[64] = {4'h1, LDI};    // LDI 0x21
        memory[65] = {NOP, 4'h2};
        memory[66] = {NOP, SS};      // SS -> RS0=0x21
        memory[67] = {4'h0, LDI};    // LDI 0x10
        memory[68] = {NOP, 4'h1};
        memory[69] = {NOP, ADD};     // ADD -> ACC=0x31
        memory[70] = {4'h0, LDI};    // LDI 0x10
        memory[71] = {NOP, 4'h1};
        memory[72] = {SUB, XOP};     // SUB -> ACC=0xEF, C=1
        memory[73] = {4'hF, LDI};    // LDI 0xFF
        memory[74] = {NOP, 4'hF};
        memory[75] = {NOP, INC};     // INC -> ACC=0x00, C=1
        memory[76] = {4'h0, LDI};    // LDI 0x00
        memory[77] = {NOP, 4'h0};
        memory[78] = {DEC, XOP};     // DEC -> ACC=0xFF, C=1

        // Phase 2: LK8 logic & shifts (AND, INV, OR, XOR, SHL, SHR)
        memory[79] = {4'hC, LDI};    // LDI 0x3C
        memory[80] = {NOP, 4'h3};
        memory[81] = {NOP, SS};      // SS -> RS0=0x3C
        memory[82] = {4'h0, LDI};    // LDI 0x00
        memory[83] = {NOP, 4'h0};
        memory[84] = {NOP, SHL};     // SHL -> C=0
        memory[85] = {4'h5, LDI};    // LDI 0xA5
        memory[86] = {NOP, 4'hA};
        memory[87] = {NOP, AND};     // AND -> ACC=0x24
        memory[88] = {NOP, OR};      // OR  -> ACC=0x3C
        memory[89] = {XOR, XOP};     // XOR -> ACC=0x00
        memory[90] = {INV, XOP};     // INV -> ACC=0xFF
        memory[91] = {NOP, SHL};     // SHL -> ACC=0xFE, C=1
        memory[92] = {SHR, XOP};     // SHR -> ACC=0x7F, C=0

        // Phase 3: LK16 arithmetic (ADD, SUB, INC, DEC)
        memory[93]  = {4'h6, CFG};   // CFG 0x46 (LK16, CI=0, IMM=0)
        memory[94]  = {NOP, 4'h4};
        memory[95]  = {4'h1, LDI};   // LDI 0x0001
        memory[96]  = {4'h0, 4'h0};
        memory[97]  = {NOP, 4'h0};
        memory[98]  = {NOP, SS};     // SS -> RS0=0x0001
        memory[99]  = {4'hF, LDI};   // LDI 0xFFFF
        memory[100] = {4'hF, 4'hF};
        memory[101] = {NOP, 4'hF};
        memory[102] = {NOP, ADD};    // ADD -> ACC=0x0000, C=1
        memory[103] = {4'h0, LDI};   // LDI 0x0000
        memory[104] = {4'h0, 4'h0};
        memory[105] = {NOP, 4'h0};
        memory[106] = {SUB, XOP};    // SUB -> ACC=0xFFFF, C=1
        memory[107] = {NOP, INC};    // INC -> ACC=0x0000, C=1
        memory[108] = {DEC, XOP};    // DEC -> ACC=0xFFFF, C=1

        // Phase 3: LK16 logic & shifts (AND, INV, OR, XOR, SHL, SHR)
        memory[109] = {4'hF, LDI};   // LDI 0x0F0F
        memory[110] = {4'hF, 4'h0};
        memory[111] = {NOP, 4'h0};
        memory[112] = {NOP, SS};     // SS -> RS0=0x0F0F
        memory[113] = {4'hA, LDI};   // LDI 0xAAAA
        memory[114] = {4'hA, 4'hA};
        memory[115] = {NOP, 4'hA};
        memory[116] = {NOP, AND};    // AND -> ACC=0x0A0A
        memory[117] = {NOP, OR};     // OR  -> ACC=0x0F0F
        memory[118] = {XOR, XOP};    // XOR -> ACC=0x0000
        memory[119] = {INV, XOP};    // INV -> ACC=0xFFFF
        memory[120] = {NOP, SHL};    // SHL -> ACC=0xFFFE, C=1
        memory[121] = {SHR, XOP};    // SHR -> ACC=0x7FFF, C=0

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        // Phase 1 (UL arithmetic)
        validate(2,  1, 16'h0000, 1'b0); // CFG 0x44
        validate(3,  1, 16'h0005, 1'b0); // LDI 0x5
        validate(4,  1, 16'h0000, 1'b0); // SS
        validate(5,  1, 16'h0003, 1'b0); // LDI 0x3
        validate(6,  1, 16'h0008, 1'b0); // ADD
        validate(7,  1, 16'h0003, 1'b0); // LDI 0x3
        validate(8,  1, 16'h000E, 1'b1); // SUB
        validate(9,  1, 16'h000F, 1'b0); // INC
        validate(10, 1, 16'h000E, 1'b0); // DEC
        validate(12, 1, 16'h000E, 1'b0); // CFG 0x4C
        validate(13, 1, 16'h0000, 1'b0); // LDI 0x0
        validate(14, 1, 16'h0005, 1'b0); // SS
        validate(15, 1, 16'h0001, 1'b0); // LDI 0x1
        validate(16, 1, 16'h0003, 1'b0); // ADDI #2
        validate(17, 1, 16'h0001, 1'b0); // LDI 0x1
        validate(19, 0, 16'h000F, 1'b1); // SUBI #2
        validate(21, 1, 16'h000F, 1'b1); // CFG 0xC4
        validate(22, 1, 16'h0001, 1'b1); // LDI 0x1
        validate(23, 1, 16'h0000, 1'b1); // SS
        validate(24, 1, 16'h0000, 1'b1); // LDI 0x0
        validate(25, 1, 16'h0000, 1'b0); // SHL (C=0)
        validate(26, 1, 16'h0001, 1'b0); // LDI 0x1
        validate(27, 1, 16'h0002, 1'b0); // ADD (CI=1, C=0)
        validate(28, 1, 16'h0008, 1'b0); // LDI 0x8
        validate(29, 1, 16'h0000, 1'b1); // SHL (C=1)
        validate(30, 1, 16'h0001, 1'b1); // LDI 0x1
        validate(31, 1, 16'h0003, 1'b0); // ADD (CI=1, C=1)
        validate(32, 1, 16'h0001, 1'b0); // LDI 0x1
        validate(33, 1, 16'h0000, 1'b0); // SUB (CI=1, C=0)
        validate(34, 1, 16'h0008, 1'b0); // LDI 0x8
        validate(35, 1, 16'h0000, 1'b1); // SHL (C=1)
        validate(36, 1, 16'h0001, 1'b1); // LDI 0x1
        validate(37, 1, 16'h000F, 1'b1); // SUB (CI=1, C=1)

        // Phase 1 (UL logic & shifts)
        validate(39, 1, 16'h000F, 1'b1); // CFG 0x44
        validate(40, 1, 16'h0000, 1'b1); // LDI 0x0
        validate(41, 1, 16'h0000, 1'b0); // SHL (C=0)
        validate(42, 1, 16'h000C, 1'b0); // LDI 0xC
        validate(43, 1, 16'h0001, 1'b0); // SS
        validate(44, 1, 16'h000A, 1'b0); // LDI 0xA
        validate(45, 1, 16'h0008, 1'b0); // AND
        validate(46, 1, 16'h000C, 1'b0); // OR
        validate(47, 1, 16'h0000, 1'b0); // XOR
        validate(48, 1, 16'h000F, 1'b0); // INV
        validate(49, 1, 16'h000E, 1'b1); // SHL
        validate(50, 1, 16'h0007, 1'b0); // SHR
        validate(52, 1, 16'h0007, 1'b0); // CFG 0x4C
        validate(53, 1, 16'h0008, 1'b0); // LDI 0x8
        validate(54, 1, 16'h0000, 1'b1); // SHL (C=1)
        validate(55, 1, 16'h0000, 1'b1); // LDI 0x0
        validate(56, 1, 16'h000C, 1'b1); // SS
        validate(57, 1, 16'h0005, 1'b1); // LDI 0x5
        validate(58, 1, 16'h0001, 1'b1); // ANDI #3
        validate(59, 1, 16'h0003, 1'b1); // ORI #2
        validate(61, 0, 16'h0004, 1'b1); // XORI #7

        // Phase 2 (LK8 arithmetic)
        validate(63, 1, 16'h0004, 1'b1); // CFG 0x45
        validate(65, 0, 16'h0021, 1'b1); // LDI 0x21
        validate(66, 1, 16'h0000, 1'b1); // SS
        validate(68, 0, 16'h0010, 1'b1); // LDI 0x10
        validate(69, 1, 16'h0031, 1'b0); // ADD
        validate(71, 0, 16'h0010, 1'b0); // LDI 0x10
        validate(72, 1, 16'h00EF, 1'b1); // SUB
        validate(74, 0, 16'h00FF, 1'b1); // LDI 0xFF
        validate(75, 1, 16'h0000, 1'b1); // INC
        validate(77, 0, 16'h0000, 1'b1); // LDI 0x00
        validate(78, 1, 16'h00FF, 1'b1); // DEC

        // Phase 2 (LK8 logic & shifts)
        validate(80, 0, 16'h003C, 1'b1); // LDI 0x3C
        validate(81, 1, 16'h0021, 1'b1); // SS
        validate(83, 0, 16'h0000, 1'b1); // LDI 0x00
        validate(84, 1, 16'h0000, 1'b0); // SHL (C=0)
        validate(86, 0, 16'h00A5, 1'b0); // LDI 0xA5
        validate(87, 1, 16'h0024, 1'b0); // AND
        validate(88, 1, 16'h003C, 1'b0); // OR
        validate(89, 1, 16'h0000, 1'b0); // XOR
        validate(90, 1, 16'h00FF, 1'b0); // INV
        validate(91, 1, 16'h00FE, 1'b1); // SHL
        validate(92, 1, 16'h007F, 1'b0); // SHR

        // Phase 3 (LK16 arithmetic)
        validate(94, 1, 16'h007F, 1'b0); // CFG 0x46
        validate(97, 0, 16'h0001, 1'b0); // LDI 0x0001
        validate(98, 1, 16'h003C, 1'b0); // SS
        validate(101,0, 16'hFFFF, 1'b0); // LDI 0xFFFF
        validate(102,1, 16'h0000, 1'b1); // ADD
        validate(105,0, 16'h0000, 1'b1); // LDI 0x0000
        validate(106,1, 16'hFFFF, 1'b1); // SUB
        validate(107,1, 16'h0000, 1'b1); // INC
        validate(108,1, 16'hFFFF, 1'b1); // DEC

        // Phase 3 (LK16 logic & shifts)
        validate(111,0, 16'h0F0F, 1'b1); // LDI 0x0F0F
        validate(112,1, 16'h0001, 1'b1); // SS
        validate(115,0, 16'hAAAA, 1'b1); // LDI 0xAAAA
        validate(116,1, 16'h0A0A, 1'b1); // AND
        validate(117,1, 16'h0F0F, 1'b1); // OR
        validate(118,1, 16'h0000, 1'b1); // XOR
        validate(119,1, 16'hFFFF, 1'b1); // INV
        validate(120,1, 16'hFFFE, 1'b1); // SHL
        validate(121,1, 16'h7FFF, 1'b0); // SHR

        $display("ALL ALU TESTS (validations) DONE");
        $finish;
    end

endmodule
