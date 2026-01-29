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

    initial begin : watchdog
        int cycle_count = 0;
        int cycle_max = 500;
        int count_down = 10;
        int threshold = cycle_max - count_down;
        while (cycle_count < cycle_max) begin
            @(negedge clk);
            cycle_count++;
            if(cycle_count > threshold) $display("THE FINAL COUNT DOWN %2d :: ACC: %h :: CPU_OUT: %h :: MEM_ADDR: %3d :: MEM_DATA: %h", (threshold - cycle_count + count_down), test_data, mem_data_out, mem_addr, memory[mem_addr]);
        end
        $error("\n\nWATCHDOG TIMEOUT: simulation exceeded 500 cycles (possible infinite loop)\n\nACC: 0x%h\nAddress: %d\n", test_data, mem_addr);
        $finish;
    end

    always @(posedge clk) begin
        if (mem_enable_write) begin
            memory[mem_addr] <= mem_data_out;
            $display("MEM[%02h] <- %02h", mem_addr, mem_data_out);
        end
    end

    always @(*) begin
        // Keep instruction bus always driven; core fetches once per byte.
        mem_data_in = memory[mem_addr];
    end

    // Validation task
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
        // Test Sequence (Control)
        // ================================================================

        // Phase 1: UL sanity + BEQZ (imm4)
        memory[1]  = {4'h4, CFG};   // CFG 0x04 (UL, BW=imm4, BRS=0, IMM=0, CI=0)
        memory[2]  = {NOP, 4'h0};   // cfg[7:4] + pad
        memory[3]  = {4'h5, LDI};   // ACC=5
        memory[4]  = {NOP, NOP};    // NOP sanity
        memory[5]  = {4'h0, LDI};   // ACC=0
        memory[6]  = {4'h4, BEQZ};  // BEQZ +4 nibbles (taken)
        memory[7]  = {4'hF, LDI};   // skipped
        memory[8]  = {4'h1, LDI};   // target ACC=1
        memory[9]  = {4'h4, BEQZ};  // BEQZ +4 nibbles (not taken)
        memory[10] = {4'h2, LDI};   // ACC=2

        // Phase 2: BC (imm4) with carry clear/set
        memory[11] = {4'h0, LDI};   // ACC=0
        memory[12] = {NOP, SHL};    // SHL -> C=0
        memory[13] = {BC, XOP};     // XOP BC (not taken, C=0)
        memory[14] = {LDI, 4'h2};   // imm=2 + LDI opcode (0x3)
        memory[15] = {LDI, 4'h3};   // imm=3 + LDI opcode (0x8)
        memory[16] = {SHL, 4'h8};   // imm=8 + SHL -> C=1
        memory[17] = {BC, XOP};     // XOP BC (taken, C=1)
        memory[18] = {LDI, 4'h2};   // imm=2 + LDI opcode (skipped)
        memory[19] = {LDI, 4'hF};   // imm=F + LDI opcode (target 0x4)
        memory[20] = {NOP, 4'h4};   // imm=4 + pad

        // Phase 3: BW=imm8 (BEQZ taken, BC not taken)
        memory[21] = {4'h4, CFG};   // CFG 0x44 (UL, BW=imm8)
        memory[22] = {NOP, 4'h4};
        memory[23] = {4'h0, LDI};   // ACC=0
        memory[24] = {4'h2, BEQZ};  // BEQZ imm8 +0x02 (taken)
        memory[25] = {LDI, 4'h0};   // imm high=0 + LDI opcode (skipped)
        memory[26] = {LDI, 4'hF};   // imm=F (skipped) + LDI opcode (target)
        memory[27] = {NOP, 4'h6};   // imm=6 + pad
        memory[28] = {4'h0, LDI};   // ACC=0
        memory[29] = {NOP, SHL};    // SHL -> C=0
        memory[30] = {BC, XOP};     // XOP BC imm8 (not taken)
        memory[31] = {4'h0, 4'h4};  // imm8 low=4, high=0 (nibble offset)
        memory[32] = {4'h7, LDI};   // ACC=7

        // Phase 4: BRS=1 scaling (imm4)
        memory[33] = {4'h4, CFG};   // CFG 0x24 (UL, BW=imm4, BRS=1)
        memory[34] = {NOP, 4'h2};
        memory[35] = {4'h0, LDI};   // ACC=0
        memory[36] = {4'h2, BEQZ};  // BEQZ +2 nibbles (scaled <<2)
        memory[37] = {4'hF, LDI};   // skipped
        memory[38] = {NOP, NOP};    // pad
        memory[39] = {4'h9, LDI};   // target ACC=9

        // Phase 5: LK16 JAL/JMP (RA1 link + jump)
        memory[40] = {4'h6, CFG};   // CFG 0x06 (LK16, BW=imm4)
        memory[41] = {NOP, 4'h0};
        memory[42] = {4'h4, LDI};   // LDI 0x0064 (JAL target pc=100)
        memory[43] = {4'h0, 4'h6};
        memory[44] = {NOP, 4'h0};
        memory[45] = {SA , XOP};    // SA -> RA0=0x0064
        memory[46] = {NOP, JAL};    // JAL (link to RA1)
        memory[47] = {NOP, INC};    // fallthrough INC (should be skipped)
        memory[48] = {NOP, NOP};
        memory[49] = {NOP, NOP};
        memory[50] = {NOP, NOP};    // JAL target entry
        memory[51] = {RSA, XOP};    // RSA (RA0<->RA1)
        memory[52] = {SA , XOP};    // SA -> ACC=RA1
        memory[53] = {4'hE, LDI};   // LDI 0x007E (JMP target pc=126)
        memory[54] = {4'h0, 4'h7};
        memory[55] = {NOP, 4'h0};
        memory[56] = {SA , XOP};    // SA -> RA0=0x007E
        memory[57] = {4'h0, LDI};   // LDI 0x0000
        memory[58] = {4'h0, 4'h0};
        memory[59] = {NOP, 4'h0};
        memory[60] = {JMP, XOP};    // XOP JMP -> pc=RA0
        memory[61] = {NOP, INC};    // fallthrough INC (should be skipped)
        memory[62] = {NOP, NOP};
        memory[63] = {NOP, NOP};    // JMP target entry

        // Phase 6: Negative control-flow (BEQZ, BC, JMP, JAL) — machine-oriented
        // Enter LK16
        memory[64]  = {4'h6, CFG};   // CFG 0x06 (LK16, BW=imm4)
        memory[65]  = {NOP, 4'h0};

        // --- Test 1: BEQZ negative (taken once) ---
        memory[66]  = {4'h0, LDI};   // LDI 0x0000
        memory[67]  = {4'h0, 4'h0};
        memory[68]  = {NOP, 4'h0};
        memory[69]  = {4'h5, BEQZ};  // BEQZ +5 -> @74 (enter test, skip taken block)

        memory[70]  = {4'h2, LDI};   // LDI 0x0002 (marker)
        memory[71]  = {4'h0, 4'h0};
        memory[72]  = {NOP, 4'h0};
        memory[73]  = {NOP, SHR};    // SHR (updates Z)

        memory[74]  = {4'hC, BEQZ};  // BEQZ -4 -> @70 (taken once, then fallthrough)

        // --- Test 2: BC negative (taken once) ---
        memory[75]  = {NOP, SHR};    // SHR (C=1, ACC=0) + updates Z
        memory[76]  = {4'h6, BEQZ};  // BEQZ +6 -> @82 (enter test, skip taken block)

        memory[77]  = {4'h0, LDI};   // LDI 0x4000 (marker)
        memory[78]  = {4'h0, 4'h0};
        memory[79]  = {NOP, 4'h4};
        memory[80]  = {NOP, SHL};    // SHL (clears C=0 for anti-loop, ACC becomes 0x8000)

        memory[81]  = {NOP, NOP};    // pad
        memory[82]  = {BC, XOP};     // XOP BC (branch backward once when C=1)
        memory[83]  = {4'hB, NOP};   // imm4=-5 (to @77), safe filler

        // --- Test 3: JMP negative (absolute backward), entered via BC ---
        memory[84]  = {NOP, SHL};    // SHL (ACC=0x8000 -> C=1, ACC=0)

        // RA0 = PC(test_3_jmp_taken) = 2*91 = 0x00B6
        memory[85]  = {4'h6, LDI};   // LDI 0x00B6
        memory[86]  = {4'h0, 4'hB};
        memory[87]  = {NOP, 4'h0};
        memory[88]  = {SA , XOP};    // SA -> RA0=0x00B6

        memory[89]  = {BC, XOP};     // enter test_3_jmp (forward)
        memory[90]  = {4'h7, NOP};   // imm4=+7 -> @96

        // test_3_jmp_taken @91
        memory[91]  = {4'h3, LDI};   // LDI 0x0003 (landing marker)
        memory[92]  = {4'h0, 4'h0};
        memory[93]  = {NOP, 4'h0};

        memory[94]  = {BC, XOP};     // "exit" via BC (uses C=1)
        memory[95]  = {4'h3, NOP};   // imm4=+3 -> @97

        // test_3_jmp @96
        memory[96]  = {JMP, XOP};    // JMP -> PC=RA0 (back to @91)

        // test_3_jmp_end @97

        // --- Test 4: JAL negative + link validation, entered via BC ---
        // RA0 = PC(test_4_jal_taken) = 2*103 = 0x00CE
        memory[97]  = {4'hE, LDI};   // LDI 0x00CE
        memory[98]  = {4'h0, 4'hC};
        memory[99]  = {NOP, 4'h0};
        memory[100] = {SA , XOP};    // SA -> RA0=0x00CE

        memory[101] = {BC, XOP};     // enter test_4_jal (forward)
        memory[102] = {4'h6, NOP};   // imm4=+6 -> @108

        // test_4_jal_taken @103
        memory[103] = {4'h4, LDI};   // LDI 0x0004 (marker)
        memory[104] = {4'h0, 4'h0};
        memory[105] = {NOP, 4'h0};

        memory[106] = {BC, XOP};     // exit via BC (uses C=1)
        memory[107] = {4'h2, NOP};   // imm4=+2 -> @109

        // test_4_jal @108
        memory[108] = {NOP, JAL};    // JAL -> PC=RA0, RA1=link

        // test_4_jal_end @109
        memory[109] = {NOP, NOP};    // checkpoint (validate marker before compute)
        memory[110] = {RSA, XOP};    // RSA
        memory[111] = {SA , XOP};    // SA -> ACC = RA1 (link)
        memory[112] = {NOP, NOP};    // pad/checkpoint

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        // Phase 1 (UL sanity + BEQZ imm4)
        validate(3,  1, 16'h0005, 1'b0); // LDI 0x5
        validate(4,  1, 16'h0005, 1'b0); // NOP (ACC unchanged)
        validate(5,  1, 16'h0000, 1'b0); // LDI 0x0
        validate(8,  1, 16'h0001, 1'b0); // BEQZ taken -> LDI 0x1
        validate(10, 1, 16'h0002, 1'b0); // BEQZ not taken -> LDI 0x2

        // Phase 2 (BC imm4, C=0 then C=1)
        validate(11, 1, 16'h0000, 1'b0); // LDI 0x0
        validate(12, 1, 16'h0000, 1'b0); // SHL -> C=0
        validate(15, 0, 16'h0003, 1'b0); // BC not taken -> LDI 0x3
        validate(16, 1, 16'h0000, 1'b1); // SHL -> C=1
        validate(20, 0, 16'h0004, 1'b1); // BC taken -> LDI 0x4

        // Phase 3 (BW=imm8)
        validate(23, 1, 16'h0000, 1'b1); // LDI 0x0
        validate(27, 0, 16'h0006, 1'b1); // BEQZ imm8 taken -> LDI 0x6
        validate(29, 1, 16'h0000, 1'b0); // SHL -> C=0
        validate(32, 1, 16'h0007, 1'b0); // BC imm8 not taken -> LDI 0x7

        // Phase 4 (BRS=1 scaling)
        validate(35, 1, 16'h0000, 1'b0); // LDI 0x0
        validate(39, 1, 16'h0009, 1'b0); // BEQZ scaled -> LDI 0x9

        // Phase 5 (LK16 JAL/JMP)
        validate(50, 1, 16'h0000, 1'b0); // JAL target entry (ACC unchanged)
        validate(52, 1, 16'h005D, 1'b0); // RA1 link via RSA+SA
        validate(63, 1, 16'h0000, 1'b0); // JMP target entry (ACC unchanged)

        // Phase 6 (negative control-flow)
        // Philosophy: validate at arrival (cycle 0) before the next instruction overwrites ACC.
        validate(75,  0, 16'h0001, 1'b0); // Test 1 completed: marker path executed (after SHR, ACC=1)
        validate(84,  0, 16'h8000, 1'b0); // Test 2 completed: after LDI 0x4000 + SHL, ACC=0x8000, C=0
        validate(97,  0, 16'h0003, 1'b1); // Test 3 completed: JMP landed on marker (ACC=3) and exited via BC
        validate(109, 0, 16'h0004, 1'b1); // Test 4 marker reached (ACC=4) before link is moved into ACC
        validate(112, 0, 16'h00D9, 1'b1); // Link check: JAL at byte[108] low nibble => link = 2*108 + 1 = 0x00D9


        $display("CONTROL TEST DONE");
        $finish;
    end

endmodule
