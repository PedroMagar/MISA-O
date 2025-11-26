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
    task automatic validate(input [14:0] addr, input integer cycles, input [15:0] expected_acc);
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
        end
    endtask

    initial begin
        $dumpfile("waves_control.vcd");
        $dumpvars(0, tb_control);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // ================================================================
        // Test Sequence (Control)
        // ================================================================

        // Phase 1: Conditional branches (UL)
        memory[1]  = {CFG, XOP};
        memory[2]  = {4'h4, 4'hC}; // cfg UL
        memory[3]  = {4'h0, LDI};  // ACC=0
        memory[4]  = {4'h2, BEQZ}; // BEQZ +2 (taken)
        memory[5]  = {4'hF, LDI};  // skipped
        memory[6]  = {4'hF, LDI};  // skipped
        memory[7]  = {4'h1, LDI};  // ACC=1
        memory[8]  = {4'h2, BEQZ}; // not taken
        memory[9]  = {4'h2, LDI};  // ACC=2

        // Phase 2: BTST + BC
        memory[10] = {4'h3, LDI};  // ACC=3
        memory[11] = {4'h0, LDI};  // ACC=0
        memory[12] = {4'h1, LDI};  // ACC=1
        memory[13] = {SS , NOP};   // RS0=1
        memory[14] = {4'h3, LDI};  // ACC=3
        memory[15] = {BTST, 4'h1}; // BTST imm1 (C=1)
        memory[16] = {XOP, 4'h0};  // XOP prefix
        memory[17] = {4'h2, BC};   // BC +2 (taken)
        memory[18] = {4'hF, LDI};  // skipped
        memory[19] = {4'hF, LDI};  // skipped
        memory[20] = {4'h5, LDI};  // ACC=5

        // Phase 3: JMP via RA0
        memory[21] = {4'hE, LDI};  // ACC=E
        memory[22] = {4'h1, LDI};  // ACC=1E
        memory[23] = {SA , XOP};   // RA0=1E
        memory[24] = {XOP, 4'h0};  // XOP
        memory[25] = {JMP, 4'h0};  // JMP RA0
        memory[26] = {4'hF, 4'hF}; // skipped fillers
        memory[27] = {4'hF, 4'hF};
        memory[28] = {4'hF, 4'hF};
        memory[29] = {4'hF, 4'hF};
        memory[30] = {4'h5, LDI};  // target ACC=5

        // Phase 4: JAL to RA0=0x0028
        memory[31] = {4'h8, LDI};  // ACC=8
        memory[32] = {4'h2, LDI};  // ACC=28
        memory[33] = {SA , XOP};   // RA0=28
        memory[34] = {JAL, 4'h0};  // JAL -> RA1=next
        memory[40] = {SA , XOP};
        memory[41] = {RSA, XOP};
        memory[42] = {SA , XOP};   // ACC should end 0x23

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        validate(15'h0007, 1, 16'h0001);
        validate(15'h0009, 1, 16'h0002);
        validate(15'h0014, 1, 16'h0005);
        validate(15'h001E, 1, 16'h0005);
        validate(15'h002A, 1, 16'h0023);

        $display("CONTROL TEST DONE (validations)");
        $finish;
    end

endmodule
