`timescale 1ns / 1ps

module tb_special;

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
        $display("Time %t: PC=%h State=%h L0=%h Nibble=%h ACC=%h RS0=%h RA0=%h MemRead=%b MemAddr=%h MemIn=%h", 
                 $time, dut.pc, dut.state, dut.L0, dut.current_nibble, test_data, dut.bank_1[0], dut.bank_addr[0],
                 mem_enable_read, mem_addr, mem_data_in);
    end

    initial begin
        $dumpfile("waves_special.vcd");
        $dumpvars(0, tb_special);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // =================================================================
        // Test Sequence (Based on Revised Test Plan)
        // =================================================================
        
        // Phase 1: Setup & Pattern Loading (LK16)
        memory[1] = 8'h18; // XOP, CFG
        memory[2] = 8'h4E; // Imm 0x4E (LK16)
        memory[3] = 8'hA4; // LDi, 0xA
        memory[4] = 8'hAA; // 0xA, 0xA
        memory[5] = 8'h0A; // 0xA, NOP

        // Phase 2: SS (Swap Source) in UL Mode
        memory[6] = 8'h18; // XOP, CFG
        memory[7] = 8'h4C; // Imm 0x4C (UL)
        memory[8] = 8'h14; // LDi, 0x1
        memory[9] = 8'hE0; // NOP, SS
        memory[10] = 8'h24; // LDi, 0x2
        memory[11] = 8'hE0; // NOP, SS

        // Phase 3: SA (Swap Address) in UL Mode
        memory[12] = 8'hE8; // XOP, SA
        memory[13] = 8'h54; // LDi, 0x5
        memory[14] = 8'hE8; // XOP, SA

        // Phase 4: RSS (Rotate Stack Source)
        memory[15] = 8'h18; // XOP, CFG
        memory[16] = 8'h4E; // Imm 0x4E (LK16)
        memory[17] = 8'hB4; // LDi, 0xB
        memory[18] = 8'hBB; // 0xB, 0xB
        memory[19] = 8'h0B; // 0xB, NOP
        memory[20] = 8'hE0; // NOP, SS
        memory[21] = 8'hA0; // NOP, RSS
        memory[22] = 8'hC4; // LDi, 0xC
        memory[23] = 8'hCC; // 0xC, 0xC
        memory[24] = 8'h0C; // 0xC, NOP
        memory[25] = 8'hE0; // NOP, SS
        memory[26] = 8'hA0; // NOP, RSS
        memory[27] = 8'hE0; // NOP, SS

        // Phase 5: RSA (Rotate Stack Address)
        memory[28] = 8'h14; // LDi, 0x1
        memory[29] = 8'h11; // 0x1, 0x1
        memory[30] = 8'h01; // 0x1, NOP
        memory[31] = 8'hE8; // XOP, SA
        memory[32] = 8'hA8; // XOP, RSA
        memory[33] = 8'h24; // LDi, 0x2
        memory[34] = 8'h22; // 0x2, 0x2
        memory[35] = 8'h02; // 0x2, NOP
        memory[36] = 8'hE8; // XOP, SA
        memory[37] = 8'hA8; // XOP, RSA
        memory[38] = 8'hE8; // XOP, SA

        // Phase 6: RRS (Rotate Register Source)
        memory[39] = 8'h18; // XOP, CFG
        memory[40] = 8'h4C; // Imm 0x4C (UL)
        memory[41] = 8'h44; // LDi, 0x4
        memory[42] = 8'hE0; // NOP, SS
        memory[43] = 8'h14; // LDi, 0x1
        memory[44] = 8'hE0; // NOP, SS
        memory[45] = 8'h68; // XOP, RRS
        memory[46] = 8'hE0; // NOP, SS

        // =================================================================
        // Execution & Checks
        // =================================================================
        
        #50; rst = 0;

        // Wait for Phase 1 & 2 to complete
        // Phase 2 ends at address 0x0B. Next fetch is 0x0C.
        wait_for_addr(15'h000C);
        check_acc(16'hAAA1);

        // Wait for Phase 3 to complete
        // Phase 3 ends at address 0x0E. Next fetch is 0x0F.
        wait_for_addr(15'h000F);
        check_acc(16'hAAA1);

        // Wait for Phase 4 to complete
        // Phase 4 ends at address 0x1B. Next fetch is 0x1C.
        wait_for_addr(15'h001C);
        check_acc(16'hBBBB);

        // Wait for Phase 5 to complete
        // Phase 5 ends at address 0x26. Next fetch is 0x27.
        wait_for_addr(15'h0027);
        check_acc(16'h1111);

        // Wait for Phase 6 to complete
        // Phase 6 ends at address 0x2E. Next fetch is 0x2F.
        wait_for_addr(15'h002F);
        // RRS rotated 0x...1 to 0x1...
        // SS swapped ACC[0] (which was 0x1 from LDi) with RS0[3:0] (which should be 0).
        // So ACC should be 0.
        if (test_data[3:0] !== 4'h0) begin
             $display("ERROR at time %t: ACC[0] mismatch. Expected 0, Got %h", $time, test_data[3:0]);
             $fatal(1);
        end else begin
             $display("PASS at time %t: ACC[0] = 0", $time);
        end

        $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
