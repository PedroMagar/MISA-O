`timescale 1ns / 1ps
`include "testbench/misa-o_instructions.svh"

module tb_control;

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
                // Sample after negedge to see the fetched byte address.
                @(negedge clk); #0;
                while (mem_addr != addr) begin
                    @(negedge clk); #0;
                end
            end else begin
                // Back-to-back validate on same byte: just advance one nibble edge.
                @(negedge clk); #0;
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
            $display("SUCCESS AT @%0d: got=%b exp=%b", addr, {test_carry, test_data}, {expected_carry,expected_acc});
        end
    endtask

    initial begin
        $dumpfile("waves_control.vcd");
        $dumpvars(0, tb_control);

        rst = 1;
        last_addr = 15'h7fff;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // ================================================================
        // Test Sequence (Control)
        // ================================================================

        // Phase 1: Conditional branches (UL)
        memory[1]  = {CFG, XOP};    // XOP CFG
        memory[2]  = {4'h4, 4'hC};  // cfg=0x4C (UL)
        memory[3]  = {4'h0, LDI};   // ACC=0
        memory[4]  = {4'h2, BEQZ};  // BEQZ +2 (taken)
        memory[5]  = {4'hF, LDI};   // skipped
        memory[6]  = {4'hF, LDI};   // skipped
        memory[7]  = {4'h1, LDI};   // ACC=1
        memory[8]  = {4'h2, BEQZ};  // not taken
        memory[9]  = {4'h2, LDI};   // ACC=2

        // Phase 2: BTST + BC
        memory[10] = {4'h3, LDI};   // ACC=3
        memory[11] = {4'h0, LDI};   // ACC=0
        memory[12] = {4'h1, LDI};   // ACC=1
        memory[13] = {SS , NOP};    // RS0=1
        memory[14] = {4'h3, LDI};   // ACC=3
        memory[15] = {BTST, 4'h1};  // C = ACC[RS0]=1
        memory[16] = {XOP, 4'h0};   // XOP prefix
        memory[17] = {4'h2, BC};    // BC taken +2 -> skip next two LDIs
        memory[18] = {4'hF, LDI};   // skipped
        memory[19] = {4'hF, LDI};   // skipped
        memory[20] = {4'h5, LDI};   // ACC=5

        // Phase 3: JMP via RA0
        memory[21] = {4'hE, LDI};   // ACC=E
        memory[22] = {4'h1, LDI};   // ACC=1E
        memory[23] = {SA , XOP};    // RA0=0x001E
        memory[24] = {XOP, 4'h0};   // XOP
        memory[25] = {JMP, 4'h0};   // JMP RA0
        memory[26] = {4'hF, 4'hF};  // filler
        memory[27] = {4'hF, 4'hF};  // filler
        memory[28] = {4'hF, 4'hF};  // filler
        memory[29] = {4'hF, 4'hF};  // filler
        memory[30] = {4'h5, LDI};   // target ACC=5

        // Phase 4: JAL to RA0=0x0028
        memory[31] = {4'h8, LDI};   // ACC=8
        memory[32] = {4'h2, LDI};   // ACC=0x28
        memory[33] = {SA , XOP};    // RA0=0x0028
        memory[34] = {JAL, 4'h0};   // JAL -> jump RA0, link RA1
        memory[40] = {SA , XOP};    // at target: swap ACC/RA0
        memory[41] = {RSA, XOP};    // swap RA0/RA1
        memory[42] = {SA , XOP};    // ACC should end 0x0023

        // Phase 5: Advanced branches (BW/BRS, negative offset, BC not taken)
        memory[43] = {CFG, XOP};
        memory[44] = {4'h4, 4'h8};  // CFG=0x48 (BW=imm4, BRS=1)
        memory[45] = {4'h0, LDI};   // ACC=0
        memory[46] = {BEQZ, 4'hF};  // BEQZ with imm4=F (negative) scaled by BRS
        memory[47] = {XOP, 4'h0};   // XOP prefix
        memory[48] = {BC, 4'h2};    // BC not taken (C=0)
        memory[49] = {4'h1, LDI};   // Execute sequentially to prove non-taken

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        // Phase 1 (UL branches)
        validate(3, 1, 16'h0000, 1'b0); // LDI -> ACC=0 (sets up BEQZ taken)
        validate(7, 1, 16'h0001, 1'b0); // LDI -> ACC=1 (after BEQZ jump)
        validate(9, 1, 16'h0002, 1'b0); // LDI -> ACC=2 (BEQZ not taken)

        // Phase 2 (BTST / BC)
        validate(10,1, 16'h0003, 1'b0); // LDI -> ACC=3
        validate(11,1, 16'h0000, 1'b0); // LDI -> ACC=0
        validate(12,1, 16'h0001, 1'b0); // LDI -> ACC=1
        validate(13,1, 16'h0000, 1'b0); // SS  -> ACC=0, RS0=1
        validate(14,1, 16'h0003, 1'b0); // LDI -> ACC=3
        validate(15,1, 16'h0003, 1'b1); // BTST-> ACC=3, C=ACC[RS0]=1
        validate(20,1, 16'h0005, 1'b1); // LDI -> ACC=5 (after BC taken)

        // Phase 3 (JMP via RA0)
        validate(21,1, 16'h000E, 1'b1); // LDI -> ACC=0x000E
        validate(22,1, 16'h001E, 1'b1); // LDI -> ACC=0x001E
        validate(23,1, 16'h0000, 1'b1); // SA  -> ACC swap with RA0 (ACC=0)
        validate(30,1, 16'h0005, 1'b1); // JMP target -> ACC=5

        // Phase 4 (JAL)
        validate(31,1, 16'h0008, 1'b1); // LDI -> ACC=0x0008
        validate(32,1, 16'h0028, 1'b1); // LDI -> ACC=0x0028
        validate(33,1, 16'h001E, 1'b1); // SA  -> ACC=old RA0=0x001E
        validate(42,1, 16'h0023, 1'b0); // after JAL sequence -> ACC=0x0023

        // Phase 5 (advanced branches)
        validate(45,1, 16'h0000, 1'b0); // LDI -> ACC=0 before negative BEQZ
        validate(44,1, 16'h0000, 1'b0); // BEQZ negative jump -> ACC stays 0
        validate(49,1, 16'h0001, 1'b0); // BC not taken -> ACC=1

        $display("CONTROL TEST DONE (validations)");
        $finish;
    end

endmodule
