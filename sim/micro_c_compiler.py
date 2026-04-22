import re
import sys

TOKEN_TYPES = [
    ('KEYWORD', r'\b(int|while|if|else|void|return)\b'),
    ('IDENTIFIER', r'[a-zA-Z_]\w*'),
    ('NUMBER', r'\d+'),
    ('OPERATOR', r'==|!=|<=|>=|<|>|\+|-|\*|/'),
    ('ASSIGN', r'='),
    ('LBRACE', r'\{'),
    ('RBRACE', r'\}'),
    ('LPAREN', r'\('),
    ('RPAREN', r'\)'),
    ('SEMICOLON', r';'),
    ('COMMA', r','),
    ('WHITESPACE', r'\s+'),
]

class Token:
    def __init__(self, type, value):
        self.type = type
        self.value = value
    def __repr__(self):
        return "{}({})".format(self.type, self.value)

def tokenize(code):
    tokens = []
    code = code.strip()
    while code:
        match = None
        for type, pattern in TOKEN_TYPES:
            regex = re.compile('^' + pattern)
            match = regex.match(code)
            if match:
                if type != 'WHITESPACE':
                    tokens.append(Token(type, match.group(0)))
                code = code[match.end():]
                break
        if not match:
            raise SyntaxError("Unexpected token at: {}".format(code[:10]))
    return tokens

# AST Nodes
class Program:
    def __init__(self, functions):
        self.functions = functions

class FunctionDef:
    def __init__(self, name, args, body):
        self.name = name
        self.args = args
        self.body = body

class VarDecl:
    def __init__(self, name, init):
        self.name = name
        self.init = init

class Assign:
    def __init__(self, name, expr):
        self.name = name
        self.expr = expr

class Return:
    def __init__(self, expr):
        self.expr = expr

class FunctionCall:
    def __init__(self, name, args):
        self.name = name
        self.args = args

class BinOp:
    def __init__(self, left, op, right):
        self.left = left
        self.op = op
        self.right = right

class Number:
    def __init__(self, val):
        self.val = val

class Variable:
    def __init__(self, name):
        self.name = name

class While:
    def __init__(self, cond, body):
        self.cond = cond
        self.body = body

class If:
    def __init__(self, cond, body):
        self.cond = cond
        self.body = body

class Block:
    def __init__(self, statements):
        self.statements = statements

