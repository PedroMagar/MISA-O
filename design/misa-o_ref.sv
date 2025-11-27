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
    localparam [4:0] CFG  = 5'b10001;

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
    reg flag_cen;
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

    wire [3:0] current_nibble = pc[0] ? mem_data_in[7:4] : mem_data_in[3:0];
    wire [4:0] instruction    = {flag_xop, current_nibble};
    wire [7:0] cfg_snapshot   = {1'b0, flag_bw, flag_brs, flag_ie, flag_cen, flag_sign, link_state};

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
        else     mem_addr <= pc[15:1];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc               <= 16'h0001;
            flag_xop         <= 1'b0;
            flag_bw          <= 1'b1; // imm8 by default
            flag_brs         <= 1'b0;
            flag_ie          <= 1'b0;
            flag_cen         <= 1'b1;
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
                    flag_bw     <= next_cfg[6];
                    flag_brs    <= next_cfg[5];
                    flag_ie     <= next_cfg[4];
                    flag_cen    <= next_cfg[3];
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
                    default: begin
                        pc       <= pc + 1'b1; // NOP or unimplemented
                        flag_xop <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
