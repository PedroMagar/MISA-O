module misao (
    input wire        clk,              // Clock signal
    input wire        rst,              // Reset signal

    input wire        mem_enable_read,  // Controls whether to read from memory
    input wire        mem_enable_write, // Controls whether to write to memory
    input wire  [3:0] mem_data_in,     // Input data from memory (4 bits)
    output reg [15:0] mem_addr,         // Address to read/write in memory

    output reg        mem_rw,           // Read/Write control signal
    output wire [3:0] mem_data_out,     // Output data to memory (4 bits)
    output wire [3:0] test_data         // Data for testing purposes
);
    // Parameters to define operation modes
        localparam [1:0] UL = 2'b00;  // Unlink mode (4-bit)
        localparam [1:0] LK8 = 2'b01;  // Link mode (8-bit)
        localparam [1:0] LK16 = 2'b10; // Link mode (16-bit)

        // Instruction opcodes
            localparam [3:0] AND  = 4'b0001;
            localparam [3:0] OR   = 4'b0101;
            localparam [3:0] XOR  = 4'b1001;
            localparam [3:0] SHF  = 4'b1101;
            localparam [3:0] ADDC = 4'b0011;
            localparam [3:0] INC  = 4'b1011;
            localparam [3:0] BEQZ = 4'b0111;
            localparam [3:0] JAL  = 4'b1111;
            localparam [3:0] NEG  = 4'b0010;
            localparam [3:0] RR   = 4'b0110;
            localparam [3:0] SR   = 4'b1010;
            localparam [3:0] SA   = 4'b1010;
            localparam [3:0] LK   = 4'b1110;
            localparam [3:0] LD   = 4'b0100;
            localparam [3:0] LDI  = 4'b1100;
            localparam [3:0] SW   = 4'b1000;
            localparam [3:0] NOP  = 4'b0000;
        //

    //

    // Internal registers and wires
    reg [15:0] pc;                  // Program Counter
    wire [15:0] pc_jmp;             // Program Counter
    wire [15:0] data_addr;          // Address for data access
    wire flag_jmp;
    wire flag_jmp_ul;
    wire flag_jmp_lk8;
    wire flag_jmp_lk16;

    reg [3:0] bank_0 [4];           // Operand registers (4)
    reg [15:0] bank_1 [2];          // Operator registers (2 x 16-bit)
    reg [15:0] bank_addr [2];       // Memory address registers (2 x 16-bit)

    reg [3:0] instruction;           // Current instruction being executed

    reg operation_mode;              // Current operation mode (linked/unlinked)
    reg operation_carry;             // Carry flag for arithmetic operations
    reg [1:0] link_state;            // Current state for link mode

    reg flag_mem_write;              // Flag to indicate a write operation in memory
    reg flag_pc_hold;                // Flag to hold the program counter
    reg flag_pc_data;                // Flag to control data output from PC
    reg flag_ld;                     // Flag for Load operation
    reg flag_ldi;                    // Flag for Load Immediate operation
    reg flag_write;                  // General write operation flag
    reg flag_write_end;              // Flag to indicate write operation completion

    reg [4:0] math_result;           // Register for math result storage (not yet used)

    // assign test_data = bank_0[0];                           // Assign test data for verification
    assign mem_addr = (flag_pc_data) ? pc : {bank_addr[0]}; // Select address based on flags

    // Memory output data assignment
    assign mem_data_out = (mem_enable_write & !mem_enable_read) ? bank_0[0] : 4'bz; // Control memory read/write

    assign pc_jmp = bank_addr[0];   // Defining address if jump

    assign flag_jmp_ul = (bank_0[0] == 4'b0) ? 1'b1 : 1'b0;
    assign flag_jmp_lk8 = (flag_jmp_ul & bank_0[1] == 4'b0) ? 1'b1 : 1'b0;
    assign flag_jmp_lk16 = (flag_jmp_lk8 & {bank_0[2], bank_0[3]} == 8'b00000000) ? 1'b1 : 1'b0;

    assign flag_jmp = (
        (instruction == JAL ||
        (instruction == BEQZ && operation_mode && operation_carry) || 
        (instruction == BEQZ && !operation_mode && 
        ((link_state == UL && flag_jmp_ul) || 
         (link_state == LK8 && flag_jmp_lk8) || 
         (link_state == LK16 && flag_jmp_lk16)
        ))
        ) && !mem_enable_write
    ) ? 1'b1 : 1'b0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            instruction <= 4'b0;
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
            link_state <= UL;

            foreach (bank_0[i]) bank_0[i] <= 4'b0;
            foreach (bank_1[i]) bank_1[i] <= 16'b0;
            foreach (bank_addr[i]) bank_addr[i] <= 16'b0;
        end else begin

            pc <= (flag_pc_hold || !mem_enable_read) ? pc : (flag_jmp) ? pc_jmp : pc + 1;

            // Fetch instruction if not in hold state
            if (!flag_pc_hold & mem_enable_read & !flag_ldi) begin
                instruction <= mem_data_in;

                // Instruction Decode
                case (mem_data_in)
                    AND :   begin
                                case(link_state) // Check link state for operation
                                    UL  : bank_0[0] <= (operation_mode) ? !(bank_0[0] & bank_1[0][3:0]) : bank_0[0] & bank_1[0][3:0];
                                    LK8 : {bank_0[1], bank_0[0]} <= (operation_mode) ? !({bank_0[1], bank_0[0]} & bank_1[0][7:0]) : {bank_0[1], bank_0[0]} & bank_1[0][7:0];
                                    LK16: {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} <= (operation_mode) ? !({bank_0[3], bank_0[2], bank_0[1], bank_0[0]} & bank_1[0][15:0]) : {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} & bank_1[0][15:0];
                                    default ;
                                endcase
                            end
                    OR  :   begin
                                case(link_state)
                                    UL  : bank_0[0] <= (operation_mode) ? !(bank_0[0] | bank_1[0][3:0]) : bank_0[0] | bank_1[0][3:0];
                                    LK8 : {bank_0[1], bank_0[0]} <= (operation_mode) ? !({bank_0[1], bank_0[0]} | bank_1[0][7:0]) : {bank_0[1], bank_0[0]} | bank_1[0][7:0];
                                    LK16: {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} <= (operation_mode) ? !({bank_0[3], bank_0[2], bank_0[1], bank_0[0]} | bank_1[0][15:0]) : {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} | bank_1[0][15:0];
                                    default ;
                                endcase
                            end
                    XOR :   begin
                                case(link_state)
                                    UL  : bank_0[0] <= (operation_mode) ? !(bank_0[0] ^ bank_1[0][3:0]) : bank_0[0] ^ bank_1[0][3:0];
                                    LK8 : {bank_0[1], bank_0[0]} <= (operation_mode) ? !({bank_0[1], bank_0[0]} ^ bank_1[0][7:0]) : {bank_0[1], bank_0[0]} ^ bank_1[0][7:0];
                                    LK16: {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} <= (operation_mode) ? !({bank_0[3], bank_0[2], bank_0[1], bank_0[0]} ^ bank_1[0][15:0]) : {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} ^ bank_1[0][15:0];
                                    default ;
                                endcase
                            end
                    SHF :   begin 
                                case(link_state)
                                    UL  : if (operation_mode) {bank_0[0], operation_carry} <= bank_0[0] >> 1; else {operation_carry, bank_0[0]} <= bank_0[0] << 1;
                                    LK8 : if (operation_mode) {bank_0[1], bank_0[0], operation_carry} <= {bank_0[1], bank_0[0]} >> 1; else {operation_carry, bank_0[1], bank_0[0]} <= {bank_0[1], bank_0[0]} << 1;
                                    LK16: if (operation_mode) {bank_0[3], bank_0[2], bank_0[1], bank_0[0], operation_carry} <= {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} >> 1; else {operation_carry, bank_0[3], bank_0[2], bank_0[1], bank_0[0]} <= {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} << 1;
                                    default ;
                                endcase
                            end
                    ADDC:   begin 
                                case(link_state)
                                    UL  : {operation_carry, bank_0[0]} <= (operation_mode) ? bank_0[0] - bank_1[0][3:0] - operation_carry : bank_0[0] + bank_1[0][3:0] + operation_carry;
                                    LK8 : {operation_carry, bank_0[1], bank_0[0]} <= (operation_mode) ? {bank_0[1], bank_0[0]} - bank_1[0][7:0] - operation_carry : {bank_0[1], bank_0[0]} + bank_1[0][7:0] + operation_carry;
                                    LK16: {operation_carry, bank_0[3], bank_0[2], bank_0[1], bank_0[0]} <= (operation_mode) ? {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} - bank_1[0][15:0] - operation_carry : {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} + bank_1[0][15:0] + operation_carry;
                                    default ;
                                endcase
                            end
                    INC :   begin 
                                case(link_state)
                                    UL  : {operation_carry, bank_0[0]} <= (operation_mode) ? bank_0[0] - 1 : bank_0[0] + 1;
                                    LK8 : {operation_carry, bank_0[1], bank_0[0]} <= (operation_mode) ? {bank_0[1], bank_0[0]} - 1 : {bank_0[1], bank_0[0]} + 1;
                                    LK16: {operation_carry, bank_0[3], bank_0[2], bank_0[1], bank_0[0]} <= (operation_mode) ? {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} - 1 : {bank_0[3], bank_0[2], bank_0[1], bank_0[0]} + 1;
                                    default ;
                                endcase
                            end
                    BEQZ:   ;
                    JAL :   bank_addr[1] <= (operation_mode) ? pc : bank_addr[1];   // Link the current pc (return address) into bank_addr[1]
                    NEG :   operation_mode <= !operation_mode;
                    RR  :   begin
                                if (operation_mode)
                                begin
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
                                    UL : link_state <= LK8;
                                    LK8 : link_state <= LK16;
                                    LK16: link_state <= UL;
                                    default: link_state <= UL;
                                endcase
                            end
                    LD  :   begin flag_pc_hold <= 1'b1; flag_ld  <= 1'b1; flag_pc_data <= 1'b0; operation_carry <= 1'b0; end
                    LDI :   begin flag_ldi <= 1'b1; operation_carry <= 1'b0; end
                    SW  :   begin flag_pc_hold <= 1'b1; flag_pc_data <= 1'b0; flag_mem_write <= 1'b1; mem_rw <= 1'b0; end
                    NOP :   ;
                    default: ;
                endcase

            end

            // Logic to execute Load and Store operations...

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

            //

        end
    end

endmodule
