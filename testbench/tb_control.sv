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
                // Sample mem_addr right after the negedge update so we catches the fetch.
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

        memory[1]   = {4'h0, CFG};   // CFG 0
        memory[2]   = {NOP, 4'h0};
        memory[3]   = {4'h5, LDI};   // LDI 5
        memory[4]   = {4'h0, SS};   // SS
        memory[5]   = {4'h5, LDI};   // LDI 5
        memory[6]   = {4'h0, XOP};   // XOP
        memory[7]   = {4'h0, CMP};   // CMP
        memory[8]   = {4'h1, BRC};   // BRC EQ, L_EQ_T
        memory[9]   = 8'h02;
        memory[10]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_EQ_T ---
        memory[11]   = {4'h2, BRC};   // BRC NE, L_NE_T
        memory[12]   = 8'h06;
        memory[13]   = {4'h1, LDI};   // LDI 1
        memory[14]   = {4'h0, BRC};   // BRC AL, L_NE_END
        memory[15]   = 8'h02;

        // --- LABEL: L_NE_T ---
        memory[16]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_NE_END ---
        memory[17]   = {4'h4, LDI};   // LDI 4
        memory[18]   = {4'h0, SS};   // SS
        memory[19]   = {4'h5, LDI};   // LDI 5
        memory[20]   = {4'h0, XOP};   // XOP
        memory[21]   = {4'h0, CMP};   // CMP
        memory[22]   = {4'h1, BRC};   // BRC EQ, L_EQ_T2
        memory[23]   = 8'h06;
        memory[24]   = {4'h2, LDI};   // LDI 2
        memory[25]   = {4'h0, BRC};   // BRC AL, L_EQ_END2
        memory[26]   = 8'h02;

        // --- LABEL: L_EQ_T2 ---
        memory[27]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_EQ_END2 ---
        memory[28]   = {4'h2, BRC};   // BRC NE, L_NE_T2
        memory[29]   = 8'h02;
        memory[30]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_NE_T2 ---
        memory[31]   = {4'h2, LDI};   // LDI 2
        memory[32]   = {4'h0, SS};   // SS
        memory[33]   = {4'hF, LDI};   // LDI 15
        memory[34]   = {4'h0, ADD};   // ADD
        memory[35]   = {4'h3, BRC};   // BRC CS, L_CS_T
        memory[36]   = 8'h02;
        memory[37]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_CS_T ---
        memory[38]   = {4'h4, BRC};   // BRC CC, L_CC_T
        memory[39]   = 8'h06;
        memory[40]   = {4'h3, LDI};   // LDI 3
        memory[41]   = {4'h0, BRC};   // BRC AL, L_CC_END
        memory[42]   = 8'h02;

        // --- LABEL: L_CC_T ---
        memory[43]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_CC_END ---
        memory[44]   = {4'h2, LDI};   // LDI 2
        memory[45]   = {4'h0, SS};   // SS
        memory[46]   = {4'h2, LDI};   // LDI 2
        memory[47]   = {4'h0, ADD};   // ADD
        memory[48]   = {4'h3, BRC};   // BRC CS, L_CS_T2
        memory[49]   = 8'h06;
        memory[50]   = {4'h4, LDI};   // LDI 4
        memory[51]   = {4'h0, BRC};   // BRC AL, L_CS_END2
        memory[52]   = 8'h02;

        // --- LABEL: L_CS_T2 ---
        memory[53]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_CS_END2 ---
        memory[54]   = {4'h4, BRC};   // BRC CC, L_CC_T2
        memory[55]   = 8'h02;
        memory[56]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_CC_T2 ---
        memory[57]   = {4'h0, LDI};   // LDI 0
        memory[58]   = {4'h0, SS};   // SS
        memory[59]   = {4'h8, LDI};   // LDI 8
        memory[60]   = {4'h0, OR};   // OR
        memory[61]   = {4'h5, BRC};   // BRC MI, L_MI_T
        memory[62]   = 8'h02;
        memory[63]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_MI_T ---
        memory[64]   = {4'h6, BRC};   // BRC PL, L_PL_T
        memory[65]   = 8'h06;
        memory[66]   = {4'h5, LDI};   // LDI 5
        memory[67]   = {4'h0, BRC};   // BRC AL, L_PL_END
        memory[68]   = 8'h02;

        // --- LABEL: L_PL_T ---
        memory[69]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_PL_END ---
        memory[70]   = {4'h0, LDI};   // LDI 0
        memory[71]   = {4'h0, SS};   // SS
        memory[72]   = {4'h7, LDI};   // LDI 7
        memory[73]   = {4'h0, OR};   // OR
        memory[74]   = {4'h5, BRC};   // BRC MI, L_MI_T2
        memory[75]   = 8'h06;
        memory[76]   = {4'h6, LDI};   // LDI 6
        memory[77]   = {4'h0, BRC};   // BRC AL, L_MI_END2
        memory[78]   = 8'h02;

        // --- LABEL: L_MI_T2 ---
        memory[79]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_MI_END2 ---
        memory[80]   = {4'h6, BRC};   // BRC PL, L_PL_T2
        memory[81]   = 8'h02;
        memory[82]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_PL_T2 ---
        memory[83]   = {4'h1, LDI};   // LDI 1
        memory[84]   = {4'h0, SS};   // SS
        memory[85]   = {4'h7, LDI};   // LDI 7
        memory[86]   = {4'h0, ADD};   // ADD
        memory[87]   = {4'h7, BRC};   // BRC VS, L_VS_T
        memory[88]   = 8'h02;
        memory[89]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_VS_T ---
        memory[90]   = {4'h8, BRC};   // BRC VC, L_VC_T
        memory[91]   = 8'h06;
        memory[92]   = {4'h7, LDI};   // LDI 7
        memory[93]   = {4'h0, BRC};   // BRC AL, L_VC_END
        memory[94]   = 8'h02;

        // --- LABEL: L_VC_T ---
        memory[95]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_VC_END ---
        memory[96]   = {4'h1, LDI};   // LDI 1
        memory[97]   = {4'h0, SS};   // SS
        memory[98]   = {4'h3, LDI};   // LDI 3
        memory[99]   = {4'h0, ADD};   // ADD
        memory[100]   = {4'h7, BRC};   // BRC VS, L_VS_T2
        memory[101]   = 8'h06;
        memory[102]   = {4'h8, LDI};   // LDI 8
        memory[103]   = {4'h0, BRC};   // BRC AL, L_VS_END2
        memory[104]   = 8'h02;

        // --- LABEL: L_VS_T2 ---
        memory[105]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_VS_END2 ---
        memory[106]   = {4'h8, BRC};   // BRC VC, L_VC_T2
        memory[107]   = 8'h02;
        memory[108]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_VC_T2 ---
        memory[109]   = {4'h4, LDI};   // LDI 4
        memory[110]   = {4'h0, SS};   // SS
        memory[111]   = {4'h5, LDI};   // LDI 5
        memory[112]   = {4'h0, XOP};   // XOP
        memory[113]   = {4'h0, CMP};   // CMP
        memory[114]   = {4'h9, BRC};   // BRC HI, L_HI_T
        memory[115]   = 8'h02;
        memory[116]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_HI_T ---
        memory[117]   = {4'hA, BRC};   // BRC LS, L_LS_T
        memory[118]   = 8'h06;
        memory[119]   = {4'h9, LDI};   // LDI 9
        memory[120]   = {4'h0, BRC};   // BRC AL, L_LS_E
        memory[121]   = 8'h02;

        // --- LABEL: L_LS_T ---
        memory[122]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_LS_E ---
        memory[123]   = {4'hB, BRC};   // BRC GE, L_GE_T
        memory[124]   = 8'h02;
        memory[125]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_GE_T ---
        memory[126]   = {4'hC, BRC};   // BRC LT, L_LT_T
        memory[127]   = 8'h06;
        memory[128]   = {4'hA, LDI};   // LDI 10
        memory[129]   = {4'h0, BRC};   // BRC AL, L_LT_E
        memory[130]   = 8'h02;

        // --- LABEL: L_LT_T ---
        memory[131]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_LT_E ---
        memory[132]   = {4'hD, BRC};   // BRC GT, L_GT_T
        memory[133]   = 8'h02;
        memory[134]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_GT_T ---
        memory[135]   = {4'hE, BRC};   // BRC LE, L_LE_T
        memory[136]   = 8'h06;
        memory[137]   = {4'hB, LDI};   // LDI 11
        memory[138]   = {4'h0, BRC};   // BRC AL, L_LE_E
        memory[139]   = 8'h02;

        // --- LABEL: L_LE_T ---
        memory[140]   = {4'h0, LDI};   // LDI 0

        // --- LABEL: L_LE_E ---
        memory[141]   = {4'hF, LDI};   // LDI 15

        // --- LABEL: END_TESTS ---
        // Total bytes used: 141
        // END_TESTS byte address: 142

        // ================================================================
        // Phase 6: Negative Branches (Backwards loop test)
        // LDI E -> INC (F) -> BRC NE (-6) -> INC (0) -> BRC NE (falls through)
        memory[150] = {4'hE, LDI};   // ACC=E
        
        // Loop entry
        memory[151] = {NOP, INC};    // INC 
        
        // COND=0010 (NE: Z==0)
        memory[152] = {4'h2, BRC};   // BRC NE 
        memory[153] = 8'hFA;         // -6 nibbles: PC(154*2) - 6 = 302 -> byte 151
        
        // Target after loop breaks
        memory[154] = {4'h6, LDI};   // ACC=6

        // Phase 7: LK16 JMP/JAL (RA1 link + jump)
        memory[155] = {4'h2, CFG};   // CFG 0x02 (LK16)
        memory[156] = {NOP, 4'h0};
        
        // Set RA0 = address of byte 164 = 328 nibbles = 0x0148
        memory[157] = {4'h8, LDI};   // LDI 0x48 (low)
        memory[158] = {4'h4, 4'h1};  
        memory[159] = {NOP, 4'h0};   // (high)
        memory[160] = {SA , XOP};    // SA -> RA0=0x0148
        
        memory[161] = {JMP, XOP};    // XOP JMP (1 byte)
        memory[162] = {NOP, NOP};    // skipped
        memory[163] = {NOP, NOP};    // skipped
        
        // Target 164 
        memory[164] = {4'h8, LDI};   // LDI 0x08
        memory[165] = {4'h0, 4'h0};
        memory[166] = {NOP, 4'h0};
        
        // Set RA0 = address of byte 174 = 348 nibbles = 0x015C
        memory[167] = {4'hC, LDI};   // 0x5C 
        memory[168] = {4'h5, 4'h1};
        memory[169] = {NOP, 4'h0};
        memory[170] = {SA , XOP};    // SA -> RA0=0x015C
        
        memory[171] = {NOP, JAL};    // JAL -> PC=015C, RA1=link= (172*2)=344=0x0158
        memory[172] = {4'h9, LDI};   // LDI 0x09 (Return point)
        memory[173] = {4'h0, 4'h0};  // Pad due to LK16 LDI
        
        memory[174] = {RSA, XOP};    // RSA -> swap RA0/RA1 to prove RA1=link
        memory[175] = {SA , XOP};    // SA -> ACC = RA0 = 0x0158 (link address)
        
        // Since ACC holds 0x0158, we can swap it back to RA0 to jump to it!
        memory[176] = {SA , XOP};    // SA -> RA0 = 0x0158
        memory[177] = {JMP, XOP};    // XOP JMP -> return to byte 172 (which is an LK16 LDI 9)
        

        // Target of JAL: RA0 = 176*2 = 352 = 0x0160
        memory[167] = {4'h0, LDI};   // 0x60
        memory[168] = {4'h6, 4'h1};
        memory[169] = {NOP, 4'h0};

        memory[172] = {4'hA, LDI};   // LDI 0xA
        memory[173] = {4'hA, 4'h0};
        memory[174] = {NOP, 4'h0};
        memory[175] = {NOP, NOP}; // Spin or NOP 

        memory[176] = {RSA, XOP};    // RSA (RA0 <-> RA1) -> RA0 = link (172*2 = 344 = 0x0158)
        memory[177] = {SA , XOP};    // ACC = RS0 = 0x0158 
        memory[178] = {SA , XOP};    // RA0 = 0x0158
        memory[179] = {JMP, XOP};    // JMP 

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        // Phase 1 (UL sanity + BRC EQ Taken/Not Taken)
        validate(3,  1, 16'h0005, 1'b0); // LDI 0x5
        validate(5,  1, 16'h0000, 1'b0); // LDI 0x0
        validate(9,  1, 16'h0001, 1'b0); // BRC taken -> LDI 0x1
        validate(12, 1, 16'h0002, 1'b0); // BRC not taken -> LDI 0x2

        // Phase 2 (BRC CS)
        validate(13, 1, 16'h0000, 1'b0); // LDI 0x0
        validate(14, 1, 16'h0000, 1'b0); // SHL -> C=0
        validate(17, 1, 16'h0003, 1'b0); // BRC not taken -> LDI 0x3
        validate(20, 0, 16'h0000, 1'b1); // SHL -> C=1
        validate(23, 1, 16'h0004, 1'b1); // BRC taken -> LDI 0x4

        // Phase 3 (Negative Branches)
        validate(24, 0, 16'h000E, 1'b1); // LDI 0xE
        validate(28, 1, 16'h0006, 1'b0); // After loop terminates -> LDI 0x6 (C=0 from INC)

        // Phase 4 (LK16 JMP/JAL)
        validate(38, 1, 16'h0008, 1'b0); // Target of JMP -> LDI 0x08
        validate(51, 1, 16'h005C, 1'b0); // Inside JAL target, ACC has link address 0x5C
        validate(46, 1, 16'h00AA, 1'b0); // Post-JMP Return -> LDI 0xAA

        $display("ALL CONTROL TESTS DONE");
        $finish;
    end

endmodule
