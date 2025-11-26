`timescale 1ns / 1ps

module tb_control;

    // Instruction table
    localparam [3:0] CC   = 4'b0001;
    localparam [3:0] AND  = 4'b0101;
    localparam [3:0] OR   = 4'b1001;
    localparam [3:0] SHL  = 4'b1101;
    localparam [3:0] ADD  = 4'b0011;
    localparam [3:0] INC  = 4'b1011;
    localparam [3:0] BEQZ = 4'b0111;
    localparam [3:0] BTST = 4'b1111;
    localparam [3:0] JAL  = 4'b0010;
    localparam [3:0] RACC = 4'b0110;
    localparam [3:0] RSS  = 4'b1010;
    localparam [3:0] SS   = 4'b1110;
    localparam [3:0] LDI  = 4'b0100;
    localparam [3:0] XMEM = 4'b1100;
    localparam [3:0] XOP  = 4'b1000;
    localparam [3:0] NOP  = 4'b0000;

    // Extended
    localparam [3:0] CFG  = 4'b0001;
    localparam [3:0] INV  = 4'b0101;
    localparam [3:0] XOR  = 4'b1001;
    localparam [3:0] SHR  = 4'b1101;
    localparam [3:0] SUB  = 4'b0011;
    localparam [3:0] DEC  = 4'b1011;
    localparam [3:0] BC   = 4'b0111;
    localparam [3:0] TST  = 4'b1111;
    localparam [3:0] JMP  = 4'b0010;
    localparam [3:0] RRS  = 4'b0110;
    localparam [3:0] RSA  = 4'b1010;
    localparam [3:0] SA   = 4'b1110;
    localparam [3:0] SIA  = 4'b0100;
    localparam [3:0] RETI = 4'b1100;
    localparam [3:0] SWI  = 4'b1000;
    localparam [3:0] WFI  = 4'b0000;

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
        if (mem_enable_read) begin
            mem_data_in = memory[mem_addr];
        end else begin
            mem_data_in = 8'h00;
        end
    end

    // Task to check ACC value
    task check_acc;
        input [15:0] expected;
        begin
            if (test_data !== expected) begin
                $display("ERROR at time %t: ACC mismatch. Expected %h, Got %h", $time, expected, test_data);
                $fatal(1);
            end else begin
                $display("PASS at time %t: ACC = %h", $time, test_data);
            end
        end
    endtask

    // Task to check Carry value
    task check_carry;
        input expected;
        begin
            if (test_carry !== expected) begin
                $display("ERROR at time %t: Carry mismatch. Expected %b, Got %b", $time, expected, test_carry);
                $fatal(1);
            end else begin
                $display("PASS at time %t: Carry = %b", $time, test_carry);
            end
        end
    endtask

    // Task to wait for a specific memory address to be read
    task wait_for_addr;
        input [14:0] addr;
        integer timeout;
        begin
            timeout = 10000;
            // Wait for mem_enable_read to be high AND mem_addr to match
            while (!(mem_enable_read && mem_addr === addr) && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("TIMEOUT waiting for address %h", addr);
                $fatal(1);
            end
        end
    endtask

    // Debug Monitor
    always @(posedge clk) begin
        $display("Time %t: PC=%h State=%h L0=%h Nibble=%h ACC=%h RS0=%h C=%b MemRead=%b MemAddr=%h MemIn=%h", 
                 $time, dut.pc, dut.state, dut.L0, dut.current_nibble, test_data, dut.bank_1[0], test_carry,
                 mem_enable_read, mem_addr, mem_data_in);
    end

    initial begin
        $dumpfile("waves_control.vcd");
        $dumpvars(0, tb_control);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // =================================================================
        // Test Sequence (Based on Control Test Plan)
        // =================================================================

        // Phase 1: Conditional Branches (UL Mode)
        memory[1]  = 8'h18; // XOP, CFG
        memory[2]  = 8'h4C; // Imm 0x4C (UL, CEN=1)
        memory[3]  = 8'h04; // LDi, 0x0 (ACC=0)
        memory[4]  = 8'h27; // BEQZ, 0x2 (Taken -> 0x07)
        memory[5]  = 8'hF4; // LDi, 0xF (Skipped)
        memory[6]  = 8'hF4; // LDi, 0xF (Skipped)
        memory[7]  = 8'h14; // LDi, 0x1 (ACC=1)
        memory[8]  = 8'h27; // BEQZ, 0x2 (Not Taken)
        memory[9]  = 8'h24; // LDi, 0x2 (ACC=2)

        // Phase 2: Bit Test & Branch Carry
        memory[10] = 8'h34; // LDi, 0x3 (ACC=3)
        memory[11] = 8'h04; // LDi, 0x0 (ACC=0)
        memory[12] = 8'h14; // LDi, 0x1 (ACC=1)
        memory[13] = 8'hE0; // NOP, SS (RS0=1)
        memory[14] = 8'h34; // LDi, 0x3 (ACC=3)
        memory[15] = 8'hF1; // BTST, 0x1 (Test bit 1 of ACC, C=1)
        memory[16] = 8'h27; // BC, 0x2 (Taken -> 0x13) - Wait, BC is XOP? No, BC is 0111 extended.
                            // BEQZ is 0111. BC is XOP, 0111.
                            // My memory[16] is 8'h27 which is BEQZ 2.
                            // BC needs XOP prefix.
                            // Let's fix this in the code below.
        
        // Correcting Phase 2 for BC
        // memory[16] needs to be XOP, BC.
        // But BC takes an immediate? Yes, BC #imm.
        // So it's XOP, then BC opcode with immediate.
        // XOP is 1000 (8). BC is 0111 (7).
        // So:
        // memory[16] = 8'h18; // XOP, CFG? No, just XOP.
        // memory[17] = 8'h27; // BC, 0x2.
        // But wait, XOP prefix applies to the next instruction.
        // The instruction at 17 is "BC 2".
        // "BC 2" is opcode 7, imm 2. -> 0x27.
        // So we need XOP at 16.
        
        // Let's shift addresses from 16 onwards.
        // 15: BTST 1.
        // 16: XOP.
        // 17: BC 2. (Taken -> PC_next + 2). PC_next is 18. Target 1A.
        // 18: LDi F (Skipped)
        // 19: LDi F (Skipped)
        // 1A: LDi 5.

        memory[16] = 8'h08; // XOP (Just XOP, no imm. Opcode 8, imm 0? Or just 80? XOP is 1000. 8'h08 is NOP, XOP? No. 
                            // XOP is 1000. NOP is 0000.
                            // 8'h08 is Imm=0, Op=XOP. Correct.
        memory[17] = 8'h27; // BC, 2. (Taken -> 1A)
        memory[18] = 8'hF4; // Skipped
        memory[19] = 8'hF4; // Skipped
        memory[20] = 8'h54; // LDi 5 (ACC=5)

        // Phase 3: Unconditional Jumps (JMP/JAL)
        // 21: LDi 4
        // 22: LDi 1
        // 23: SA (RA0=... wait, need to load RA0 properly)
        // Let's follow the plan but adjust addresses.
        
        // Load 0x001E into RA0.
        // 1E = 30.
        // We are at 21 (0x15).
        // Let's load 0x0020 into RA0 (32).
        // 21: LDi E (ACC=E)
        // 22: LDi 1 (ACC=1E)
        // 23: SA (RA0=1E)
        // 24: XOP
        // 25: JMP (to 1E)
        // 26: Skipped
        // ...
        // 1E: LDi 5.
        
        memory[21] = 8'hE4; // LDi E
        memory[22] = 8'h14; // LDi 1 (ACC=1E)
        memory[23] = 8'hE8; // XOP, SA (RA0=1E)
        memory[24] = 8'h08; // XOP
        memory[25] = 8'h28; // JMP (Op 2, Imm 8? No. JMP is Extended 2. JAL is 2. 
                            // JMP is XOP, JAL.
                            // 25: JMP. Opcode 2. Imm doesn't matter for JMP RA0.
                            // So 0x02 is fine.
        memory[26] = 8'hFF; // Skipped
        memory[27] = 8'hFF; // Skipped
        memory[28] = 8'hFF; // Skipped
        memory[29] = 8'hFF; // Skipped

        // Target 1E (30)
        memory[30] = 8'h54; // LDi 5 (ACC=5)

        // Phase 4: JAL Test
        // Load 0x0022 (34) into RA0.
        // 31: LDi 2
        // 32: LDi 2 (ACC=22)
        // 33: SA (RA0=22)
        // 34: JAL (to 22). RA1 -> 35.
        // 35: NOP (Return address)
        // ...
        // 22: NOP (Target)
        // 23: SA (Swap ACC/RA0)
        // 24: RSA (Swap RA0/RA1)
        // 25: SA (Swap ACC/RA0) -> ACC should be 35 (0x23).

        // Adjusting addresses:
        // We are at 31 (0x1F).
        memory[31] = 8'h24; // LDi 2
        memory[32] = 8'h24; // LDi 2 (ACC=22)
        memory[33] = 8'hE8; // XOP, SA (RA0=22)
        memory[34] = 8'h02; // JAL (Standard, Op 2). PC->22. RA1->35.
        
        // Target at 22 (0x22).
        // Wait, 22 is already used by "LDi 1" in Phase 3 setup?
        // Yes, 22 is 0x16.
        // We need to jump forward to empty space.
        // Let's jump to 0x28 (40).
        // Load 0x0028 into RA0.
        // 31: LDi 8
        // 32: LDi 2 (ACC=28)
        // 33: SA (RA0=28)
        // 34: JAL.
        
        memory[31] = 8'h84; // LDi 8
        memory[32] = 8'h24; // LDi 2 (ACC=28)
        memory[33] = 8'hE8; // XOP, SA (RA0=28)
        memory[34] = 8'h02; // JAL. PC->28. RA1->23 (35).
        
        // Return address 35 (0x23).
        // We can put a check here or just stop?
        // The test plan says we check RA1.
        // So at target (28), we should return? Or just check RA1 there?
        // At target (28):
        // 28: SA (Swap ACC/RA0). RA0 was 28. ACC becomes 28.
        // 29: RSA (Swap RA0/RA1). RA0 becomes 23.
        // 2A: SA (Swap ACC/RA0). ACC becomes 23.
        
        memory[40] = 8'hE8; // XOP, SA
        memory[41] = 8'hA8; // XOP, RSA
        memory[42] = 8'hE8; // XOP, SA

        // =================================================================
        // Execution & Checks
        // =================================================================
        
        #50; rst = 0;

        // Phase 1 Checks
        wait_for_addr(15'h0007); // After BEQZ taken
        check_acc(16'h0001);

        wait_for_addr(15'h0009); // After BEQZ not taken
        check_acc(16'h0002);

        // Phase 2 Checks
        wait_for_addr(15'h0014); // After LDi 5 (Target of BC)
        check_acc(16'h0005);

        // Phase 3 Checks
        wait_for_addr(15'h001E); // After JMP to 1E
        check_acc(16'h0005);

        // Phase 4 Checks
        wait_for_addr(15'h002A); // After JAL sequence
        check_acc(16'h0023); // RA1 should be 0x23 (35)

        $display("ALL CONTROL TESTS PASSED");
        $finish;
    end

endmodule
