.PHONY: all compare clean

.SUFFIXES:
.SUFFIXES: .asm .o .gb
.SECONDEXPANSION:

# Build Lazer Pong.
ROM := lazerpong.gb
OBJS := main.o wram.o

# Link objects together to build a rom.
all: $(ROM)

# Assemble source files into objects.
# Use rgbasm -h to use halts without nops.
$(OBJS): $$*.asm $$($$*_dep)
	rgbasm -h -o $@ $<

$(ROM): $(OBJS)
	rgblink -n $(ROM:.gb=.sym) -m $(ROM:.gb=.map) -o $@ $^
	rgbfix -jsvc -k 01 -l 0x33 -m 0x1e -p 0 -r 02 -t "LAZERPONG" -i VPHE $@

# Remove files generated by the build process.
clean:
	rm -f $(ROM) $(OBJS) $(ROM:.gb=.sym)
