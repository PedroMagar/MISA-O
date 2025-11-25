`timescale 1ns / 1ps

module tb_misao_global;

    // Instructions
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
    wire [15:0]  test_data;

    misao dut (
        .clk(clk),
        .rst(rst),
        .mem_rw(mem_rw),
        .mem_enable_read(mem_enable_read),
        .mem_enable_write(mem_enable_write),
        .mem_data_in(mem_data_in),
        .mem_data_out(mem_data_out),
        .mem_addr(mem_addr),
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
        $dumpfile("waves_global.vcd");
        $dumpvars(0, tb_misao_global);

        rst = 1;
        mem_data_in = 0;

        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // Validation program for updated ISA (nibble addressing):
        // - XOP+CFG -> cfg = 0x0C (UL, imm4, CEN=1, SIGN=1)
        // - LDI/SS -> RS0 = 3
        // - LDI/ADD -> ACC = 8
        // - XOP INV/XOR/SUB, INC, SHL, XOP SHR
        // - XOP+CFG -> cfg = 0x0E (LK16); LDI 0x0020; XOP SA -> RA0 = 0x0020
        // - XOP+CFG -> cfg = 0x0C (UL); LDI 0xA
        // - XMEM store/load @RA0 -> final ACC 0xA and memory[0x10] = 0x0A
        memory[0]  = {CFG , XOP };
        memory[1]  = {4'h0, 4'hC};            // cfg = 0x0C
        memory[2]  = {4'h3, LDI };            // LDI #3
        memory[3]  = {LDI , SS  };            // SS ; LDI
        memory[4]  = {ADD , 4'h5};            // imm #5 ; ADD (ACC=8)
        memory[5]  = {INV , XOP };            // XOP INV
        memory[6]  = {XOR , XOP };            // XOP XOR
        memory[7]  = {SUB , XOP };            // XOP SUB
        memory[8]  = {SHL , INC };            // INC ; SHL
        memory[9]  = {SHR , XOP };            // XOP SHR
        memory[10] = {CFG , XOP };            // XOP CFG (entering LK16)
        memory[11] = {4'h0, 4'hE};            // imm_cfg = 0x0E
        memory[12] = {4'h0, LDI };            // LDI parte baixa ra0 = 0x0020
        memory[13] = {4'h0, 4'h2};
        memory[14] = {XOP , 4'h0};            // 
        memory[15] = {XOP , SA  };            // SA (swap ACC<->RA0) with previous XOP
        memory[16] = {4'hC, CFG };            // XOP CFG (renturning to UL)
        memory[17] = {4'h4, 4'h0};            // cfg imm2=0 ; next nibble (upper) = LDI opcode
        memory[18] = {XMEM, 4'hA};            // LDI imm = A (lower); XMEM store (upper)
        memory[19] = {4'h4, 4'h8};            // XOP ; LDI (upper executa como SIA via XOP)
        memory[20] = {XMEM, 4'h0};            // XMEM load (f=0x0 -> load, no post-inc, ra0)
        memory[21] = {4'h0, 4'h0};

        #100;
        rst = 0;

        // Let program run then report ACC/memory snapshot
        #1500;
        $display("GLOBAL DONE: ACC=%h mem[0x10]=%h", test_data, memory[8'h10]);

        $finish;
    end

endmodule
