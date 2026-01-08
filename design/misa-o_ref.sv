module misao (
    input  wire        clk,
    input  wire        rst,

    output wire        mem_enable_read,
    output wire        mem_enable_write,
    input  wire [7:0]  mem_data_in,
    output reg  [14:0] mem_addr,

    output wire        mem_rw,
    output wire [7:0]  mem_data_out,
    output wire [15:0] test_data,
    output wire        test_carry
);
    // Link modes
    localparam [1:0] UL   = 2'b00;
    localparam [1:0] LK8  = 2'b01;
    localparam [1:0] LK16 = 2'b10;

    // Opcodes (5-bit: {flag_xop, nibble})
    localparam [4:0] LDI  = 5'b00100;
    localparam [4:0] XOP  = 5'b01000;
    localparam [4:0] CFG  = 5'b00010;
    localparam [4:0] ADD  = 5'b00001;
    localparam [4:0] INC  = 5'b01001;
    localparam [4:0] AND  = 5'b00101;
    localparam [4:0] OR   = 5'b01101;
    localparam [4:0] SHL  = 5'b00011;
    localparam [4:0] SS   = 5'b01110;
    localparam [4:0] SA   = 5'b11110;
    localparam [4:0] RSS  = 5'b01010;
    localparam [4:0] RSA  = 5'b11010;
    localparam [4:0] RRS  = 5'b10110;
    localparam [4:0] RACC = 5'b00110;
    localparam [4:0] SUB  = 5'b10001;
    localparam [4:0] DEC  = 5'b11001;
    localparam [4:0] INV  = 5'b10101;
    localparam [4:0] XOR  = 5'b11101;
    localparam [4:0] SHR  = 5'b10011;

    // Registers
    reg [15:0] pc;                   // Nibble-addressed PC
    reg [3:0]  bank_acc [4];         // 4x4-bit accumulator nibbles
    reg [15:0] bank_src [2];
    reg [15:0] bank_adr [2];

    // Flags / cfg
    reg flag_xop;
    reg flag_bw;                     // Branch Immediate Width
    reg flag_brs;                    // Branch Relative Scale
    reg flag_ie;
    reg flag_cen;                    // Carry-in Enable (CI)
    reg flag_imm;
    reg flag_sign;
    reg [1:0] link_state;

    reg operation_carry;

    // LDI helpers
    reg        ldi_pending;
    reg [2:0]  ldi_remaining;
    reg [2:0]  ldi_index;
    reg [15:0] ldi_shift;

    // CFG helpers
    reg        cfg_pending;
    reg [1:0]  cfg_remaining;
    reg [1:0]  cfg_index;
    reg [7:0]  cfg_shift;

    // ALU immediate helpers
    reg        imm_pending;
    reg [2:0]  imm_remaining;
    reg [2:0]  imm_index;
    reg [15:0] imm_shift;
    reg [4:0]  imm_opcode;

    wire [3:0] current_nibble = (pc == 16'h0001) ? mem_data_in[3:0] :
                                pc[0] ? mem_data_in[7:4] : mem_data_in[3:0];
    wire [4:0] instruction    = {flag_xop, current_nibble};
    wire [7:0] cfg_snapshot   = {flag_cen, flag_bw, flag_brs, flag_ie, flag_imm, flag_sign, link_state};

    wire [15:0] dbg_acc = {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]}; // White-box DEBUG
    wire [15:0] dbg_rs0 = bank_src[0];      // White-box DEBUG
    wire [15:0] dbg_rs1 = bank_src[1];      // White-box DEBUG
    wire [15:0] dbg_ra0 = bank_adr[0];      // White-box DEBUG
    wire [15:0] dbg_ra1 = bank_adr[1];      // White-box DEBUG
    wire        dbg_carry = operation_carry;// White-box DEBUG

    // Outputs
    assign test_data  = {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]};
    assign test_carry = operation_carry;
    assign mem_data_out = 8'h00; // not used for now

    // Memory interface (always-on read-only for now)
    assign mem_enable_read  = 1'b1;
    assign mem_enable_write = 1'b0;
    assign mem_rw           = 1'b1;
    // mem_addr is registered on negedge to avoid posedge timing pressure
    always @(negedge clk or posedge rst) begin
        if (rst) mem_addr <= 15'h0;
        else     mem_addr <= (pc == 16'h0001) ? 15'h1 : pc[15:1];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc               <= 16'h0002;
            flag_xop         <= 1'b0;
            flag_bw          <= 1'b1; // imm8 by default
            flag_brs         <= 1'b0;
            flag_ie          <= 1'b0;
            flag_cen         <= 1'b1;
            flag_imm         <= 1'b0;
            flag_sign        <= 1'b1;
            link_state       <= UL;
            operation_carry  <= 1'b0;
            ldi_pending      <= 1'b0;
            cfg_pending      <= 1'b0;
            ldi_remaining    <= 3'd0;
            cfg_remaining    <= 2'd0;
            ldi_index        <= 3'd0;
            cfg_index        <= 2'd0;
            ldi_shift        <= 16'h0;
            cfg_shift        <= 8'h0;
            imm_pending      <= 1'b0;
            imm_remaining    <= 3'd0;
            imm_index        <= 3'd0;
            imm_shift        <= 16'h0;
            imm_opcode       <= 5'h00;
            bank_acc[0]      <= 4'h0;
            bank_acc[1]      <= 4'h0;
            bank_acc[2]      <= 4'h0;
            bank_acc[3]      <= 4'h0;
            bank_src[0]      <= 16'h0;
            bank_src[1]      <= 16'h0;
            bank_adr[0]      <= 16'h0;
            bank_adr[1]      <= 16'h0;
        end else begin
            // Pending CFG collection
            if (cfg_pending) begin
                // capture current nibble into a temp then commit
                reg [7:0] next_cfg;
                next_cfg                = cfg_shift;
                next_cfg[cfg_index*4 +: 4] = current_nibble;
                cfg_shift               <= next_cfg;
                cfg_index               <= cfg_index + 1'b1;
                cfg_remaining           <= cfg_remaining - 1'b1;
                pc                      <= pc + 1'b1;
                if (cfg_remaining == 2'd1) begin
                    cfg_pending <= 1'b0;
                    flag_cen    <= next_cfg[7];
                    flag_bw     <= next_cfg[6];
                    flag_brs    <= next_cfg[5];
                    flag_ie     <= next_cfg[4];
                    flag_imm    <= next_cfg[3];
                    flag_sign   <= next_cfg[2];
                    link_state  <= next_cfg[1:0];
                end
                flag_xop <= 1'b0;
            end
            // Pending LDI collection
            else if (ldi_pending) begin
                reg [15:0] next_ldi;
                next_ldi                       = ldi_shift;
                next_ldi[ldi_index*4 +: 4]     = current_nibble;
                ldi_shift                      <= next_ldi;
                ldi_index                      <= ldi_index + 1'b1;
                ldi_remaining                  <= ldi_remaining - 1'b1;
                pc                             <= pc + 1'b1;
                if (ldi_remaining == 3'd1) begin
                    ldi_pending <= 1'b0;
                    case (link_state)
                        UL: begin
                            bank_acc[0] <= next_ldi[3:0];
                        end
                        LK8: begin
                            bank_acc[0] <= next_ldi[3:0];
                            bank_acc[1] <= next_ldi[7:4];
                        end
                        default: begin
                            bank_acc[0] <= next_ldi[3:0];
                            bank_acc[1] <= next_ldi[7:4];
                            bank_acc[2] <= next_ldi[11:8];
                            bank_acc[3] <= next_ldi[15:12];
                        end
                    endcase
                end
                flag_xop <= 1'b0;
            end
            // Pending ALU immediate collection
            else if (imm_pending) begin
                reg [15:0] next_imm;
                next_imm                       = imm_shift;
                next_imm[imm_index*4 +: 4]     = current_nibble;
                imm_shift                      <= next_imm;
                imm_index                      <= imm_index + 1'b1;
                imm_remaining                  <= imm_remaining - 1'b1;
                pc                             <= pc + 1'b1;
                if (imm_remaining == 3'd1) begin
                    imm_pending <= 1'b0;
                    case (imm_opcode)
                        ADD: begin
                            reg [4:0] sum4;
                            reg [8:0] sum8;
                            reg [16:0] sum16;
                            reg carry_in;
                            carry_in = flag_cen ? operation_carry : 1'b0;
                            if (link_state == UL) begin
                                sum4 = {1'b0, bank_acc[0]} + {1'b0, next_imm[3:0]} + {4'b0, carry_in};
                                bank_acc[0] <= sum4[3:0];
                                operation_carry <= sum4[4];
                            end else if (link_state == LK8) begin
                                sum8 = {1'b0, bank_acc[1], bank_acc[0]} + {1'b0, next_imm[7:0]} + {8'b0, carry_in};
                                {bank_acc[1], bank_acc[0]} <= sum8[7:0];
                                operation_carry <= sum8[8];
                            end else begin
                                sum16 = {1'b0, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} + {1'b0, next_imm} + {16'b0, carry_in};
                                {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= sum16[15:0];
                                operation_carry <= sum16[16];
                            end
                        end
                        SUB: begin
                            reg [4:0] diff4;
                            reg [8:0] diff8;
                            reg [16:0] diff16;
                            reg borrow_in;
                            borrow_in = flag_cen ? operation_carry : 1'b0;
                            if (link_state == UL) begin
                                diff4 = {1'b0, bank_acc[0]} - {1'b0, next_imm[3:0]} - {4'b0, borrow_in};
                                bank_acc[0] <= diff4[3:0];
                                operation_carry <= ({1'b0, bank_acc[0]} < ({1'b0, next_imm[3:0]} + {4'b0, borrow_in}));
                            end else if (link_state == LK8) begin
                                diff8 = {1'b0, bank_acc[1], bank_acc[0]} - {1'b0, next_imm[7:0]} - {8'b0, borrow_in};
                                {bank_acc[1], bank_acc[0]} <= diff8[7:0];
                                operation_carry <= ({1'b0, bank_acc[1], bank_acc[0]} < ({1'b0, next_imm[7:0]} + {8'b0, borrow_in}));
                            end else begin
                                diff16 = {1'b0, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} - {1'b0, next_imm} - {16'b0, borrow_in};
                                {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= diff16[15:0];
                                operation_carry <= ({1'b0, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} < ({1'b0, next_imm} + {16'b0, borrow_in}));
                            end
                        end
                        AND: begin
                            if (link_state == UL) begin
                                bank_acc[0] <= bank_acc[0] & next_imm[3:0];
                            end else if (link_state == LK8) begin
                                {bank_acc[1], bank_acc[0]} <= {bank_acc[1], bank_acc[0]} & next_imm[7:0];
                            end else begin
                                {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} & next_imm;
                            end
                        end
                        OR: begin
                            if (link_state == UL) begin
                                bank_acc[0] <= bank_acc[0] | next_imm[3:0];
                            end else if (link_state == LK8) begin
                                {bank_acc[1], bank_acc[0]} <= {bank_acc[1], bank_acc[0]} | next_imm[7:0];
                            end else begin
                                {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} | next_imm;
                            end
                        end
                        XOR: begin
                            if (link_state == UL) begin
                                bank_acc[0] <= bank_acc[0] ^ next_imm[3:0];
                            end else if (link_state == LK8) begin
                                {bank_acc[1], bank_acc[0]} <= {bank_acc[1], bank_acc[0]} ^ next_imm[7:0];
                            end else begin
                                {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} ^ next_imm;
                            end
                        end
                        default: begin
                        end
                    endcase
                end
                flag_xop <= 1'b0;
            end
            // Normal decode
            else begin
                case (instruction)
                    XOP: begin
                        flag_xop <= 1'b1;
                        pc       <= pc + 1'b1;
                    end
                    CFG: begin
                        cfg_pending   <= 1'b1;
                        cfg_remaining <= 2'd2; // two nibbles
                        cfg_index     <= 2'd0;
                        cfg_shift     <= 8'h00;
                        pc            <= pc + 1'b1;
                        flag_xop      <= 1'b0;
                    end
                    LDI: begin
                        ldi_pending   <= 1'b1;
                        ldi_index     <= 3'd0;
                        ldi_shift     <= 16'h0000;
                        ldi_remaining <= (link_state == UL)  ? 3'd1 :
                                        (link_state == LK8) ? 3'd2 : 3'd4;
                        pc            <= pc + 1'b1;
                        flag_xop      <= 1'b0;
                    end
                    SS: begin
                        // Swap ACC <-> RS0 respecting link width
                        reg [15:0] acc_val;
                        reg [15:0] rs0_val;
                        acc_val = {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]};
                        rs0_val = bank_src[0];
                        case (link_state)
                            UL: begin
                                bank_acc[0] <= rs0_val[3:0];
                                bank_src[0][3:0] <= acc_val[3:0];
                            end
                            LK8: begin
                                bank_acc[0] <= rs0_val[3:0];
                                bank_acc[1] <= rs0_val[7:4];
                                bank_src[0][7:0] <= acc_val[7:0];
                            end
                            default: begin
                                bank_acc[0] <= rs0_val[3:0];
                                bank_acc[1] <= rs0_val[7:4];
                                bank_acc[2] <= rs0_val[11:8];
                                bank_acc[3] <= rs0_val[15:12];
                                bank_src[0] <= acc_val;
                            end
                        endcase
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    ADD: begin
                        if (flag_imm) begin
                            imm_pending   <= 1'b1;
                            imm_index     <= 3'd0;
                            imm_shift     <= 16'h0000;
                            imm_remaining <= (link_state == UL)  ? 3'd1 :
                                             (link_state == LK8) ? 3'd2 : 3'd4;
                            imm_opcode    <= ADD;
                        end else begin
                            reg [4:0] sum4;
                            reg [8:0] sum8;
                            reg [16:0] sum16;
                            reg carry_in;
                            carry_in = flag_cen ? operation_carry : 1'b0;
                            if (link_state == UL) begin
                                sum4 = {1'b0, bank_acc[0]} + {1'b0, bank_src[0][3:0]} + {4'b0, carry_in};
                                bank_acc[0] <= sum4[3:0];
                                operation_carry <= sum4[4];
                            end else if (link_state == LK8) begin
                                sum8 = {1'b0, bank_acc[1], bank_acc[0]} + {1'b0, bank_src[0][7:0]} + {8'b0, carry_in};
                                {bank_acc[1], bank_acc[0]} <= sum8[7:0];
                                operation_carry <= sum8[8];
                            end else begin
                                sum16 = {1'b0, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} + {1'b0, bank_src[0]} + {16'b0, carry_in};
                                {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= sum16[15:0];
                                operation_carry <= sum16[16];
                            end
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    SUB: begin
                        if (flag_imm) begin
                            imm_pending   <= 1'b1;
                            imm_index     <= 3'd0;
                            imm_shift     <= 16'h0000;
                            imm_remaining <= (link_state == UL)  ? 3'd1 :
                                             (link_state == LK8) ? 3'd2 : 3'd4;
                            imm_opcode    <= SUB;
                        end else begin
                            reg [4:0] diff4;
                            reg [8:0] diff8;
                            reg [16:0] diff16;
                            reg borrow_in;
                            borrow_in = flag_cen ? operation_carry : 1'b0;
                            if (link_state == UL) begin
                                diff4 = {1'b0, bank_acc[0]} - {1'b0, bank_src[0][3:0]} - {4'b0, borrow_in};
                                bank_acc[0] <= diff4[3:0];
                                operation_carry <= ({1'b0, bank_acc[0]} < ({1'b0, bank_src[0][3:0]} + {4'b0, borrow_in}));
                            end else if (link_state == LK8) begin
                                diff8 = {1'b0, bank_acc[1], bank_acc[0]} - {1'b0, bank_src[0][7:0]} - {8'b0, borrow_in};
                                {bank_acc[1], bank_acc[0]} <= diff8[7:0];
                                operation_carry <= ({1'b0, bank_acc[1], bank_acc[0]} < ({1'b0, bank_src[0][7:0]} + {8'b0, borrow_in}));
                            end else begin
                                diff16 = {1'b0, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} - {1'b0, bank_src[0]} - {16'b0, borrow_in};
                                {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= diff16[15:0];
                                operation_carry <= ({1'b0, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} < ({1'b0, bank_src[0]} + {16'b0, borrow_in}));
                            end
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    INC: begin
                        reg [4:0] sum4;
                        reg [8:0] sum8;
                        reg [16:0] sum16;
                        if (link_state == UL) begin
                            sum4 = {1'b0, bank_acc[0]} + 5'd1;
                            bank_acc[0] <= sum4[3:0];
                            operation_carry <= sum4[4];
                        end else if (link_state == LK8) begin
                            sum8 = {1'b0, bank_acc[1], bank_acc[0]} + 9'd1;
                            {bank_acc[1], bank_acc[0]} <= sum8[7:0];
                            operation_carry <= sum8[8];
                        end else begin
                            sum16 = {1'b0, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} + 17'd1;
                            {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= sum16[15:0];
                            operation_carry <= sum16[16];
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    DEC: begin
                        reg [4:0] diff4;
                        reg [8:0] diff8;
                        reg [16:0] diff16;
                        if (link_state == UL) begin
                            diff4 = {1'b0, bank_acc[0]} - 5'd1;
                            bank_acc[0] <= diff4[3:0];
                            operation_carry <= ({1'b0, bank_acc[0]} < 5'd1);
                        end else if (link_state == LK8) begin
                            diff8 = {1'b0, bank_acc[1], bank_acc[0]} - 9'd1;
                            {bank_acc[1], bank_acc[0]} <= diff8[7:0];
                            operation_carry <= ({1'b0, bank_acc[1], bank_acc[0]} < 9'd1);
                        end else begin
                            diff16 = {1'b0, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} - 17'd1;
                            {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= diff16[15:0];
                            operation_carry <= ({1'b0, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} < 17'd1);
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    AND: begin
                        if (flag_imm) begin
                            imm_pending   <= 1'b1;
                            imm_index     <= 3'd0;
                            imm_shift     <= 16'h0000;
                            imm_remaining <= (link_state == UL)  ? 3'd1 :
                                             (link_state == LK8) ? 3'd2 : 3'd4;
                            imm_opcode    <= AND;
                        end else begin
                            if (link_state == UL) begin
                                bank_acc[0] <= bank_acc[0] & bank_src[0][3:0];
                            end else if (link_state == LK8) begin
                                {bank_acc[1], bank_acc[0]} <= {bank_acc[1], bank_acc[0]} & bank_src[0][7:0];
                            end else begin
                                {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} & bank_src[0];
                            end
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    INV: begin
                        if (link_state == UL) begin
                            bank_acc[0] <= ~bank_acc[0];
                        end else if (link_state == LK8) begin
                            {bank_acc[1], bank_acc[0]} <= ~{bank_acc[1], bank_acc[0]};
                        end else begin
                            {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= ~{bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]};
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    OR: begin
                        if (flag_imm) begin
                            imm_pending   <= 1'b1;
                            imm_index     <= 3'd0;
                            imm_shift     <= 16'h0000;
                            imm_remaining <= (link_state == UL)  ? 3'd1 :
                                             (link_state == LK8) ? 3'd2 : 3'd4;
                            imm_opcode    <= OR;
                        end else begin
                            if (link_state == UL) begin
                                bank_acc[0] <= bank_acc[0] | bank_src[0][3:0];
                            end else if (link_state == LK8) begin
                                {bank_acc[1], bank_acc[0]} <= {bank_acc[1], bank_acc[0]} | bank_src[0][7:0];
                            end else begin
                                {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} | bank_src[0];
                            end
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    XOR: begin
                        if (flag_imm) begin
                            imm_pending   <= 1'b1;
                            imm_index     <= 3'd0;
                            imm_shift     <= 16'h0000;
                            imm_remaining <= (link_state == UL)  ? 3'd1 :
                                             (link_state == LK8) ? 3'd2 : 3'd4;
                            imm_opcode    <= XOR;
                        end else begin
                            if (link_state == UL) begin
                                bank_acc[0] <= bank_acc[0] ^ bank_src[0][3:0];
                            end else if (link_state == LK8) begin
                                {bank_acc[1], bank_acc[0]} <= {bank_acc[1], bank_acc[0]} ^ bank_src[0][7:0];
                            end else begin
                                {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} ^ bank_src[0];
                            end
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    SHL: begin
                        if (link_state == UL) begin
                            {operation_carry, bank_acc[0]} <= {bank_acc[0][3], bank_acc[0][2:0], 1'b0};
                        end else if (link_state == LK8) begin
                            {operation_carry, bank_acc[1], bank_acc[0]} <= {bank_acc[1], bank_acc[0], 1'b0};
                        end else begin
                            {operation_carry, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0], 1'b0};
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    SHR: begin
                        if (link_state == UL) begin
                            operation_carry <= bank_acc[0][0];
                            bank_acc[0] <= {1'b0, bank_acc[0][3:1]};
                        end else if (link_state == LK8) begin
                            operation_carry <= bank_acc[0][0];
                            {bank_acc[1], bank_acc[0]} <= {1'b0, bank_acc[1], bank_acc[0]} >> 1;
                        end else begin
                            operation_carry <= bank_acc[0][0];
                            {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} <= {1'b0, bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]} >> 1;
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    SA: begin
                        // Swap ACC (always 16b) <-> RA0
                        reg [15:0] acc_val;
                        acc_val       = {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]};
                        bank_acc[0]   <= bank_adr[0][3:0];
                        bank_acc[1]   <= bank_adr[0][7:4];
                        bank_acc[2]   <= bank_adr[0][11:8];
                        bank_acc[3]   <= bank_adr[0][15:12];
                        bank_adr[0]   <= acc_val;
                        pc            <= pc + 1'b1;
                        flag_xop      <= 1'b0;
                    end
                    RSS: begin
                        // Rotate RS stack (swap rs0<->rs1)
                        reg [15:0] tmp_rs;
                        tmp_rs      = bank_src[0];
                        bank_src[0] <= bank_src[1];
                        bank_src[1] <= tmp_rs;
                        pc          <= pc + 1'b1;
                        flag_xop    <= 1'b0;
                    end
                    RSA: begin
                        // Rotate RA stack (swap ra0<->ra1)
                        reg [15:0] tmp_ra;
                        tmp_ra      = bank_adr[0];
                        bank_adr[0] <= bank_adr[1];
                        bank_adr[1] <= tmp_ra;
                        pc          <= pc + 1'b1;
                        flag_xop    <= 1'b0;
                    end
                    RRS: begin
                        // Rotate/shift RS0 by width; LK16 acts as NOP
                        if (link_state == UL) begin
                            bank_src[0] <= {bank_src[0][3:0], bank_src[0][15:4]};
                        end else if (link_state == LK8) begin
                            bank_src[0] <= {bank_src[0][7:0], bank_src[0][15:8]};
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    RACC: begin
                        // Rotate ACC by width; LK16 acts as NOP
                        reg [15:0] acc_val;
                        acc_val = {bank_acc[3], bank_acc[2], bank_acc[1], bank_acc[0]};
                        if (link_state == UL) begin
                            acc_val = {acc_val[3:0], acc_val[15:4]};
                        end else if (link_state == LK8) begin
                            acc_val = {acc_val[7:0], acc_val[15:8]};
                        end
                        if (link_state != LK16) begin
                            bank_acc[0] <= acc_val[3:0];
                            bank_acc[1] <= acc_val[7:4];
                            bank_acc[2] <= acc_val[11:8];
                            bank_acc[3] <= acc_val[15:12];
                        end
                        pc       <= pc + 1'b1;
                        flag_xop <= 1'b0;
                    end
                    default: begin
                        pc       <= pc + 1'b1; // NOP or unimplemented
                        flag_xop <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
