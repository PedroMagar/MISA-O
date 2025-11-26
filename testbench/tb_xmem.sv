`timescale 1ns / 1ps

module tb_xmem;

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

    // Task to check Memory value
    task check_mem;
        input [7:0] addr;
        input [7:0] expected;
        begin
            if (memory[addr] !== expected) begin
                $display("ERROR at time %t: MEM[%h] mismatch. Expected %h, Got %h", $time, addr, expected, memory[addr]);
                $fatal(1);
            end else begin
                $display("PASS at time %t: MEM[%h] = %h", $time, addr, memory[addr]);
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
        $display("Time %t: PC=%h State=%h L0=%h Nibble=%h ACC=%h RA0=%h RA1=%h MemRead=%b MemAddr=%h MemIn=%h", 
                 $time, dut.pc, dut.state, dut.L0, dut.current_nibble, test_data, dut.bank_addr[0], dut.bank_addr[1],
                 mem_enable_read, mem_addr, mem_data_in);
    end

    initial begin
        $dumpfile("waves_xmem.vcd");
        $dumpvars(0, tb_xmem);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // =================================================================
        // Test Sequence (Based on XMEM Test Plan)
        // =================================================================

        // Phase 1: Setup (LK16) - Init RA0=0x0080, RA1=0x0090
        memory[1]  = 8'h18; // XOP, CFG
        memory[2]  = 8'h4E; // Imm 0x4E (LK16)
        memory[3]  = 8'h84; // LDi, 0x8
        memory[4]  = 8'h00; // 0x0, 0x0
        memory[5]  = 8'h00; // 0x0, NOP (ACC=0x0080)
        memory[6]  = 8'hE8; // XOP, SA (RA0=0x0080)
        memory[7]  = 8'h94; // LDi, 0x9
        memory[8]  = 8'h00; // 0x0, 0x0
        memory[9]  = 8'h00; // 0x0, NOP (ACC=0x0090)
        memory[10] = 8'hE8; // XOP, SA (RA0=0x0090)
        memory[11] = 8'hA8; // XOP, RSA (RA1=0x0090, RA0=0x0080)

        // Phase 2: UL Mode Store/Load
        memory[12] = 8'h18; // XOP, CFG
        memory[13] = 8'h4C; // Imm 0x4C (UL)
        memory[14] = 8'h54; // LDi, 0x5
        memory[15] = 8'hCC; // XMEM, 0xC (Store UL @RA0, Post-Inc)
        memory[16] = 8'h34; // LDi, 0x3
        memory[17] = 8'h8C; // XMEM, 0x8 (Store UL @RA0, No Inc)
        memory[18] = 8'h0C; // XMEM, 0x0 (Load UL @RA0)

        // Phase 3: LK8 Mode Store/Load
        memory[19] = 8'h18; // XOP, CFG
        memory[20] = 8'h4D; // Imm 0x4D (LK8)
        memory[21] = 8'hB4; // LDi, 0xB
        memory[22] = 8'h55; // 0x5, 0x5 (ACC=0x5B)
        memory[23] = 8'hCC; // XMEM, 0xC (Store Byte @RA0, Post-Inc)
        memory[24] = 8'h04; // LDi, 0x0
        memory[25] = 8'h00; // 0x0, 0x0 (ACC=0)
        memory[26] = 8'h8C; // XMEM, 0x8 (Store Byte @RA0)
        memory[27] = 8'h4C; // XMEM, 0x4 (Load Byte @RA0, Post-Inc)
        memory[28] = 8'h6C; // XMEM, 0x6 (Load Byte @RA0, Post-Dec)

        // Phase 4: LK16 Mode & RA1
        memory[29] = 8'h18; // XOP, CFG
        memory[30] = 8'h4E; // Imm 0x4E (LK16)
        memory[31] = 8'h14; // LDi, 0x1
        memory[32] = 8'h22; // 0x2, 0x2
        memory[33] = 8'h33; // 0x3, 0x3
        memory[34] = 8'h44; // 0x4, 0x4 (ACC=0x1234)
        memory[35] = 8'hCD; // XMEM, 0xD (Store Word @RA1, Post-Inc, AR=1)
        memory[36] = 8'h04; // LDi, 0x0
        memory[37] = 8'h00; // 0x0, 0x0
        memory[38] = 8'h00; // 0x0, 0x0
        memory[39] = 8'h00; // 0x0, 0x0 (ACC=0)
        memory[40] = 8'h6D; // XMEM, 0x6 (Load Word @RA1, Post-Dec, AR=1)

        // =================================================================
        // Execution & Checks
        // =================================================================
        
        #50; rst = 0;

        // Phase 1 Checks
        wait_for_addr(15'h000C); // After Setup
        // RA0 should be 0x0080, RA1 should be 0x0090.
        // We can't check them directly easily without swapping, but subsequent stores will verify.

        // Phase 2 Checks
        wait_for_addr(15'h0013); // After UL operations
        check_mem(8'h80, 8'h05); // [0x80] = 05
        check_mem(8'h81, 8'h03); // [0x81] = 03
        check_acc(16'h0003); // ACC should be 3

        // Phase 3 Checks
        wait_for_addr(15'h001D); // After LK8 operations
        check_mem(8'h81, 8'h5B); // [0x81] = 5B (Overwrote 03)
        check_mem(8'h82, 8'h00); // [0x82] = 00
        check_acc(16'h0000); // ACC should be 0

        // Phase 4 Checks
        wait_for_addr(15'h0029); // After LK16 operations
        check_mem(8'h90, 8'h34); // [0x90] = 34
        check_mem(8'h91, 8'h12); // [0x91] = 12
        check_acc(16'h1234); // ACC should be 1234

        $display("ALL XMEM TESTS PASSED");
        $finish;
    end

endmodule
