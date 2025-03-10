DMD ?= dmd
GCC ?= gcc
NASM ?= nasm
RDMD ?= rdmd

ARCHFLAG ?= -m64
DFLAGS = $(ARCHFLAG) -Isrc -w -debug -g
PLATFORM = $(shell uname -s)

# DFLAGS = $(ARCHFLAG) -w -O -release

# dmd.conf doesn't set the proper -L flags.  
# Fix it here until dmd installer is updated
ifeq ($(PLATFORM),Darwin)
	LD_PATH ?= /Library/D/dmd/lib
endif

NASMFLAGS ?=
LDFLAGS ?=
ifdef LD_PATH
	override LDFLAGS += $(addprefix -L, $(LD_PATH))
endif

override LDFLAGS += -lphobos2

ifeq ($(PLATFORM),Linux)
	LD_LLD = $(shell which ld.lld | xargs basename)
	ifeq ($(LD_LLD),ld.lld)
		override LDFLAGS += -fuse-ld=lld
	endif
	override LDFLAGS += -lstdc++ -export-dynamic
	override NASMFLAGS += -f elf64
endif
ifeq ($(PLATFORM),Darwin)
	override LDFLAGS += -lc++
	override NASMFLAGS += -f macho64
endif
ifeq ($(PLATFORM),FreeBSD)
	override LDFLAGS += -lc++
	override NASMFLAGS += -f elf64
endif

# To make sure make calls all
default: all

include src/sdc.mak
include src/sdfmt.mak

all: $(ALL_EXECUTABLES) $(LIBSDRT) $(PHOBOS)

check: all

clean:
	rm -rf obj lib $(ALL_EXECUTABLES)

print-%: ; @echo $*=$($*)

.PHONY: check clean default

# Secondary without dependency make all temporaries secondary.
.SECONDARY:

include $(shell test -d obj && find obj/ -type f -name '*.deps')
