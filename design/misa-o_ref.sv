module misao (
    input wire        clk,
    input wire        rst,

    input wire        mem_enable_read,
    input wire        mem_enable_write,
    input wire  [3:0] mem_data_in,
    output reg [15:0] mem_addr,

    output reg        mem_rw,
    output wire [3:0] mem_data_out,
    output wire [3:0] test_data
);
    // Parâmetros
        localparam [3:0] PARAM_EX = 4'b0000;

        localparam [1:0] BM4 = 2'b00;
        localparam [1:0] BM8 = 2'b01;
        localparam [1:0] BM16 = 2'b10;

        // Instruções
            localparam [3:0] AND  = 4'b0001;
            localparam [3:0] OR   = 4'b0101;
            localparam [3:0] XOR  = 4'b1001;
            localparam [3:0] SHF  = 4'b1101;
            localparam [3:0] ADDC = 4'b0011;
            localparam [3:0] INC  = 4'b1011;
            localparam [3:0] BEQZ = 4'b0111;
            localparam [3:0] JAL  = 4'b1111;
            localparam [3:0] NEG  = 4'b0010;
            localparam [3:0] RR   = 4'b1010;
            localparam [3:0] SR   = 4'b0110;
            localparam [3:0] SA   = 4'b0110;
            localparam [3:0] LK   = 4'b1110;
            localparam [3:0] LD   = 4'b0100;
            localparam [3:0] LDI  = 4'b1100;
            localparam [3:0] SW   = 4'b1000;
            localparam [3:0] NOP  = 4'b0000;
        //

    //

    reg [15:0] pc;
    wire [15:0] data_addr;

    reg [3:0] bank_0 [4];
    reg [15:0] bank_1 [2];
    reg [15:0] bank_addr [2];

    reg [3:0] instruction;

    reg operation_mode;
    reg operation_carry;
    reg [1:0] link_state;

    reg flag_mem_write;
    reg flag_pc_hold;
    reg flag_pc_data;
    reg flag_ld;
    reg flag_ldi;
    reg flag_write;
    reg flag_write_end;

    reg [4:0] math_result;

    assign test_data = bank_0[0];
    assign mem_addr = (flag_pc_data) ? pc : {bank_addr[0]} ;

    assign mem_data_out = (mem_enable_write & !mem_enable_read) ? bank_0[0] : 4'bz ;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            instruction <= 4'b0; // debug
            pc <= 16'b0;
            flag_pc_hold <= 1'b0;
            flag_pc_data <= 1'b1;
            flag_ld <= 1'b0;
            flag_ldi <= 1'b0;
            flag_write <= 1'b0;
            flag_write_end <= 1'b0;
            mem_rw <= 1'b1;
            flag_mem_write <= 1'b0;
            operation_mode <= 1'b0;
            operation_carry <= 1'b0;
            link_state <= BM4;

            foreach (bank_0[i]) bank_0[i] <= 4'b0;
            foreach (bank_1[i]) bank_1[i] <= 4'b0;
            foreach (bank_addr[i]) bank_addr[i] <= 4'b0;
        end else begin

            pc <= (flag_pc_hold || !mem_enable_read) ? pc : pc + 1;

            // Fetch instruction if not to hold
            if (!flag_pc_hold & mem_enable_read & !flag_ldi) begin
                instruction <= mem_data_in;

                // Instruction Decode
                case (mem_data_in)
                    AND :   bank_0[0] <= (operation_mode) ? !(bank_0[0] & bank_1[0][3:0]) : bank_0[0] & bank_1[0][3:0];
                    OR  :   bank_0[0] <= (operation_mode) ? !(bank_0[0] | bank_1[0][3:0]) : bank_0[0] | bank_1[0][3:0];
                    XOR :   bank_0[0] <= (operation_mode) ? !(bank_0[0] ^ bank_1[0][3:0]) : bank_0[0] ^ bank_1[0][3:0];
                    SHF :   begin 
                                if (operation_mode) begin
                                    operation_carry <= bank_0[0][0];
                                    bank_0[0] <= bank_0[0] >> 1;
                                end else begin
                                    operation_carry <= bank_0[0][3];
                                    bank_0[0] <= bank_0[0] << 1;
                                end
                            end
                    ADDC:   {operation_carry, bank_0[0]} <= (operation_mode) ? bank_0[0] - bank_1[0][3:0] - operation_carry : bank_0[0] + bank_1[0][3:0] + operation_carry;
                    INC :   {operation_carry, bank_0[0]} <= (operation_mode) ? bank_0[0] - 1  : bank_0[0] + 1;
                    BEQZ:   if (bank_0[0] == 4'b0) pc <= pc + 16;
                    JAL :   begin pc <= bank_addr[0]; bank_addr[0] <= pc; end
                    NEG :   operation_mode <= ! operation_mode;
                    RR  :   begin
                                if (operation_mode) begin
                                    bank_0[0] <= bank_0[3]; 
                                    bank_0[1] <= bank_0[0]; 
                                    bank_0[2] <= bank_0[1]; 
                                    bank_0[3] <= bank_0[2]; 
                                end else begin
                                    bank_0[0] <= bank_0[1]; 
                                    bank_0[1] <= bank_0[2]; 
                                    bank_0[2] <= bank_0[3]; 
                                    bank_0[3] <= bank_0[0]; 
                                end
                            end
                    'hA :  begin
                                if (!operation_mode)
                                begin
                                    {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} <= bank_1[0];
                                    bank_1[0] <= bank_1[1];
                                    bank_1[1] <= {bank_0[3], bank_0[2], bank_0[1], bank_0[0]};
                                end else begin
                                    {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} <= bank_addr[0];
                                    bank_addr[0] <= bank_addr[1];
                                    bank_addr[1] <= {bank_0[3], bank_0[2], bank_0[1], bank_0[0]};
                                end
                            end
                    LK  :   begin
                                case (link_state)
                                    BM4 : link_state <= BM8;
                                    BM8 : link_state <= BM16;
                                    BM16: link_state <= BM4;
                                    default: link_state <= BM4;
                                endcase
                            end
                    LD  :   begin flag_pc_hold <= 1'b1; flag_ld  <= 1'b1; flag_pc_data <= 1'b0; operation_carry <= 1'b0; end
                    LDI :   begin flag_ldi <= 1'b1; operation_carry <= 1'b0; end
                    SW  :   begin flag_pc_hold <= 1'b1; flag_pc_data <= 1'b0; flag_mem_write <= 1'b1; mem_rw <= 1'b0; end
                    NOP :   ;
                    default: ;
                endcase

            end

            // Executing Load
            if (flag_ld) begin
                bank_0[0] <= mem_data_in;
                flag_ld <= 1'b0;
                flag_pc_hold <= 1'b0;
                flag_pc_data <= 1'b1;
            end

            // Executing Load Immediate
            if (flag_ldi) begin
                bank_0[0] <= mem_data_in;
                flag_ldi <= 1'b0;
                flag_pc_hold <= 1'b0;
            end

            // Executing Write (Store Word)
            if (flag_mem_write) begin
                flag_mem_write <= 1'b0;
                mem_rw <= 1'b1;
                flag_pc_data <= 1'b1;
                flag_pc_hold <= 1'b0;
            end

        end
    end

endmodule
