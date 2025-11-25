`timescale 1ns / 1ps

module tb_alu_shift;

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
        $dumpfile("waves_shift.vcd");
        $dumpvars(0, tb_alu_shift);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // Program: SHL and SHR with carry check via BC; also INC/DEC
        memory[0] = {CFG, XOP};      // XOP CFG
        memory[1] = {4'h0, 4'hC};    // cfg = 0x0C (UL, imm4, carry on)
        memory[2] = {4'h9, LDI};     // LDI #9 -> ACC=9
        memory[3] = {BC, SHL};       // SHL (ACC=2, carry=1); BC validates carry
        memory[4] = {LDI, 4'h2};     // imm for BC=+2; LDI if BC fails
        memory[5] = {SHR, 4'h0};     // imm for LDI fail=0; SHR (ACC=1, carry=0)
        memory[6] = {4'h2, BC};      // BC should NOT branch (carry=0), imm=+2
        memory[7] = {DEC, INC};      // INC ->2 ; DEC ->1
        memory[8] = {NOP, NOP};

        #50;  rst = 0;
        #500;

        assert (test_data[3:0] == 4'h1)
            else $fatal(1, "SHIFT FAIL: ACC=%h (expected 0x1)", test_data);
        $display("SHIFT PASS: SHL/SHR + INC/DEC");
        $finish;
    end

endmodule
