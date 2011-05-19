all: current

gracelib.o: gracelib.c
	clang -emit-llvm -c gracelib.c

current.bc: current.ll gracelib-kg.o
	llvm-link -o current.bc gracelib-kg.o current.ll

current.ll: compiler.gc
	./minigrace_known-good < compiler.gc >current.ll

current.s: current.bc
	llc -o current.s current.bc

current: current.s gracelib.o
	gcc -o current current.s
selfhost: current compiler.gc gracelib.o
	./current <compiler.gc>selfhost.ll
	llvm-link -o selfhost.bc gracelib.o selfhost.ll
	llc -o selfhost.s selfhost.bc
	gcc -o selfhost selfhost.s

selfhost-stats: selfhost
	./selfhost < compiler.gc >/dev/null

clean:
	rm -f compiler.ll gracelib.o current.bc current.s current
	rm -f selfhost selfhost.s selfhost.bc selfhost.ll

.PHONY: all clean selfhost-stats