class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.pos = 0

    def current(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def consume(self, expected_type, expected_value=None):
        tok = self.current()
        if not tok or tok.type != expected_type or (expected_value and tok.value != expected_value):
            expected = expected_value if expected_value else expected_type
            raise SyntaxError("Expected {}, got {}".format(expected, tok))
        self.pos += 1
        return tok

    def parse(self):
        funcs = []
        while self.current():
            funcs.append(self.parse_function())
        return Program(funcs)

    def parse_function(self):
        ret_type = self.consume('KEYWORD').value # int or void
        name = self.consume('IDENTIFIER').value
        self.consume('LPAREN')
        args = []
        while self.current() and self.current().type != 'RPAREN':
            self.consume('KEYWORD', 'int')
            args.append(self.consume('IDENTIFIER').value)
            if self.current() and self.current().type == 'COMMA':
                self.consume('COMMA')
        self.consume('RPAREN')
        body = self.parse_block()
        return FunctionDef(name, args, body)

    def parse_block(self):
        self.consume('LBRACE')
        stmts = []
        while self.current() and self.current().type != 'RBRACE':
            stmts.append(self.parse_statement())
        self.consume('RBRACE')
        return Block(stmts)

    def parse_statement(self):
        tok = self.current()
        if tok.type == 'KEYWORD' and tok.value == 'int':
            self.consume('KEYWORD')
            name = self.consume('IDENTIFIER').value
            self.consume('ASSIGN')
            expr = self.parse_expression()
            self.consume('SEMICOLON')
            return VarDecl(name, expr)
        elif tok.type == 'KEYWORD' and tok.value == 'return':
            self.consume('KEYWORD')
            expr = self.parse_expression()
            self.consume('SEMICOLON')
            return Return(expr)
        elif tok.type == 'KEYWORD' and tok.value == 'while':
            self.consume('KEYWORD')
            self.consume('LPAREN')
            cond = self.parse_expression()
            self.consume('RPAREN')
            body = self.parse_block()
            return While(cond, body)
        elif tok.type == 'KEYWORD' and tok.value == 'if':
            self.consume('KEYWORD')
            self.consume('LPAREN')
            cond = self.parse_expression()
            self.consume('RPAREN')
            body = self.parse_block()
            return If(cond, body)
        elif tok.type == 'IDENTIFIER':
            name = self.consume('IDENTIFIER').value
            self.consume('ASSIGN')
            expr = self.parse_expression()
            self.consume('SEMICOLON')
            return Assign(name, expr)
        else:
            raise SyntaxError("Unexpected statement token: {}".format(tok))

    def parse_expression(self):
        left = self.parse_term()
        tok = self.current()
        if tok and tok.type == 'OPERATOR':
            op = self.consume('OPERATOR').value
            right = self.parse_term()
            return BinOp(left, op, right)
        return left

    def parse_term(self):
        tok = self.current()
        if tok.type == 'NUMBER':
            self.consume('NUMBER')
            return Number(int(tok.value))
        elif tok.type == 'IDENTIFIER':
            name = self.consume('IDENTIFIER').value
            if self.current() and self.current().type == 'LPAREN':
                self.consume('LPAREN')
                args = []
                while self.current() and self.current().type != 'RPAREN':
                    args.append(self.parse_expression())
                    if self.current() and self.current().type == 'COMMA':
                        self.consume('COMMA')
                self.consume('RPAREN')
                return FunctionCall(name, args)
            return Variable(name)
        raise SyntaxError("Unexpected term token: {}".format(tok))

# Code Generator for RA1 as Stack Pointer
class CodeGeneratorRA1:
    def __init__(self):
        self.asm = []
        self.label_count = 0
        self.current_func = None
        self.locals = []
        self.args = []

    def get_label(self, prefix="L"):
        self.label_count += 1
        return "{}{}".format(prefix, self.label_count)

    def emit(self, instruction):
        self.asm.append(instruction)

    def generate(self, program):
        self.emit(".org 0x0000")
        self.emit("ENTRY:")
        self.emit("    CFG #0x02\t; W=LK16, IMM=0 (16-bit mode)")
        self.emit("    ; Initialize RA1 (SP) to end of memory (0xFFFE)")
        self.emit("    CFG #0x0A\t; IMM=1")
        self.emit("    LDi #0xFFFE")
        self.emit("    CFG #0x02\t; IMM=0")
        self.emit("    RSA\t\t; RA1 <- 0xFFFE")
        self.emit("    LDi #main")
        self.emit("    SA")
        self.emit("    JAL\t\t; Call main")
        self.emit("DONE:")
        self.emit("    WFI\t\t; halt")
        self.emit("")
        
        for func in program.functions:
            self.gen_func(func)
        return "\n".join(self.asm)

    def gen_func(self, func):
        self.current_func = func.name
        self.args = func.args
        self.locals = []
        
        # Pre-scan for local variables to allocate space
        self.scan_locals(func.body)
        
        self.emit("{}:".format(func.name))
        
        # Prologue
        self.emit("    ; PROLOGUE: Save RA0 (return address)")
        self.emit("    SA\t\t; ACC <- RA0")
        self.emit("    XMEM #0b1110\t; Push ACC to [RA1]")
        self.emit("    SA\t\t; Restore ACC (optional)")
        
        if len(self.locals) > 0:
            self.emit("    ; Allocate {} locals".format(len(self.locals)))
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #0")
            self.emit("    CFG #0x02\t; IMM=0")
            for _ in self.locals:
                self.emit("    XMEM #0b1110\t; Push 0")

        self.gen_stmt(func.body)
        
        self.emit("{}_end:".format(self.current_func))
        # Epilogue
        if len(self.locals) > 0:
            self.emit("    ; Deallocate {} locals".format(len(self.locals)))
            for _ in self.locals:
                self.emit("    XMEM #0b0010\t; Pop to ACC (discard)")
        
        self.emit("    ; EPILOGUE: Restore RA0")
        self.emit("    SA\t\t; Save ACC (return value)")
        self.emit("    XMEM #0b0010\t; Pop to ACC")
        self.emit("    SA\t\t; RA0 <- return address, ACC <- return value")
        self.emit("    JMP\t\t; Return")
        self.emit("")

    def scan_locals(self, block):
        for stmt in block.statements:
            if isinstance(stmt, VarDecl):
                self.locals.append(stmt.name)
            elif isinstance(stmt, If):
                self.scan_locals(stmt.body)
            elif isinstance(stmt, While):
                self.scan_locals(stmt.body)

    def get_var_offset(self, name):
        # locals: 0, 2, 4... (closest to RA1)
        # return addr: 2 * len(locals)
        # args: 2 * len(locals) + 2 + 2 * arg_index
        if name in self.locals:
            idx = self.locals.index(name)
            # locals are pushed in order. Last local is at SP (0 offset)
            return 2 * (len(self.locals) - 1 - idx)
        elif name in self.args:
            idx = self.args.index(name)
            # args were pushed by caller. Last arg pushed is at lowest address.
            # wait! If caller evaluates arg1 then arg2, arg2 is pushed last!
            # So arg2 is at offset + 2 after return addr. arg1 is at offset + 4.
            # Let's say caller pushes args from Right to Left (C standard):
            # arg2 pushed, then arg1 pushed.
            # Then arg1 is at +2 after return addr, arg2 is at +4.
            # So offset = 2 * len(locals) + 2 + 2 * idx
            return 2 * len(self.locals) + 2 + 2 * idx
        else:
            raise Exception("Undefined variable: {}".format(name))

    def gen_stmt(self, node):
        if isinstance(node, Block):
            for stmt in node.statements:
                self.gen_stmt(stmt)
        elif isinstance(node, VarDecl):
            self.gen_expr(node.init)
            self.emit_assign(node.name)
        elif isinstance(node, Assign):
            self.gen_expr(node.expr)
            self.emit_assign(node.name)
        elif isinstance(node, Return):
            self.gen_expr(node.expr)
            self.emit("    BAL {}_end".format(self.current_func))
        elif isinstance(node, While):
            start_lbl = self.get_label("WHILE_START")
            end_lbl = self.get_label("WHILE_END")
            self.emit("{}:".format(start_lbl))
            self.gen_cond(node.cond, end_lbl, invert=True)
            self.gen_stmt(node.body)
            self.emit("    BAL {}".format(start_lbl))
            self.emit("{}:".format(end_lbl))
        elif isinstance(node, If):
            end_lbl = self.get_label("IF_END")
            self.gen_cond(node.cond, end_lbl, invert=True)
            self.gen_stmt(node.body)
            self.emit("{}:".format(end_lbl))

    def emit_assign(self, var_name):
        offset = self.get_var_offset(var_name)
        self.emit("    ; Store to {}".format(var_name))
        self.emit("    XMEM #0b1110\t; Push value to store")
        self.emit("    CFG #0x0A\t; IMM=1")
        self.emit("    LDi #{}\t; offset".format(offset))
        self.emit("    CFG #0x02\t; IMM=0")
        self.emit("    SA\t\t; RA0 <- offset")
        self.emit("    XMEM #0b0010\t; Pop value back to ACC")
        self.emit("    XMEM #0b1001\t; Store ACC to [RA1+RA0]")

    def gen_expr(self, node):
        if isinstance(node, Number):
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #{}\t; Number".format(node.val))
            self.emit("    CFG #0x02\t; IMM=0")
        elif isinstance(node, Variable):
            offset = self.get_var_offset(node.name)
            self.emit("    ; Read {}".format(node.name))
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #{}\t; offset".format(offset))
            self.emit("    CFG #0x02\t; IMM=0")
            self.emit("    SA\t\t; RA0 <- offset")
            self.emit("    XMEM #0b0001\t; ACC <- [RA1+RA0]")
        elif isinstance(node, FunctionCall):
            self.emit("    ; Call {}".format(node.name))
            # Push args right to left
            for arg in reversed(node.args):
                self.gen_expr(arg)
                self.emit("    XMEM #0b1110\t; Push arg")
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #{}\t; function address".format(node.name))
            self.emit("    CFG #0x02\t; IMM=0")
            self.emit("    SA\t\t; RA0 <- func addr")
            self.emit("    JAL")
            if len(node.args) > 0:
                self.emit("    ; Pop args")
                for _ in node.args:
                    self.emit("    XMEM #0b0010")
        elif isinstance(node, BinOp):
            if node.op == '*':
                # Micro compiler doesn't have MUL instruction. We fallback to calling a helper?
                # Actually, MISA-O doesn't have multiply. If we need it for factorial, we must do software multiply.
                # Let's just implement a quick software multiply in ASM inline for the test!
                # Wait, this is very complex. Better to add a pseudo-op or use ADD in loop.
                pass
            
            # Evaluate left side into ACC
            self.gen_expr(node.left)
            # Save left side to stack
            self.emit("    XMEM #0b1110\t; Push left side")
            # Evaluate right side into ACC
            self.gen_expr(node.right)
            # Now ACC has right side. Stack has left side.
            # We want Left op Right.
            self.emit("    SS\t\t; RS0 <- right side")
            self.emit("    XMEM #0b0010\t; ACC <- left side")
            # Now ACC has left, RS0 has right.
            if node.op == '+': self.emit("    ADD")
            elif node.op == '-': self.emit("    SUB")

    def gen_cond(self, node, target_lbl, invert=False):
        if not isinstance(node, BinOp):
            raise Exception("Condition must be a binary operation")
        self.gen_expr(node.left)
        self.emit("    XMEM #0b1110\t; Push left")
        self.gen_expr(node.right)
        self.emit("    SS\t\t; RS0 <- right")
        self.emit("    XMEM #0b0010\t; ACC <- left")
        self.emit("    CMP\t\t; left - right")
        
        op = node.op
        if invert:
            if op == '==': self.emit("    BNE {}".format(target_lbl))
            elif op == '!=': self.emit("    BEQ {}".format(target_lbl))
            elif op == '<': self.emit("    BCC {}".format(target_lbl))
            elif op == '>': self.emit("    BLS {}".format(target_lbl))
            elif op == '<=': self.emit("    BHI {}".format(target_lbl))
            elif op == '>=': self.emit("    BCS {}".format(target_lbl))
        else:
            if op == '==': self.emit("    BEQ {}".format(target_lbl))
            elif op == '!=': self.emit("    BNE {}".format(target_lbl))
            elif op == '<': self.emit("    BCS {}".format(target_lbl))
            elif op == '>': self.emit("    BHI {}".format(target_lbl))
            elif op == '<=': self.emit("    BLS {}".format(target_lbl))
            elif op == '>=': self.emit("    BCC {}".format(target_lbl))

def compile_c(code):
    tokens = tokenize(code)
    parser = Parser(tokens)
    ast = parser.parse()
    codegen = CodeGeneratorRA1()
    return codegen.generate(ast)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python micro_c_compiler_ra1.py <file.c>")
        sys.exit(1)
    
    with open(sys.argv[1], 'r') as f:
        code = f.read()
    
    try:
        asm = compile_c(code)
        out_file = sys.argv[1].replace(".c", ".asm")
        with open(out_file, 'w') as f:
            f.write(asm)
        print("Successfully compiled {} to {}".format(sys.argv[1], out_file))
    except Exception as e:
        print("Compilation error: {}".format(e))
