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
        memory[6]  = {4'h2, BEQZ};  // BEQZ +2 (taken)
        memory[7]  = {4'hF, LDI};   // skipped
        memory[8]  = {4'h1, LDI};   // target ACC=1
        memory[9]  = {4'h2, BEQZ};  // BEQZ +2 (not taken)
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
        memory[31] = {4'h0, 4'h2};  // imm8 low=2, high=0
        memory[32] = {4'h7, LDI};   // ACC=7

        // Phase 4: BRS=1 scaling (imm4)
        memory[33] = {4'h4, CFG};   // CFG 0x24 (UL, BW=imm4, BRS=1)
        memory[34] = {NOP, 4'h2};
        memory[35] = {4'h0, LDI};   // ACC=0
        memory[36] = {4'h1, BEQZ};  // BEQZ +1 (scaled <<2)
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

        $display("CONTROL TEST DONE (validations)");
        $finish;
    end

endmodule
