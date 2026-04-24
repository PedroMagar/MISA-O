import re
import sys

TOKEN_TYPES = [
    ('KEYWORD', r'\b(int|while|if|else|void|return|struct|sizeof)\b'),
    ('IDENTIFIER', r'[a-zA-Z_]\w*'),
    ('NUMBER', r'\d+'),
    ('OPERATOR', r'==|!=|<=|>=|<|>|\+|-|\*|/|&'),
    ('ARROW', r'->'),
    ('DOT', r'\.'),
    ('ASSIGN', r'='),
    ('LBRACE', r'\{'),
    ('RBRACE', r'\}'),
    ('LPAREN', r'\('),
    ('RPAREN', r'\)'),
    ('LBRACKET', r'\['),
    ('RBRACKET', r'\]'),
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

# Types
class Type:
    def __init__(self, kind, base=None, size=2, fields=None):
        self.kind = kind
        self.base = base
        self.size = size
        self.fields = fields or {}
        self.name = None
    def __repr__(self):
        if self.kind == 'struct': return "struct {}".format(self.name)
        if self.kind == 'ptr': return "{}*".format(self.base)
        if self.kind == 'array': return "{}[{}]".format(self.base, self.size//self.base.size)
        return self.kind

# AST
class Program:
    def __init__(self, decls): self.decls = decls
class StructDef:
    def __init__(self, name, fields, size): self.name, self.fields, self.size = name, fields, size
class FunctionDef:
    def __init__(self, ret_type, name, args, body): self.ret_type, self.name, self.args, self.body = ret_type, name, args, body
class VarDecl:
    def __init__(self, var_type, name, init=None): self.var_type, self.name, self.init = var_type, name, init
class Block:
    def __init__(self, statements): self.statements = statements
class If:
    def __init__(self, cond, body): self.cond, self.body = cond, body
class While:
    def __init__(self, cond, body): self.cond, self.body = cond, body
class Return:
    def __init__(self, expr): self.expr = expr
class Assign:
    def __init__(self, target, expr): self.target, self.expr = target, expr
class BinOp:
    def __init__(self, left, op, right): self.left, self.op, self.right = left, op, right
class UnaryOp:
    def __init__(self, op, expr): self.op, self.expr = op, expr
class Number:
    def __init__(self, val): self.val = val
class Variable:
    def __init__(self, name): self.name = name
class FunctionCall:
    def __init__(self, name, args): self.name, self.args = name, args
class MemberAccess:
    def __init__(self, expr, member, is_arrow): self.expr, self.member, self.is_arrow = expr, member, is_arrow
class ArrayAccess:
    def __init__(self, expr, index): self.expr, self.index = expr, index
class SizeOf:
    def __init__(self, target_type): self.target_type = target_type

class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.pos = 0
        self.structs = {}

    def current(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def consume(self, expected_type, expected_value=None):
        tok = self.current()
        if not tok or tok.type != expected_type or (expected_value and tok.value != expected_value):
            exp = expected_value if expected_value else expected_type
            raise SyntaxError("Expected {}, got {}".format(exp, tok))
        self.pos += 1
        return tok
        
    def match(self, expected_type, expected_value=None):
        tok = self.current()
        if tok and tok.type == expected_type and (expected_value is None or tok.value == expected_value):
            self.pos += 1
            return True
        return False

    def parse_type(self):
        tok = self.current()
        if tok.type == 'KEYWORD' and tok.value in ('int', 'void'):
            self.consume('KEYWORD')
            t = Type(tok.value, size=(2 if tok.value == 'int' else 0))
        elif tok.type == 'KEYWORD' and tok.value == 'struct':
            self.consume('KEYWORD')
            name = self.consume('IDENTIFIER').value
            if name in self.structs:
                t = self.structs[name]
            else:
                t = Type('struct', size=0)
                t.name = name
        else:
            raise SyntaxError("Expected type, got {}".format(tok))
            
        while self.match('OPERATOR', '*'):
            t = Type('ptr', base=t, size=2)
            
        return t

    def parse(self):
        decls = []
        while self.current():
            tok = self.current()
            if tok.type == 'KEYWORD' and tok.value == 'struct':
                idx = self.pos + 2
                if idx < len(self.tokens) and self.tokens[idx].type == 'LBRACE':
                    decls.append(self.parse_struct_def())
                    continue
            decls.append(self.parse_function_or_global())
        return Program(decls)

    def parse_struct_def(self):
        self.consume('KEYWORD', 'struct')
        name = self.consume('IDENTIFIER').value
        self.consume('LBRACE')
        fields = {}
        offset = 0
        while not self.match('RBRACE'):
            ftype = self.parse_type()
            fname = self.consume('IDENTIFIER').value
            if self.match('LBRACKET'):
                size_tok = self.consume('NUMBER')
                self.consume('RBRACKET')
                arr_size = int(size_tok.value)
                ftype = Type('array', base=ftype, size=ftype.size * arr_size)
            self.consume('SEMICOLON')
            fields[fname] = (ftype, offset)
            offset += ftype.size
        self.consume('SEMICOLON')
        t = Type('struct', fields=fields, size=offset)
        t.name = name
        self.structs[name] = t
        return StructDef(name, fields, offset)

    def parse_function_or_global(self):
        t = self.parse_type()
        name = self.consume('IDENTIFIER').value
        self.consume('LPAREN')
        args = []
        while self.current() and self.current().type != 'RPAREN':
            arg_type = self.parse_type()
            arg_name = self.consume('IDENTIFIER').value
            args.append((arg_type, arg_name))
            if self.match('COMMA'): pass
        self.consume('RPAREN')
        body = self.parse_block()
        return FunctionDef(t, name, args, body)

    def parse_block(self):
        self.consume('LBRACE')
        stmts = []
        while self.current() and self.current().type != 'RBRACE':
            stmts.append(self.parse_statement())
        self.consume('RBRACE')
        return Block(stmts)

    def parse_statement(self):
        tok = self.current()
        if tok.type == 'KEYWORD' and tok.value in ('int', 'struct'):
            vtype = self.parse_type()
            name = self.consume('IDENTIFIER').value
            if self.match('LBRACKET'):
                sz = int(self.consume('NUMBER').value)
                self.consume('RBRACKET')
                vtype = Type('array', base=vtype, size=vtype.size * sz)
            init = None
            if self.match('ASSIGN'):
                init = self.parse_expression()
            self.consume('SEMICOLON')
            return VarDecl(vtype, name, init)
        elif tok.type == 'KEYWORD' and tok.value == 'return':
            self.consume('KEYWORD')
            expr = self.parse_expression() if not self.match('SEMICOLON') else None
            if expr: self.consume('SEMICOLON')
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
        else:
            expr = self.parse_expression()
            if self.match('ASSIGN'):
                rhs = self.parse_expression()
                self.consume('SEMICOLON')
                return Assign(expr, rhs)
            self.consume('SEMICOLON')
            return expr

    def parse_expression(self):
        left = self.parse_term()
        tok = self.current()
        if tok and tok.type == 'OPERATOR' and tok.value not in ('*', '&'):
            op = self.consume('OPERATOR').value
            right = self.parse_term()
            return BinOp(left, op, right)
        return left

    def parse_term(self):
        tok = self.current()
        if tok.type == 'OPERATOR' and tok.value == '&':
            self.consume('OPERATOR')
            return UnaryOp('&', self.parse_term())
        elif tok.type == 'OPERATOR' and tok.value == '*':
            self.consume('OPERATOR')
            return UnaryOp('*', self.parse_term())
        elif tok.type == 'KEYWORD' and tok.value == 'sizeof':
            self.consume('KEYWORD')
            self.consume('LPAREN')
            t = self.parse_type()
            self.consume('RPAREN')
            return SizeOf(t)
        
        if tok.type == 'NUMBER':
            self.consume('NUMBER')
            node = Number(int(tok.value))
        elif tok.type == 'IDENTIFIER':
            name = self.consume('IDENTIFIER').value
            if self.match('LPAREN'):
                args = []
                while self.current() and self.current().type != 'RPAREN':
                    args.append(self.parse_expression())
                    if self.match('COMMA'): pass
                self.consume('RPAREN')
                node = FunctionCall(name, args)
            else:
                node = Variable(name)
        else:
            raise SyntaxError("Unexpected term: {}".format(tok))
            
        while self.current() and self.current().type in ('LBRACKET', 'DOT', 'ARROW'):
            if self.match('LBRACKET'):
                idx = self.parse_expression()
                self.consume('RBRACKET')
                node = ArrayAccess(node, idx)
            elif self.match('DOT'):
                field = self.consume('IDENTIFIER').value
                node = MemberAccess(node, field, False)
            elif self.match('ARROW'):
                field = self.consume('IDENTIFIER').value
                node = MemberAccess(node, field, True)
                
        return node

class Environment:
    def __init__(self, parent=None):
        self.vars = {}
        self.parent = parent
        self.local_size = 0

    def get(self, name):
        if name in self.vars: return self.vars[name]
        if self.parent: return self.parent.get(name)
        raise Exception("Undefined variable {}".format(name))
        
    def add(self, name, vtype, offset):
        self.vars[name] = (vtype, offset)

class CodeGeneratorRA1:
    def __init__(self):
        self.asm = []
        self.label_count = 0
        self.structs = {}
        self.env = None
        self.current_func = None

    def get_label(self, prefix="L"):
        self.label_count += 1
        return "{}{}".format(prefix, self.label_count)

    def emit(self, inst):
        self.asm.append(inst)

    def generate(self, program):
        self.emit(".org 0x0000")
        self.emit("ENTRY:")
        self.emit("    CFG #0x02\t; LK16")
        self.emit("    CFG #0x0A\t; IMM=1")
        self.emit("    LDi #0xFFFE")
        self.emit("    CFG #0x02\t; IMM=0")
        self.emit("    SA1\t\t; RA1 = SP = 0xFFFE")
        self.emit("    CFG #0x0A\t; IMM=1")
        self.emit("    LDi #main")
        self.emit("    CFG #0x02\t; IMM=0")
        self.emit("    SA1\t\t; RA1 = func, ACC = SP")
        self.emit("    SA0\t\t; RA0 = SP")
        self.emit("    JAL\t\t; CALL main")
        self.emit("DONE:")
        self.emit("    WFI")
        self.emit("")
        
        for decl in program.decls:
            if isinstance(decl, StructDef):
                self.structs[decl.name] = Type('struct', fields=decl.fields, size=decl.size)
            elif isinstance(decl, FunctionDef):
                self.gen_func(decl)
                
        return "\n".join(self.asm)

    def scan_locals(self, block, offset):
        for stmt in block.statements:
            if isinstance(stmt, VarDecl):
                self.env.add(stmt.name, stmt.var_type, offset)
                offset += stmt.var_type.size
            elif isinstance(stmt, If):
                offset = self.scan_locals(stmt.body, offset)
            elif isinstance(stmt, While):
                offset = self.scan_locals(stmt.body, offset)
        return offset

    def gen_func(self, func):
        self.current_func = func.name
        self.env = Environment()
        self.env.local_size = self.scan_locals(func.body, 0)
        
        arg_offset = self.env.local_size + 2
        for arg_type, arg_name in func.args:
            self.env.add(arg_name, arg_type, arg_offset)
            arg_offset += arg_type.size
            
        self.emit("{}:".format(func.name))
        self.emit("    ; Prologue: RA1=ret_addr, RA0=SP")
        self.emit("    SA0\t\t; ACC = SP")
        self.emit("    SA1\t\t; RA1 = SP, ACC = ret_addr")
        self.emit("    XMEM #0b1110\t; Push ret_addr to [RA1] (pre-dec)")
        
        if self.env.local_size > 0:
            self.emit("    ; Allocate locals")
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #{}\t; size".format(self.env.local_size))
            self.emit("    CFG #0x02\t; IMM=0")
            self.emit("    SA0\t\t; RA0 = size")
            self.emit("    SA1\t\t; RA1 <-> ACC")
            self.emit("    SUB\t\t; ACC(SP) - RA0(size)")
            self.emit("    SA1\t\t; RA1 = ACC(new SP)")

        self.gen_stmt(func.body)
        
        self.emit("{}_end:".format(self.current_func))
        self.emit("    ; Epilogue")
        if self.env.local_size > 0:
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #{}\t; size".format(self.env.local_size))
            self.emit("    CFG #0x02\t; IMM=0")
            self.emit("    SA0\t\t; RA0 = size")
            self.emit("    SA1\t\t; RA1 <-> ACC")
            self.emit("    ADD\t\t; ACC(SP) + RA0(size)")
            self.emit("    SA1\t\t; RA1 = ACC(SP)")
            
        self.emit("    XMEM #0b0010\t; Pop ret_addr to ACC")
        self.emit("    SA0\t\t; RA0=ret_addr, ACC=old RA0")
        self.emit("    SA1\t\t; RA1=old RA0, ACC=SP")
        self.emit("    SA0\t\t; RA0=SP, ACC=ret_addr")
        self.emit("    SA1\t\t; RA1=ret_addr, ACC=old RA0")
        self.emit("    JMP")
        self.emit("")

    def evaluate_lvalue(self, node):
        if isinstance(node, Variable):
            vtype, offset = self.env.get(node.name)
            self.emit("    ; lvalue var {}".format(node.name))
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #{}\t; offset".format(offset))
            self.emit("    CFG #0x02\t; IMM=0")
            self.emit("    SS0\t\t; RS0 = offset")
            self.emit("    SA1\t\t; ACC = SP, RA1 = old")
            self.emit("    ADD\t\t; ACC = SP + offset")
            self.emit("    SS1\t\t; RS1 = Result")
            self.emit("    SS1\t\t; ACC = Result")
            self.emit("    SUB\t\t; ACC = SP")
            self.emit("    SA1\t\t; RA1 = SP")
            self.emit("    SS1\t\t; ACC = Result")
            return vtype
        elif isinstance(node, UnaryOp) and node.op == '*':
            vtype = self.gen_expr(node.expr)
            return vtype.base
        elif isinstance(node, ArrayAccess):
            vtype = self.evaluate_lvalue(node.expr)
            self.emit("    XMEM #0b1110\t; Push base addr")
            self.gen_expr(node.index)
            if vtype.base.size == 2:
                self.emit("    SHL\t\t; index * 2")
            elif vtype.base.size > 1:
                # Unsupported sizes for now without MUL, but safely handled.
                pass
            self.emit("    SS0\t\t; RS0 = index_offset")
            self.emit("    XMEM #0b0010\t; pop base_addr to ACC")
            self.emit("    ADD\t\t; ACC = base_addr + index_offset")
            return vtype.base
        elif isinstance(node, MemberAccess):
            vtype = self.evaluate_lvalue(node.expr)
            if node.is_arrow:
                self.emit("    SA0\t\t; RA0 = lval addr")
                self.emit("    XMEM #0b0001\t; ACC = [RA1+RA0]")
                vtype = vtype.base
            field_type, field_offset = vtype.fields[node.member]
            self.emit("    SS0\t\t; RS0 = ACC (base addr)")
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #{}\t; field offset".format(field_offset))
            self.emit("    CFG #0x02\t; IMM=0")
            self.emit("    ADD\t\t; ACC = base addr + offset")
            return field_type
        else:
            raise Exception("Invalid lvalue")

    def gen_cond(self, node, target_lbl, invert=False):
        if not isinstance(node, BinOp):
            raise Exception("Condition must be a binary operation")
        self.gen_expr(node.left)
        self.emit("    XMEM #0b1110\t; Push left")
        self.gen_expr(node.right)
        self.emit("    SS0\t\t; RS0 <- right")
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

    def gen_stmt(self, node):
        if isinstance(node, Block):
            for stmt in node.statements:
                self.gen_stmt(stmt)
        elif isinstance(node, VarDecl):
            if node.init:
                rhs_type = self.gen_expr(node.init)
                self.emit("    XMEM #0b1110\t; push rhs")
                self.evaluate_lvalue(Variable(node.name))
                self.emit("    SA0\t\t; RA0 = lval")
                self.emit("    XMEM #0b0010\t; pop rhs")
                self.emit("    XMEM #0b1001\t; [RA1+RA0] = ACC")
        elif isinstance(node, Assign):
            rhs_type = self.gen_expr(node.expr)
            self.emit("    XMEM #0b1110\t; push rhs")
            lhs_type = self.evaluate_lvalue(node.target)
            
            if lhs_type.kind in ('struct', 'array'):
                self.emit("    ; Struct/Array Copy")
                self.emit("    SA0\t\t; RA0 = dst addr (from ACC)")
                self.emit("    XMEM #0b0010\t; ACC = src addr (from stack)")
                
                self.emit("    SA1\t\t; RA1 <-> ACC. ACC = SP, RA1 = src addr")
                self.emit("    SS0\t\t; RS0 = SP")
                
                self.emit("    CFG #0x0A\t; IMM=1")
                self.emit("    LDi #{}\t; size".format(lhs_type.size))
                self.emit("    CFG #0x02\t; IMM=0")
                self.emit("    SS1\t\t; RS1 = size")
                
                self.emit("    XOP")
                self.emit("    MCPY\t\t; [RA0] <- [RA1], size RS1")
                
                self.emit("    SS0\t\t; ACC = SP")
                self.emit("    SA1\t\t; RA1 = SP")
            else:
                self.emit("    SA0\t\t; RA0 = target addr (LHS)")
                self.emit("    XMEM #0b0010\t; ACC = RHS")
                self.emit("    XMEM #0b1001\t; [RA1+RA0] = ACC")
        elif isinstance(node, Return):
            if node.expr:
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
        else:
            self.gen_expr(node)

    def gen_expr(self, node):
        if isinstance(node, Number):
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #{}\t; Number".format(node.val))
            self.emit("    CFG #0x02\t; IMM=0")
            return Type('int')
        elif isinstance(node, Variable):
            vtype = self.evaluate_lvalue(node)
            if vtype.kind in ('array', 'struct'): return vtype
            self.emit("    SA0\t\t; RA0 = addr")
            self.emit("    XMEM #0b0001\t; ACC = [RA1+RA0]")
            return vtype
        elif isinstance(node, ArrayAccess) or isinstance(node, MemberAccess):
            vtype = self.evaluate_lvalue(node)
            if vtype.kind in ('array', 'struct'): return vtype
            self.emit("    SA0\t\t; RA0 = addr")
            self.emit("    XMEM #0b0001\t; ACC = [RA1+RA0]")
            return vtype
        elif isinstance(node, UnaryOp) and node.op == '&':
            vtype = self.evaluate_lvalue(node.expr)
            return Type('ptr', base=vtype, size=2)
        elif isinstance(node, UnaryOp) and node.op == '*':
            vtype = self.evaluate_lvalue(node.expr)
            if vtype.kind in ('array', 'struct'): return vtype
            self.emit("    SA0\t\t; RA0 = addr")
            self.emit("    XMEM #0b0001\t; ACC = [RA1+RA0]")
            return vtype
        elif isinstance(node, SizeOf):
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #{}\t; sizeof".format(node.target_type.size))
            self.emit("    CFG #0x02\t; IMM=0")
            return Type('int')
        elif isinstance(node, FunctionCall):
            for arg in reversed(node.args):
                self.gen_expr(arg)
                self.emit("    XMEM #0b1110\t; Push arg")
            self.emit("    CFG #0x0A\t; IMM=1")
            self.emit("    LDi #{}\t; func addr".format(node.name))
            self.emit("    CFG #0x02\t; IMM=0")
            self.emit("    SA1\t\t; RA1 = func, ACC = SP")
            self.emit("    SA0\t\t; RA0 = SP")
            self.emit("    JAL\t\t; Call")
            self.emit("    SA0\t\t; ACC = SP (from RA0)")
            self.emit("    SA1\t\t; RA1 = SP")
            for arg in node.args:
                self.emit("    XMEM #0b0010\t; pop arg")
            return Type('int')
        elif isinstance(node, BinOp):
            self.gen_expr(node.left)
            self.emit("    XMEM #0b1110\t; push left")
            self.gen_expr(node.right)
            self.emit("    SS0\t\t; RS0 = right")
            self.emit("    XMEM #0b0010\t; ACC = left")
            if node.op == '+': self.emit("    ADD")
            elif node.op == '-': self.emit("    SUB")
            return Type('int')

def compile_c(code):
    tokens = tokenize(code)
    parser = Parser(tokens)
    ast = parser.parse()
    codegen = CodeGeneratorRA1()
    return codegen.generate(ast)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python micro_c_compiler.py <file.c>")
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
