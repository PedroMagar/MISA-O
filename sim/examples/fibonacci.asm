; MISA-O v0 — Fibonacci: compute fib(10) = 55
;
; Iterative algorithm in LK8 mode.
; Register layout at every loop entry:
;   ACC  = a  (previous fib, starts 0)
;   RS0  = b  (current fib, starts 1)
;
; Each iteration:  new_b = a+b,  new_a = b
;   ADD  →  ACC = a+b = new_b;  RS0 = b (unchanged)
;   SS   →  ACC = b  = new_a;   RS0 = new_b
;
; Loop terminates when b == 55 (fib(10)).
; Termination check (top-of-loop):
;   SS      move b into ACC
;   CMP #55  flags ← b-55
;   SS      restore ACC=a, RS0=b
;   BEQ     exit if b==55

.equ FIB_TARGET, 55     ; = fib(10)

.org 0x0000

FIB_MAIN:
    CFG #0x09           ; LK8, IMM=1

    ; Seed: ACC=0 (a), RS0=1 (b)
    LDi #0              ; ACC=0
    SS                  ; RS0=0, ACC=0  (both 0; just sets RS0)
    LDi #1              ; ACC=1
    SS                  ; RS0=1 (b=1), ACC=0 (a=0)

    CFG #0x01           ; LK8, IMM=0

CHECK_B:
    ; Check if b (in RS0) has reached FIB_TARGET
    SS                  ; ACC=b, RS0=a
    CFG #0x09           ; IMM=1
    CMP #FIB_TARGET     ; flags ← b - FIB_TARGET
    CFG #0x01           ; IMM=0
    SS                  ; ACC=a, RS0=b  (restore)
    BEQ FIB_DONE        ; exit when b == FIB_TARGET

    ; One Fibonacci step
    ADD                 ; ACC = a+b (new_b);  RS0=b (unchanged)
    SS                  ; ACC=b (new_a),       RS0=new_b
    BAL CHECK_B         ; unconditional loop back

FIB_DONE:
    ; RS0 = fib(10) = 55;  move to ACC for easy inspection
    SS                  ; ACC = 55

HALT:
    WFI                 ; ACC = 0x37 = 55
