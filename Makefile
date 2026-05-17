asm-prime-bench: asm-prime-bench.o
	ld -o asm-prime-bench asm-prime-bench.o -lSystem -syslibroot `xcrun -sdk macosx --show-sdk-path` -e _start -arch arm64
asm-prime-bench.o: asm-prime-bench.s
	as -o asm-prime-bench.o asm-prime-bench.s
