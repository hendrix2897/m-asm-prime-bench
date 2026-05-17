To run this, download the latest release on an Apple Silicon Mac.

Then, `chmod +x asm-prime-bench` in the terminal.

When first run, Apple will, as usually, block it. 
You have to go into Settings->Privacy & Security, scroll down and allowrunning the unsigned program.

It will prompt you for your user password. It will be able to run without hassle afterwards.

**Note this only benchmarks single core, never multi-core.**

Sample results:

M4:

Primes found:      5761455

Time:           13.442245000 s

M2:

Primes found:      5761455

Time:           18.153635690 s

