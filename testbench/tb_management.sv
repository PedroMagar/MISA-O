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
        // Each phase padded so the next one starts on a full byte (PC low)
        // ================================================================

        // Phase 1: LDI (UL -> LK8 -> LK16), aligned with NOPs
        memory[1]  = {4'h5, LDI};    // LDI 0x5 -> ACC=0x0005
        memory[2]  = {CFG, XOP};     // XOP CFG
        memory[3]  = {4'h4, 4'hD};   // CFG LK8 -> link=LK8
        memory[4]  = {4'h3, LDI};    // LDI 0x00B3 (aligned)
        memory[5]  = {XOP, 4'hB};    // padding high nibble
        memory[6]  = {4'hE, CFG};     // XOP CFG
        memory[7]  = {NOP, 4'h4};   // CFG LK16 -> link=LK16
        memory[8]  = {4'hE, LDI};    // LDI 0xCAFE (aligned)
        memory[9]  = {4'hA, 4'hF};
        memory[10] = {NOP, 4'hC};    // align next phase

        // Phase 2: CFG + LDI (byte-aligned vs misaligned cases)
        memory[11] = {CFG, XOP};     // CFG LK8 (baseline)
        memory[12] = {4'h4, 4'hD};
        memory[13] = {LDI, NOP};     // opcode at high nib (unaligned LDI 0x0091)
        memory[14] = {4'h9, 4'h1};
        memory[15] = {CFG, XOP};     // CFG UL
        memory[16] = {4'h4, 4'hC};
        memory[17] = {4'h6, LDI};    // LDI 0x6 (UL)
        memory[18] = {CFG, XOP};     // CFG LK16
        memory[19] = {4'h4, 4'hE};
        memory[20] = {4'h7, LDI};    // LDI 0x1357 (aligned)
        memory[21] = {4'h3, 4'h5};
        memory[22] = {NOP, 4'h1};

        // Phase 3: RACC + RRS (UL -> LK8 -> LK16) with RS0 capture via LK16+SS
        memory[23] = {SS , NOP};     // seed RS0 with ACC (full swap in LK16)
        memory[24] = {CFG, XOP};     // CFG UL
        memory[25] = {4'h4, 4'hC};
        memory[26] = {4'hA, LDI};    // LDI 0xA (UL)
        memory[27] = {RACC, NOP};    // rotate ACC nibbles (UL)
        memory[28] = {RRS , XOP};    // RRS (UL rotate RS0 by nibble) -> RS0=0x7135
        memory[29] = {CFG, XOP};     // hop to LK16 to pull RS0 into ACC
        memory[30] = {4'h4, 4'hE};
        memory[31] = {SS , NOP};     // SS (LK16) ACC=RS0=0x7135, RS0=0xA000
        memory[32] = {CFG, XOP};     // CFG LK8
        memory[33] = {4'h4, 4'hD};
        memory[34] = {4'h2, LDI};    // LDI 0x00D2 (aligned)
        memory[35] = {NOP, 4'hD};
        memory[36] = {RACC, NOP};    // rotate ACC by link width (LK8 byte swap)
        memory[37] = {RRS , XOP};    // RRS (LK8 swap bytes in RS0) -> RS0=0x00A0
        memory[38] = {CFG, XOP};     // hop to LK16 to pull RS0 into ACC
        memory[39] = {4'h4, 4'hE};
        memory[40] = {SS , NOP};     // SS (LK16) ACC=RS0=0x00A0, RS0=0xD2A0
        memory[41] = {4'hB, LDI};    // LDI 0x89AB (aligned)
        memory[42] = {4'h9, 4'hA};
        memory[43] = {NOP, 4'h8};
        memory[44] = {RACC, NOP};    // RACC -> NOP in LK16
        memory[45] = {RRS , XOP};    // RRS -> NOP in LK16

        // Phase 4: SS + RSS (UL -> LK8 -> LK16)
        memory[46] = {CFG, XOP};     // CFG UL
        memory[47] = {4'h4, 4'hC};
        memory[48] = {4'h7, LDI};    // LDI 0x7 (UL)
        memory[49] = {SS , NOP};     // SS (UL swap low nibble with RS0)
        memory[50] = {RSS , NOP};    // RSS (swap RS0/RS1)
        memory[51] = {CFG, XOP};     // CFG LK8
        memory[52] = {4'h4, 4'hD};
        memory[53] = {4'h6, LDI};    // LDI 0x00B6 (aligned)
        memory[54] = {NOP, 4'hB};
        memory[55] = {SS , NOP};     // SS (LK8 swap low byte with RS0)
        memory[56] = {RSS , NOP};    // RSS (swap RS0/RS1)
        memory[57] = {CFG, XOP};     // CFG LK16
        memory[58] = {4'h4, 4'hE};
        memory[59] = {4'h4, LDI};    // LDI 0x2244 (aligned)
        memory[60] = {4'h2, 4'h4};
        memory[61] = {NOP, 4'h2};
        memory[62] = {SS , NOP};     // SS (LK16 full swap ACC/RS0)
        memory[63] = {RSS , NOP};    // RSS (swap RS0/RS1)

        // Phase 5: SA + RSA (UL -> LK8 -> LK16)
        memory[64] = {CFG, XOP};     // CFG UL
        memory[65] = {4'h4, 4'hC};
        memory[66] = {4'hC, LDI};    // LDI 0xC (UL)
        memory[67] = {SA , XOP};     // SA (swap ACC/RA0)
        memory[68] = {RSA, XOP};     // RSA (swap RA0/RA1)
        memory[69] = {CFG, XOP};     // CFG LK8
        memory[70] = {4'h4, 4'hD};
        memory[71] = {4'hE, LDI};    // LDI 0x00DE (aligned)
        memory[72] = {NOP, 4'hD};
        memory[73] = {SA , XOP};     // SA (swap ACC/RA0)
        memory[74] = {RSA, XOP};     // RSA (swap RA0/RA1)
        memory[75] = {CFG, XOP};     // CFG LK16
        memory[76] = {4'h4, 4'hE};
        memory[77] = {4'hD, LDI};    // LDI 0xABCD (aligned)
        memory[78] = {4'hB, 4'hC};
        memory[79] = {NOP, 4'hA};
        memory[80] = {SA , XOP};     // SA (swap ACC/RA0)
        memory[81] = {RSA, XOP};     // RSA (swap RA0/RA1)

        // Phase 6: Mixed
        memory[82]  = {CFG , XOP};   // CFG LK16
        memory[83]  = {4'h4, 4'hE};  // imm1=4 / imm0=E  (CFG=0x4E)

        memory[84]  = {4'hA, LDI};   // LDi 0xEBA0                      imm0=A / LDI16 start
        memory[85]  = {4'hA, 4'hB};  //                                 imm2=A / imm1=B
        memory[86]  = {XOP , 4'hE};  // imm3=E / XOP (SA)
        memory[87]  = {XOP , SA };   // SA -> ACC=0 / XOP (RSA)
        memory[88]  = {XOP , RSA};   // RSA -> RA1=EBA0 / XOP (CFG UL)

        memory[89]  = {4'hC, CFG};   // imm0=C (0x4C) / CFG
        memory[90]  = {LDI , 4'h4};  // imm1=4 / LDI UL 0xE
        memory[91]  = {RACC, 4'hE};  // imm0=E / RACC UL
        memory[92]  = {4'hF, LDI};   // imm0=F / LDI UL 0xF
        memory[93]  = {NOP , RACC};  // RACC UL / XOP (CFG LK8)

        memory[94]  = {CFG, XOP };   // CFG LK8
        memory[95]  = {4'h4, 4'hD};  // 
        memory[96]  = {4'hE, LDI};   // LDi 0xBE
        memory[97]  = {RACC, 4'hB};  // RACC
        memory[98]  = {SA  , XOP};   // SA -> RA0=BEFE 
        memory[99]  = {RSA , XOP};   // RSA -> RA1=BEFE 
        memory[100] = {SA  , XOP};   // XOP (SA) / SA -> ACC=BEFE
        memory[101] = {SA  , XOP};   // XOP (RSA) / SA -> ACC=0, RA0=BEFE
        memory[102] = {RSA , XOP};   // XOP (CFG LK16) / RSA -> RA1=EBA0

        memory[103] = {CFG , XOP};   // XOP (CFG LK16) / CFG
        memory[104] = {4'h4, 4'hE};  // imm1=4 / imm0=E  (0x4E)
        memory[105] = {4'hB, LDI};   // imm0=B / LDI16 0xFEEB
        memory[106] = {4'hE, 4'hE};  // imm2=E / imm1=E
        memory[107] = {SS  , 4'hF};  // imm3=F / SS -> RS0=FEEB
        memory[108] = {RSS , RSS};   // RSS (swap) / RSS (swap back)
        memory[109] = {SS  , SS };   // SS -> ACC=FEEB / SS -> RS0=FEEB

        memory[110] = {CFG , XOP};   // XOP (CFG LK8) / CFG
        memory[111] = {4'h4, 4'hD};  // imm1=4 / imm0=D  (0x4D)
        memory[112] = {RRS , XOP};   // XOP (RRS) / RRS -> RS0 rot FEEB->EBFE
        memory[113] = {4'h0, LDI};   // imm0=0 / LDI8 0xA0
        memory[114] = {RACC, 4'hA};  // imm1=A / RACC LK8 (ACC=A000)
        memory[115] = {4'hA, LDI};   // imm0=A / LDI8 0xCA
        memory[116] = {RACC, 4'hC};  // imm1=C / RACC LK8 (ACC=CAA0)
        memory[117] = {4'hE, LDI};   // imm0=E / LDI8 0xFE
        memory[118] = {SS  , 4'hF};  // imm1=F / SS LK8 final -> ACC=CAFE, RS0=EBA0
        memory[119] = {CFG , XOP};   // XOP (CFG LK8) / CFG
        memory[83]  = {4'h4, 4'hE};  // imm1=4 / imm0=E  (CFG=0x4E)
        memory[121] = {NOP , SS  };  // imm1=F / SS LK8 final -> ACC=CAFE, RS0=EBA0

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        // Phase 1 validations
        validate( 1, 1, 16'h0005, 1'b0); // LDI 0x5     -> ACC=0x0005
        validate( 3, 1, 16'h0005, 1'b0); // CFG LK8     -> link=LK8, ACC=0x0005
        validate( 5, 0, 16'h00B3, 1'b0); // LDI 0x00B3  -> ACC=0x00B3
        validate( 7, 1, 16'h00B3, 1'b0); // CFG LK16    -> link=LK16, ACC=0x00B3
        validate(10, 0, 16'hCAFE, 1'b0); // LDI 0xCAFE  -> ACC=0xCAFE

        // Phase 2 validations
        validate(12, 1, 16'hCAFE, 1'b0); // CFG LK8     -> link=LK8, ACC=0xCAFE
        validate(14, 1, 16'hCA91, 1'b0); // LDI 0x0091  -> ACC=0xCA91                           (unaligned)
        validate(16, 1, 16'hCA91, 1'b0); // CFG UL      -> link=UL, ACC=0xCA91
        validate(17, 1, 16'hCA96, 1'b0); // LDI 0x6     -> ACC=0xCA96
        validate(19, 1, 16'hCA96, 1'b0); // CFG LK16    -> link=LK16, ACC=0xCA96
        validate(22, 0, 16'h1357, 1'b0); // LDI 0x1357  -> ACC=0x1357

        // Phase 3 validations (RACC + RRS with RS0 capture)
        validate(23, 1, 16'h0000, 1'b0); // SS          -> ACC=0x0000, RS0=0x1357               (LK16)
        validate(25, 1, 16'h0000, 1'b0); // CFG UL      -> link=UL
        validate(26, 1, 16'h000A, 1'b0); // LDI 0xA     -> ACC=0x000A
        validate(27, 1, 16'hA000, 1'b0); // RACC        -> ACC=0xA000                           (UL nibble swap)
        validate(28, 1, 16'hA000, 1'b0); // RRS         -> ACC=0xA000, RS0=0x7135               (UL nibble swap)
        validate(30, 1, 16'hA000, 1'b0); // CFG LK16    -> link=LK16
        validate(31, 1, 16'h7135, 1'b0); // SS          -> ACC=0x7135 (captura RS0), RS0=0xA000
        validate(33, 1, 16'h7135, 1'b0); // CFG LK8     -> link=LK8
        validate(35, 0, 16'h71D2, 1'b0); // LDI 0x00D2  -> ACC=0x71D2 (upper byte preserved)
        validate(36, 1, 16'hD271, 1'b0); // RACC        -> ACC=0xD271                           (LK8 byte swap)
        validate(37, 1, 16'hD271, 1'b0); // RRS         -> ACC=0xD271, RS0=0x00A0               (LK8 byte swap)
        validate(39, 1, 16'hD271, 1'b0); // CFG LK16    -> link=LK16
        validate(40, 1, 16'h00A0, 1'b0); // SS          -> ACC=0x00A0 (captura RS0), RS0=0xD271
        validate(43, 0, 16'h89AB, 1'b0); // LDI 0x89AB  -> ACC=0x89AB
        validate(44, 1, 16'h89AB, 1'b0); // RACC        -> ACC=0x89AB                           (LK16 no-op)
        validate(45, 1, 16'h89AB, 1'b0); // RRS         -> ACC=0x89AB, RS0=0xD2A0               (LK16 no-op)

        // Phase 4 validations (SS + RSS)
        validate(47, 1, 16'h89AB, 1'b0); // CFG UL      -> link=UL
        validate(48, 1, 16'h89A7, 1'b0); // LDI 0x7     -> ACC=0x89A7
        validate(49, 1, 16'h89A1, 1'b0); // SS          -> ACC=0x89A1, RS0=0xD277               (UL low-nibble swap)
        validate(50, 1, 16'h89A1, 1'b0); // RSS         -> ACC=0x89A1, RS0=0x0000, RS1=0xD277
        validate(52, 1, 16'h89A1, 1'b0); // CFG LK8     -> link=LK8 (ACC unchanged)
        validate(54, 0, 16'h89B6, 1'b0); // LDI 0x00B6  -> ACC=0x89B6
        validate(55, 1, 16'h8900, 1'b0); // SS          -> ACC=0x8900, RS0=0x00B6               (LK8)
        validate(56, 1, 16'h8900, 1'b0); // RSS         -> ACC=0x8900, RS0=0xD277, RS1=0x00B6
        validate(58, 1, 16'h8900, 1'b0); // CFG LK16    -> link=LK16
        validate(61, 0, 16'h2244, 1'b0); // LDI 0x2244  -> ACC=0x2244
        validate(62, 1, 16'hD277, 1'b0); // SS          -> ACC=0xD277, RS0=0x2244               (LK16)
        validate(63, 1, 16'hD277, 1'b0); // RSS         -> ACC=0xD277, RS0=0x00B6, RS1=0x2244

        // Phase 5 validations (SA + RSA)
        validate(65, 1, 16'hD277, 1'b0); // CFG UL      -> link=UL
        validate(66, 1, 16'hD27C, 1'b0); // LDI 0xC     -> ACC=0xD27C
        validate(67, 1, 16'h0000, 1'b0); // SA          -> ACC=0x0000, RA0=0xD27C
        validate(68, 1, 16'h0000, 1'b0); // RSA         -> ACC=0x0000, RA0=0x0000, RA1=0xD27C
        validate(70, 1, 16'h0000, 1'b0); // CFG LK8     -> link=LK8
        validate(72, 0, 16'h00DE, 1'b0); // LDI 0x00DE  -> ACC=0x00DE
        validate(73, 1, 16'h0000, 1'b0); // SA          -> ACC=0x0000, RA0=0x00DE
        validate(74, 1, 16'h0000, 1'b0); // RSA         -> ACC=0x0000, RA0=0xD27C, RA1=0x00DE
        validate(76, 1, 16'h0000, 1'b0); // CFG LK16    -> link=LK16
        validate(79, 0, 16'hABCD, 1'b0); // LDI 0xABCD  -> ACC=0xABCD
        validate(80, 1, 16'hD27C, 1'b0); // SA          -> ACC=0xD27C, RA0=0xABCD
        validate(81, 1, 16'hD27C, 1'b0); // RSA         -> ACC=0xD27C, RA0=0x00DE, RA1=0xABCD

        // Phase 6 validations (nibble-packed)
        validate(82,  1, 16'hD27C, 1'b0); // CFG LK16 -> ACC=0xD27C
        validate(109, 0, 16'hFEEB, 1'b0); // SA
        validate(112, 0, 16'hFEEB, 1'b0); // 
        validate(112, 1, 16'hEBFE, 1'b0); // RRS        -> ACC=0xEBFE
        validate(121, 1, 16'hEBA0, 1'b0); // SS

        $display("========================");
        $display("= MANAGEMENT TEST DONE =");
        $display("=     SUCCESSFULLY     =");
        $display("========================");
        $finish;
    end

endmodule
