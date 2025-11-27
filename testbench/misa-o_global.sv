`timescale 1ns / 1ps

`include "testbench/misa-o_instructions.svh"

module tb_misao_global;

    reg clk;
    reg rst;

    // Memory Interface
    wire        mem_enable_read;
    wire        mem_enable_write;
    reg  [7:0]  mem_data_in;
    wire [14:0] mem_addr;
    wire        mem_rw;
    wire [7:0]  mem_data_out;
    wire [15:0] test_data;
    wire        test_carry;

    // Simple memory model (32 KB)
    reg [7:0] memory [0:32767];

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

    // Clock generation
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Combinational read path (always reflect current address)
    always @(*) begin
        mem_data_in = memory[mem_addr];
    end

    integer i;

    initial begin
        // Initialize memory
        for (i = 0; i < 32768; i = i + 1) begin
            memory[i] = 8'h00;
        end

        // Program: LDI UL, then CFG->LK8 + LDI 8-bit, then CFG->LK16 + LDI 16-bit
        memory[1]  = {4'h5, LDI};     // LDI UL imm=5

        memory[2]  = {CFG , XOP};     // XOP CFG
        memory[3]  = {4'h0, 4'hD};    // cfg=0x0D (LK8)

        memory[4]  = {4'hB, LDI};     // LDI LK8 imm_low=B
        memory[5]  = {4'h0, 4'hA};    // imm_high=A

        memory[6]  = {CFG , XOP};     // XOP CFG
        memory[7]  = {4'h0, 4'hE};    // cfg=0x0E (LK16)

        memory[8]  = {4'h4, LDI};     // LDI LK16 imm0=4
        memory[9]  = {4'h2, 4'h3};    // imm1=3, imm2=2
        memory[10] = {NOP , 4'h1};    // imm3=1 (high nibble filler)

        // Reset
        rst = 1'b1;
        #20;
        rst = 1'b0;

        // Parallel validators
        fork
            validate(1, 1, 16'h0005, 1'b0);   // UL LDI (last nibble @ pc3 -> mem_addr=1)
            validate(5, 1, 16'h00AB, 1'b0);   // LK8 LDI (last nibble @ pc10 -> mem_addr=5)
            validate(10, 1, 16'h1234, 1'b0);  // LK16 LDI (last nibble @ pc20 -> mem_addr=10)
        join_none

        #200;
        $display("TB GLOBAL PASS");
        $finish;
    end

    // Parametric validation: wait for read of addr, check data, then check ACC after cycles
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
                $display("FAIL DATA @%0d: got=%h exp=%h", addr, test_data, expected_acc);
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
        $dumpfile("tb_misao_global.vcd");
        $dumpvars(0, tb_misao_global);
    end

endmodule
