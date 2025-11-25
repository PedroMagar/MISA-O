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
        $dumpfile("waves_special.vcd");
        $dumpvars(0, tb_special);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // Exercise swaps/rotations: SS (2x), RSS (2x), SA (2x), RSA (2x), RRS (2x), RACC (2x)
        // Config: start UL (0x0C), then LK8 (0x0D), LK16 (0x0E) to load ACC, return to LK8 for RACC.
        memory[0]  = {CFG, XOP};   // XOP CFG -> UL
        memory[1]  = {4'h0, 4'hC};

        memory[2]  = {4'h2, LDI};  // LDI #2 (UL)
        memory[3]  = {RSS, SS};    // SS (rs0=2); RSS #1 (rs0<->rs1)

        memory[4]  = {4'h7, LDI};  // LDI #7
        memory[5]  = {RSS, SS};    // SS (rs0=7); RSS #2 (rs0=2, rs1=7)

        memory[6]  = {4'h5, LDI};  // LDI #5
        memory[7]  = {SA, XOP};    // XOP; SA #1 (ra0=5)

        memory[8]  = {RSA, XOP};   // XOP; RSA #1 (ra1=5, ra0=0)

        memory[9]  = {4'h6, LDI};  // LDI #6
        memory[10] = {SA, XOP};    // XOP; SA #2 (ra0=6)

        memory[11] = {RSA, XOP};   // XOP; RSA #2 (ra0=5, ra1=6)

        // Switch to LK8 to load rs0=0x00AB and apply RRS; then LK16 to load ACC 0x1234; return to LK8 for RACC
        memory[12] = {CFG, XOP};   // XOP CFG -> LK8
        memory[13] = {4'h0, 4'hD};

        memory[14] = {4'hB, LDI};  // LDI #0xAB (LK8) part 1
        memory[15] = {SS, 4'hA};   // imm2=A ; SS moves ACC->rs0

        memory[16] = {RRS, XOP};   // XOP; RRS #1 (rs0=0xAB00)
        memory[17] = {RRS, XOP};   // XOP; RRS #2 (rs0=0x00AB)

        memory[18] = {CFG, XOP};   // XOP CFG -> LK16
        memory[19] = {4'h0, 4'hE};

        memory[20] = {4'h4, LDI};  // LDI 0x1234 (LK16) imm1=4
        memory[21] = {4'h2, 4'h3}; // imm2=3 (low), imm3=2 (high of byte)
        memory[22] = {XOP , 4'h1}; // imm4=1 (low), XOP (high) for next CFG

        memory[23] = {4'hD, CFG};  // CFG opcode (low), imm_low=D (high)
        memory[24] = {RACC, 4'h0}; // imm_high=0 (low), RACC #1 (high)
        memory[25] = {NOP, RACC};  // RACC #2 (low), NOP (high)

        #50; rst = 0;
        #1200;

        assert (test_data == 16'h3412)
            else $fatal(1, "RACC FAIL: ACC=%h (expected 0x3412)", test_data);
        assert (dut.bank_1[0] == 16'h00AB)
            else $fatal(1, "RRS/RSS/SS FAIL: RS0=%h (expected 0x00AB)", dut.bank_1[0]);
        assert (dut.bank_1[1] == 16'h0007)
            else $fatal(1, "RSS FAIL: RS1=%h (expected 0x0007)", dut.bank_1[1]);
        assert (dut.bank_addr[0] == 16'h0005 && dut.bank_addr[1] == 16'h0006)
            else $fatal(1, "SA/RSA FAIL: RA0=%h RA1=%h (expected 0x0005/0x0006)", dut.bank_addr[0], dut.bank_addr[1]);

        $display("SPECIAL PASS: SS/RSS/SA/RSA/RRS/RACC exercised twice each");
        $finish;
    end

endmodule
