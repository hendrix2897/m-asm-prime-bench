// prime_bench.s — Apple Silicon (AArch64/macOS) prime benchmark
// Computes all primes up to N using trial division
// Prints elapsed wall-clock time on completion.
//
// Registers used (callee-saved, preserved across syscalls):
//   X19 = current candidate number being tested
//   X20 = outer loop limit
//   X21 = prime count
//   X22 = divisor used in inner trial-division loop
//   X23 = start tv_sec
//   X24 = start tv_nsec
//   X25 = total elapsed nanoseconds
//   X26 = elapsed whole seconds    (X25 / 1,000,000,000)
//   X27 = elapsed nanoseconds remainder (X25 % 1,000,000,000)
//   X28 = constant 1,000,000,000

.global _start
.align 2

// ─── Timeval buffer layout ────────────────────────────────────────────────
// gettimeofday writes a struct timeval (16 bytes total due to padding):
//   [+0]  8 bytes  tv_sec
//   [+8]  4 bytes  tv_usec (microseconds)
//   [+12] 4 bytes  padding

// ─── Syscall numbers (macOS/Darwin AArch64) ───────────────────────────────
.equ SYS_EXIT,            1
.equ SYS_WRITE,           4
.equ SYS_GETTIMEOFDAY,    116

_start:
    // ── Allocate stack space ──────────────────────────────────────────────
    //    [SP+0  .. SP+15]  tv_start (16 bytes)
    //    [SP+16 .. SP+31]  tv_end   (16 bytes)
    //    [SP+32 .. SP+47]  LR save slot
    sub SP, SP, #48

    // ── Print opening message ─────────────────────────────────────────────
    mov  X0, #1
    adrp X1, msg_start@PAGE
    add  X1, X1, msg_start@PAGEOFF
    mov  X2, #29                // <--- UPDATED: 28 bytes for the 100M string
    mov  X16, #SYS_WRITE
    svc  #0x80

    // ── Record start time (gettimeofday) ──────────────────────────────────
    mov  X0, SP                 // X0 = pointer to struct timeval
    mov  X1, #0                 // X1 = pointer to timezone (NULL)
    mov  X16, #SYS_GETTIMEOFDAY
    svc  #0x80

    ldr  X23, [SP, #0]          // X23 = start tv_sec (8 bytes)
    ldr  W24, [SP, #8]          // X24 = start tv_usec (4 bytes, zero-extended)
    
    // Convert microseconds to nanoseconds so the rest of the math works
    mov  X9, #1000
    mul  X24, X24, X9           // X24 = start time in nanoseconds

    // ── Initialise loop state ─────────────────────────────────────────────
    mov  X21, #1                // prime count = 1 (2 counted manually)
    mov  X19, #3                // first candidate: 3

    // limit: 100,000,000 = 100 × 1,000,000
    movz X20, #0x4240
    movk X20, #0x000F, lsl #16  // X20 = 1,000,000
    mov  X9,  #100              // <--- UPDATED: Changed from 50 to 100
    mul  X20, X20, X9           // X20 = 100,000,000

outer_loop:
    cmp  X19, X20
    bgt  done

    // ── Trial division: test odd divisors 3..√candidate ──────────────────
    mov  X22, #3

trial_loop:
    mul  X9,  X22, X22          // X9 = divisor²
    cmp  X9,  X19
    bgt  is_prime               // divisor² > candidate → prime

    udiv X10, X19, X22
    mul  X11, X10, X22
    sub  X11, X19, X11          // X11 = candidate mod divisor
    cbz  X11, not_prime

    add  X22, X22, #2
    b    trial_loop

is_prime:
    add  X21, X21, #1

not_prime:
    add  X19, X19, #2
    b    outer_loop

done:
    // ── Record end time (gettimeofday) ────────────────────────────────────
    add  X0, SP, #16            // X0 = pointer to struct timeval
    mov  X1, #0                 // X1 = pointer to timezone (NULL)
    mov  X16, #SYS_GETTIMEOFDAY
    svc  #0x80

    ldr  X9,  [SP, #16]         // end tv_sec (8 bytes)
    ldr  W10, [SP, #24]         // end tv_usec (4 bytes, zero-extended)

    // Convert microseconds to nanoseconds
    mov  X11, #1000
    mul  X10, X10, X11          // end time in nanoseconds

    // ── Compute elapsed nanoseconds ───────────────────────────────────────
    // Build 1,000,000,000 into X28
    movz X28, #0xCA00
    movk X28, #0x3B9A, lsl #16  // X28 = 1,000,000,000

    // elapsed = (end_sec - start_sec) * 1e9 + (end_nsec - start_nsec)
    sub  X9,  X9,  X23          // sec diff
    mul  X9,  X9,  X28          // sec diff in nanoseconds
    sub  X10, X10, X24          // nsec diff (may be negative)
    add  X25, X9,  X10          // total elapsed nanoseconds

    // ── Split into seconds + nanosecond remainder ─────────────────────────
    udiv X26, X25, X28          // X26 = whole seconds
    msub X27, X26, X28, X25     // X27 = remainder nanoseconds

    // ── Print "Primes found: XXXXXXXXXX\n" ────────────────────────────────
    adrp X0, num_buf@PAGE
    add  X0, X0, num_buf@PAGEOFF
    mov  X1, X21
    str  X30, [SP, #32]
    bl   format_u64
    ldr  X30, [SP, #32]

    mov  X0, #1
    adrp X1, msg_count@PAGE
    add  X1, X1, msg_count@PAGEOFF
    mov  X2, #14
    mov  X16, #SYS_WRITE
    svc  #0x80

    mov  X0, #1
    adrp X1, num_buf@PAGE
    add  X1, X1, num_buf@PAGEOFF
    mov  X2, #12
    mov  X16, #SYS_WRITE
    svc  #0x80

    mov  X0, #1
    adrp X1, newline@PAGE
    add  X1, X1, newline@PAGEOFF
    mov  X2, #1
    mov  X16, #SYS_WRITE
    svc  #0x80

    // ── Print "Time: SS.NNNNNNNNN s\n" ───────────────────────────────────
    mov  X0, #1
    adrp X1, msg_time@PAGE
    add  X1, X1, msg_time@PAGEOFF
    mov  X2, #6
    mov  X16, #SYS_WRITE
    svc  #0x80

    // format whole seconds
    adrp X0, num_buf@PAGE
    add  X0, X0, num_buf@PAGEOFF
    mov  X1, X26
    str  X30, [SP, #32]
    bl   format_u64
    ldr  X30, [SP, #32]

    mov  X0, #1
    adrp X1, num_buf@PAGE
    add  X1, X1, num_buf@PAGEOFF
    mov  X2, #12
    mov  X16, #SYS_WRITE
    svc  #0x80

    // decimal point
    mov  X0, #1
    adrp X1, dot@PAGE
    add  X1, X1, dot@PAGEOFF
    mov  X2, #1
    mov  X16, #SYS_WRITE
    svc  #0x80

    // format nanosecond remainder (9 digits, zero-padded)
    adrp X0, num_buf@PAGE
    add  X0, X0, num_buf@PAGEOFF
    mov  X1, X27
    str  X30, [SP, #32]
    bl   format_u64_9
    ldr  X30, [SP, #32]

    mov  X0, #1
    adrp X1, num_buf@PAGE
    add  X1, X1, num_buf@PAGEOFF
    mov  X2, #9
    mov  X16, #SYS_WRITE
    svc  #0x80

    mov  X0, #1
    adrp X1, msg_sec@PAGE
    add  X1, X1, msg_sec@PAGEOFF
    mov  X2, #3
    mov  X16, #SYS_WRITE
    svc  #0x80

    // ── Exit cleanly ──────────────────────────────────────────────────────
    add  SP, SP, #48
    mov  X0, #0
    mov  X16, #SYS_EXIT
    svc  #0x80


// ══════════════════════════════════════════════════════════════════════════
// format_u64 — 64-bit unsigned integer → right-aligned ASCII in 12-byte buf
//   X0 = pointer to 12-byte buffer (space-padded on the left)
//   X1 = value
//   Clobbers: X2–X8
// ══════════════════════════════════════════════════════════════════════════
format_u64:
    mov  X8, X0
    mov  X2, #12
    mov  X3, #0x20              // ASCII space
.fill_spaces:
    strb W3, [X8], #1
    subs X2, X2, #1
    bne  .fill_spaces

    add  X8, X0, #11            // point at last byte
    mov  X2, #10
    cbz  X1, .write_zero
.digit_loop:
    cbz  X1, .fmt_done
    udiv X3, X1, X2
    msub X4, X3, X2, X1         // X4 = value mod 10
    add  X4, X4, #0x30
    strb W4, [X8], #-1
    mov  X1, X3
    b    .digit_loop
.write_zero:
    mov  X3, #0x30
    strb W3, [X8]
.fmt_done:
    ret

// ══════════════════════════════════════════════════════════════════════════
// format_u64_9 — write exactly 9 digits (zero-padded) into 9-byte buffer
//   X0 = pointer to 9-byte buffer
//   X1 = value (0 .. 999,999,999)
//   Clobbers: X2–X8
// ══════════════════════════════════════════════════════════════════════════
format_u64_9:
    add  X8, X0, #8             // point at last byte
    mov  X2, #10
    mov  X3, #9                 // 9 digits to emit
.ns_loop:
    udiv X4, X1, X2
    msub X5, X4, X2, X1         // remainder
    add  X5, X5, #0x30
    strb W5, [X8], #-1
    mov  X1, X4
    subs X3, X3, #1
    bne  .ns_loop
    ret


// ══════════════════════════════════════════════════════════════════════════
// Data — all in __DATA,__data to prevent linker string merging
// ══════════════════════════════════════════════════════════════════════════
.section __DATA,__data
.align 2
msg_start: .ascii "Computing primes to 100M...\n\n"
msg_count: .ascii "Primes found: "
msg_time:  .ascii "Time: "
msg_sec:   .ascii " s\n"
dot:       .ascii "."
newline:   .ascii "\n"
num_buf:   .space 12
