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
        memory[1]  = {4'h5, LDI};     // pc2: LDI UL, pc3: imm=5

        memory[2]  = {CFG , XOP};     // pc4: XOP, pc5: CFG
        memory[3]  = {4'h0, 4'hD};    // pc6: imm_low=D, pc7: imm_high=0 (CFG=0x0D -> LK8)

        memory[4]  = {4'hB, LDI};     // pc8: LDI (LK8), pc9: imm_low=B
        memory[5]  = {4'h0, 4'hA};    // pc10: imm_high=A

        memory[6]  = {CFG , XOP};     // pc12: XOP, pc13: CFG
        memory[7]  = {4'h0, 4'hE};    // pc14: imm_low=E, pc15: imm_high=0 (CFG=0x0E -> LK16)

        memory[8]  = {4'h4, LDI};     // pc16: LDI (LK16), pc17: imm0=4
        memory[9]  = {4'h2, 4'h3};    // pc18: imm1=3, pc19: imm2=2
        memory[10] = {NOP , 4'h1};    // pc20: imm3=1

        // Reset
        rst = 1'b1;
        #20;
        rst = 1'b0;

        // Parallel validators
        fork
            validate(15'd1, 1, 16'h0005);   // UL LDI (last nibble @ pc3 -> mem_addr=1)
            validate(15'd5, 1, 16'h00AB);   // LK8 LDI (last nibble @ pc10 -> mem_addr=5)
            validate(15'd10, 1, 16'h1234);  // LK16 LDI (last nibble @ pc20 -> mem_addr=10)
        join_none

        #200;
        $display("TB GLOBAL PASS");
        $finish;
    end

    // Parametric validation: wait for read of addr, check data, then check ACC after cycles
    task automatic validate(input [14:0] addr, input integer cycles, input [3:0] expected);
        begin
            // Wait for desired address read
            @(negedge clk);
            while (!(mem_enable_read && mem_addr == addr)) @(negedge clk);
            if (mem_data_in !== memory[addr]) begin
                $display("FAIL READ @%0d: mem_data_in=%02h exp=%02h", addr, mem_data_in, memory[addr]);
                $fatal(1);
            end
            // Wait 'cycles' negedges before ACC check
            repeat (cycles) @(negedge clk);
            if (test_data[3:0] !== expected) begin
                $display("FAIL GLOBAL RESULT @%0d: ACC=%h exp_low=%h", addr, test_data, expected);
                $fatal(1);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_misao_global.vcd");
        $dumpvars(0, tb_misao_global);
    end

endmodule
