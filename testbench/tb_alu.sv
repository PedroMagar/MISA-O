`timescale 1ns / 1ps
`include "testbench/misa-o_instructions.svh"

module tb_alu;

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

    // Validation task: wait for read of addr, check mem_data_in, then after cycles check ACC.
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
        end
    endtask

    initial begin
        $dumpfile("waves_alu.vcd");
        $dumpvars(0, tb_alu);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // ================================================================
        // Test Sequence (ALU)
        // ================================================================

        // Phase 1: UL arithmetic
        memory[1]  = {CFG, XOP};
        memory[2]  = {4'h4, 4'hC};   // imm 0x4C (UL, CEN=1)
        memory[3]  = {4'h5, LDI};    // LDI 5
        memory[4]  = {SS , NOP};     // RS0=5
        memory[5]  = {4'h3, LDI};    // LDI 3
        memory[6]  = {ADD, NOP};     // ACC=8
        memory[7]  = {ADD, NOP};     // ACC=D
        memory[8]  = {ADD, NOP};     // ACC=2, C=1
        memory[9]  = {CC , NOP};     // C=0
        memory[10] = {INC, NOP};     // ACC=3
        memory[11] = {SUB, XOP};     // SUB (ACC=E, C=1)

        // Phase 2: UL logic & shifts
        memory[12] = {4'hC, LDI};    // LDI C
        memory[13] = {SS , NOP};     // RS0=C
        memory[14] = {4'hA, LDI};    // LDI A
        memory[15] = {AND, NOP};     // ACC=8
        memory[16] = {OR , NOP};     // ACC=C
        memory[17] = {XOR, XOP};     // ACC=0
        memory[18] = {INV, XOP};     // ACC=F
        memory[19] = {SHL, NOP};     // ACC=E, C=1
        memory[20] = {SHR, XOP};     // ACC=7, C=0

        // Phase 3: LK8 arithmetic
        memory[21] = {CFG, XOP};
        memory[22] = {4'h4, 4'hD};   // imm 0x4D (LK8)
        memory[23] = {4'h1, LDI};    // LDI 1
        memory[24] = {NOP, 4'h0};    // NOP (ACC=01)
        memory[25] = {SS , NOP};     // RS0=01
        memory[26] = {4'hF, LDI};    // LDI F
        memory[27] = {NOP, 4'hF};    // NOP (ACC=FF)
        memory[28] = {ADD, NOP};     // ACC=00, C=1

        // Phase 4: LK16 arithmetic
        memory[29] = {CFG, XOP};
        memory[30] = {4'h4, 4'hE};   // imm 0x4E (LK16)
        memory[31] = {4'h1, LDI};    // LDI 1
        memory[32] = {4'h0, 4'h0};   // imm1
        memory[33] = {NOP, 4'h0};    // NOP (ACC=0001)
        memory[34] = {SS , NOP};     // RS0=0001
        memory[35] = {4'hF, LDI};    // LDI F
        memory[36] = {4'hF, 4'hF};   // imm1
        memory[37] = {NOP, 4'hF};    // imm2
        memory[38] = {ADD, NOP};     // ACC=0000, C=1

        // Phase 5: DEC with CEN variations, SHL/SHR in LK8/LK16
        memory[39] = {CFG, XOP};     // cfg 0x4C (UL, CEN=1)
        memory[40] = {4'h4, 4'hC};
        memory[41] = {4'h3, LDI};    // ACC=3
        memory[42] = {DEC, XOP};     // ACC=2, C=0
        memory[43] = {CFG, XOP};     // cfg 0x44 (UL, CEN=0)
        memory[44] = {4'h4, 4'h4};
        memory[45] = {DEC, XOP};     // ACC=1, C=1 (borrow)
        // LK8 shifts
        memory[46] = {CFG, XOP};
        memory[47] = {4'h4, 4'hD};   // LK8
        memory[48] = {4'hF, LDI};    // ACC=0x0F
        memory[49] = {SHL, NOP};     // ACC=0x1E, C from bit7=0
        memory[50] = {SHR, XOP};     // ACC=0x0F, C=0
        // LK16 shifts
        memory[51] = {CFG, XOP};
        memory[52] = {4'h4, 4'hE};   // LK16
        memory[53] = {4'h1, LDI};    // ACC=0x0001
        memory[54] = {SHL, NOP};     // ACC=0x0002, C=0
        memory[55] = {SHR, XOP};     // ACC=0x0001, C=0

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        // Phase 1
        validate(15'h0007, 1, 16'h0008, 1'b0);
        validate(15'h0008, 1, 16'h000D, 1'b0);
        validate(15'h0009, 1, 16'h0002, 1'b1);
        validate(15'h000A, 1, 16'h0002, 1'b0);
        validate(15'h000B, 1, 16'h0003, 1'b0);
        validate(15'h000C, 1, 16'h000E, 1'b1);

        // Phase 2
        validate(15'h0010, 1, 16'h0008, 1'b0);
        validate(15'h0011, 1, 16'h000C, 1'b0);
        validate(15'h0012, 1, 16'h0000, 1'b0);
        validate(15'h0013, 1, 16'h000F, 1'b1);
        validate(15'h0014, 1, 16'h000E, 1'b1);
        validate(15'h0015, 1, 16'h0007, 1'b0);

        // Phase 3
        validate(15'h001D, 1, 16'h0000, 1'b1);

        // Phase 4
        validate(15'h0027, 1, 16'h0000, 1'b1);

        // Phase 5
        validate(15'h0028, 1, 16'h0002, 1'b0); // DEC with CEN=1
        validate(15'h002A, 1, 16'h0001, 1'b1); // DEC with CEN=0 (borrow)
        validate(15'h002F, 1, 16'h001E, 1'b0); // LK8 SHL
        validate(15'h0031, 1, 16'h000F, 1'b0); // LK8 SHR
        validate(15'h0035, 1, 16'h0002, 1'b0); // LK16 SHL
        validate(15'h0037, 1, 16'h0001, 1'b0); // LK16 SHR

        $display("ALL ALU TESTS (validations) DONE");
        $finish;
    end

endmodule
