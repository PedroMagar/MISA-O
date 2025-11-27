`timescale 1ns / 1ps
`include "testbench/misa-o_instructions.svh"

module tb_management;

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
        $dumpfile("waves_management.vcd");
        $dumpvars(0, tb_management);

        rst = 1;
        mem_data_in = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 8'h00;

        // ================================================================
        // Test Sequence (Management)
        // ================================================================
        
        // Phase 1: Setup & Pattern Loading (LK16)
        memory[1] = {CFG, XOP};
        memory[2] = {4'h4, 4'hE}; // LK16
        memory[3] = {4'hA, LDI};
        memory[4] = {4'hA, 4'hA};
        memory[5] = {4'h0, 4'hA};

        // Phase 2: SS in UL
        memory[6] = {CFG, XOP};
        memory[7] = {4'h4, 4'hC}; // UL
        memory[8] = {4'h1, LDI};
        memory[9] = {SS , NOP};
        memory[10] = {4'h2, LDI};
        memory[11] = {SS , NOP};

        // Phase 3: SA in UL
        memory[12] = {SA , XOP};
        memory[13] = {4'h5, LDI};
        memory[14] = {SA , XOP};

        // Phase 4: RSS (LK16)
        memory[15] = {CFG, XOP};
        memory[16] = {4'h4, 4'hE};
        memory[17] = {4'hB, LDI};
        memory[18] = {4'hB, 4'hB};
        memory[19] = {4'h0, 4'hB};
        memory[20] = {SS , NOP};
        memory[21] = {RSS, NOP};
        memory[22] = {4'hC, LDI};
        memory[23] = {4'hC, 4'hC};
        memory[24] = {4'h0, 4'hC};
        memory[25] = {SS , NOP};
        memory[26] = {RSS, NOP};
        memory[27] = {SS , NOP};

        // Phase 5: RSA
        memory[28] = {4'h1, LDI};
        memory[29] = {4'h1, 4'h1};
        memory[30] = {4'h0, 4'h1};
        memory[31] = {SA , XOP};
        memory[32] = {RSA, XOP};
        memory[33] = {4'h2, LDI};
        memory[34] = {4'h2, 4'h2};
        memory[35] = {4'h0, 4'h2};
        memory[36] = {SA , XOP};
        memory[37] = {RSA, XOP};
        memory[38] = {SA , XOP};

        // Phase 6: RRS in UL
        memory[39] = {CFG, XOP};
        memory[40] = {4'h4, 4'hC};
        memory[41] = {4'h4, LDI};
        memory[42] = {SS , NOP};
        memory[43] = {4'h1, LDI};
        memory[44] = {SS , NOP};
        memory[45] = {RRS, XOP};
        memory[46] = {SS , NOP};

        // Phase 7: RRS NOP in LK16
        memory[47] = {CFG, XOP};
        memory[48] = {4'h4, 4'hE}; // LK16
        memory[49] = {4'h5, LDI};  // ACC=0x0005
        memory[50] = {SS , NOP};   // RS0=0x0005
        memory[51] = {RRS, XOP};   // Should be NOP
        memory[52] = {SS , NOP};   // ACC should remain 0x0005

        // ================================================================
        // Execution & Checks
        // ================================================================
        
        #50; rst = 0;

        validate(15'h000C, 1, 16'hAAA1, 1'b0);
        validate(15'h000F, 1, 16'hAAA1, 1'b0);
        validate(15'h001C, 1, 16'hBBBB, 1'b0);
        validate(15'h0027, 1, 16'h1111, 1'b0);
        validate(15'h002F, 1, 16'h0000, 1'b0);
        validate(15'h0034, 1, 16'h0005, 1'b0);

        $display("MANAGEMENT TEST DONE (validations)");
        $finish;
    end

endmodule
