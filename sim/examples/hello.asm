; MISA-O v0 — example: sum of 1..10
;
; Computes  sum = 1 + 2 + ... + 10 = 55 (0x37)
;
; Register plan (LK8 mode, IMM=0 except where noted):
;   ACC  — loop counter (1 → 11, exits when == 11)
;   RS0  — running sum  (0 → 55)
;
; Final result: RS0 = 55;  ACC = 11 after loop, then swapped so ACC = 55.

.org 0x0000

ENTRY:
    CFG #0x01           ; W=LK8, IMM=0

    ; Initialise sum=0 in RS0, counter=1 in ACC
    CFG #0x09           ; W=LK8, IMM=1 — need IMM for LDi
    LDi #0              ; ACC ← 0
    SS                  ; ACC ↔ RS0 : RS0=0 (sum), ACC=0
    LDi #1              ; ACC ← 1  (counter starts at 1)
    CFG #0x01           ; W=LK8, IMM=0  (disable IMM for loop body)

    ; Loop: ACC=counter, RS0=sum
SUM_LOOP:
    SS                  ; ACC ↔ RS0 → ACC=sum, RS0=counter
    ADD                 ; ACC = sum + counter  (RS0=counter, IMM=0)
    SS                  ; ACC ↔ RS0 → RS0=new_sum, ACC=counter
    INC                 ; counter++

    CFG #0x09           ; W=LK8, IMM=1 — for CMP immediate
    CMP #11             ; flags ← counter − 11  (does not write ACC)
    CFG #0x01           ; W=LK8, IMM=0
    BNE SUM_LOOP        ; loop while counter != 11

    ; Loop finished: RS0 = 55.  Move to ACC.
    SS                  ; ACC ← RS0 (= 55)

DONE:
    WFI                 ; halt — ACC = 0x37 = 55
