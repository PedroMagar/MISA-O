`timescale 1ns / 1ps

module tb_alu_full;

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
        $dumpfile("waves_full.vcd");
        $dumpvars(0, tb_alu_full);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // =================================================================
        // Test Sequence (Based on ALU Test Plan)
        // =================================================================

        // Phase 1: UL Mode (4-bit) Arithmetic
        memory[1]  = 8'h18; // XOP, CFG
        memory[2]  = 8'h4C; // Imm 0x4C (UL, CEN=1)
        memory[3]  = 8'h54; // LDi, 0x5
        memory[4]  = 8'hE0; // NOP, SS (RS0=5)
        memory[5]  = 8'h34; // LDi, 0x3 (ACC=3)
        memory[6]  = 8'h30; // NOP, ADD (ACC=8)
        memory[7]  = 8'h30; // NOP, ADD (ACC=D)
        memory[8]  = 8'h30; // NOP, ADD (ACC=2, C=1)
        memory[9]  = 8'h10; // NOP, CC (C=0)
        memory[10] = 8'hB0; // NOP, INC (ACC=3)
        memory[11] = 8'h38; // XOP, SUB (ACC=3-5=E, C=1)

        // Phase 2: UL Mode Logic & Shifts
        memory[12] = 8'hC4; // LDi, 0xC
        memory[13] = 8'hE0; // NOP, SS (RS0=C)
        memory[14] = 8'hA4; // LDi, 0xA
        memory[15] = 8'h50; // NOP, AND (ACC=8)
        memory[16] = 8'h90; // NOP, OR (ACC=C)
        memory[17] = 8'h98; // XOP, XOR (ACC=0)
        memory[18] = 8'h58; // XOP, INV (ACC=F)
        memory[19] = 8'hD0; // NOP, SHL (ACC=E, C=1)
        memory[20] = 8'hD8; // XOP, SHR (ACC=7, C=0)

        // Phase 3: LK8 Mode Arithmetic
        memory[21] = 8'h18; // XOP, CFG
        memory[22] = 8'h4D; // Imm 0x4D (LK8)
        memory[23] = 8'h14; // LDi, 0x1
        memory[24] = 8'h00; // 0x0, NOP (ACC=0x01)
        memory[25] = 8'hE0; // NOP, SS (RS0=0x01)
        memory[26] = 8'hF4; // LDi, 0xF
        memory[27] = 8'h0F; // 0xF, NOP (ACC=0xFF)
        memory[28] = 8'h30; // NOP, ADD (ACC=0x00, C=1)

        // Phase 4: LK16 Mode Arithmetic
        memory[29] = 8'h18; // XOP, CFG
        memory[30] = 8'h4E; // Imm 0x4E (LK16)
        memory[31] = 8'h14; // LDi, 0x1
        memory[32] = 8'h00; // 0x0, 0x0
        memory[33] = 8'h00; // 0x0, NOP (ACC=0x0001)
        memory[34] = 8'hE0; // NOP, SS (RS0=0x0001)
        memory[35] = 8'hF4; // LDi, 0xF
        memory[36] = 8'hFF; // 0xF, 0xF
        memory[37] = 8'h0F; // 0xF, NOP (ACC=0xFFFF)
        memory[38] = 8'h30; // NOP, ADD (ACC=0x0000, C=1)

        // =================================================================
        // Execution & Checks
        // =================================================================
        
        #50; rst = 0;

        // Phase 1 Checks
        wait_for_addr(15'h0007); // After first ADD
        check_acc(16'h0008); check_carry(0);

        wait_for_addr(15'h0008); // After second ADD
        check_acc(16'h000D); check_carry(0);

        wait_for_addr(15'h0009); // After third ADD (Overflow)
        check_acc(16'h0002); check_carry(1);

        wait_for_addr(15'h000A); // After CC
        check_carry(0);

        wait_for_addr(15'h000B); // After INC
        check_acc(16'h0003); check_carry(0);

        wait_for_addr(15'h000C); // After SUB
        check_acc(16'h000E); check_carry(1);

        // Phase 2 Checks
        wait_for_addr(15'h0010); // After AND
        check_acc(16'h0008);

        wait_for_addr(15'h0011); // After OR
        check_acc(16'h000C);

        wait_for_addr(15'h0012); // After XOR
        check_acc(16'h0000);

        wait_for_addr(15'h0013); // After INV
        check_acc(16'h000F);

        wait_for_addr(15'h0014); // After SHL
        check_acc(16'h000E); check_carry(1);

        wait_for_addr(15'h0015); // After SHR
        check_acc(16'h0007); check_carry(0);

        // Phase 3 Checks
        wait_for_addr(15'h001D); // After ADD (LK8)
        check_acc(16'h0000); check_carry(1);

        // Phase 4 Checks
        wait_for_addr(15'h0027); // After ADD (LK16)
        check_acc(16'h0000); check_carry(1);

        $display("ALL ALU TESTS PASSED");
        $finish;
    end

endmodule
