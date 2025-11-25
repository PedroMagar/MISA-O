`timescale 1ns / 1ps

module tb_control_branch;

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
    //

    reg clk;
    reg rst;
    reg [7:0] mem_data_in;

    wire        mem_enable_read;
    wire        mem_enable_write;
    wire [14:0] mem_addr;
    wire        mem_rw;
    wire [7:0]  mem_data_out;
    wire [15:0] test_data;

    misao dut (
        .clk(clk), 
        .rst(rst), 
        .mem_enable_read(mem_enable_read), 
        .mem_enable_write(mem_enable_write), 
        .mem_data_in(mem_data_in), 
        .mem_addr(mem_addr), 
        .mem_rw(mem_rw), 
        .mem_data_out(mem_data_out), 
        .test_data(test_data)
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
        if (mem_enable_read) begin
            mem_data_in <= memory[mem_addr];
        end
    end

    initial begin
        $dumpfile("waves_branch.vcd");
        $dumpvars(0, tb_control_branch);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // Program: first BEQZ taken, second not taken; final ACC=0x5
        memory[0] = {CFG, XOP};    // XOP CFG
        memory[1] = {4'h0, 4'hC};  // cfg = 0x0C (UL, imm4)
        memory[2] = {4'h0, LDI};   // LDI #0
        memory[3] = {4'h2, BEQZ};  // BEQZ +2 (skip next LDI)
        memory[4] = {4'hF, LDI};   // skipped if branch taken
        memory[5] = {4'hA, LDI};   // ACC=0xA (branch target)
        memory[6] = {4'h1, LDI};   // ACC=1
        memory[7] = {4'h2, BEQZ};  // BEQZ +2 (should NOT branch)
        memory[8] = {4'h5, LDI};   // ACC=5 (expected)
        memory[9] = {NOP, NOP};

        #50; rst = 0;
        #600;

        assert (test_data[3:0] == 4'h5)
            else $fatal(1, "BRANCH FAIL: ACC=%h (expected 0x5)", test_data);
        $display("BRANCH PASS: first BEQZ taken, second not taken");
        $finish;
    end

endmodule
