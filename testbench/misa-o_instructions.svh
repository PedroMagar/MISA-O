`ifndef MISAO_INSTR_SVH
`define MISAO_INSTR_SVH

// Base opcodes (4-bit)
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

// Extended opcodes (4-bit)
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

`endif
