# =================================================
# Makefile based Human68k cross-compiler setup.
# Modeled after amiga-gcc by Stefan "Bebbo" Franke.
# =================================================
include disable_implicite_rules.mk
# =================================================
# variables
# =================================================
$(eval SHELL = $(shell which bash 2>/dev/null) )

PREFIX ?= /opt/human68k
export PATH := $(PREFIX)/bin:$(PATH)

TARGET ?= m68k-human68k

UNAME_S := $(shell uname -s)
BUILD := $(shell pwd)/build-$(UNAME_S)-$(TARGET)
PROJECTS := $(shell pwd)/projects
DOWNLOAD := $(shell pwd)/download
__BUILDDIR := $(shell mkdir -p $(BUILD))
__PROJECTDIR := $(shell mkdir -p $(PROJECTS))
__DOWNLOADDIR := $(shell mkdir -p $(DOWNLOAD))

GCC_VERSION ?= $(shell cat 2>/dev/null $(PROJECTS)/gcc/gcc/BASE-VER)

ifeq ($(UNAME_S), Darwin)
	SED := gsed
else ifeq ($(UNAME_S), FreeBSD)
	SED := gsed
else
	SED := sed
endif

# get git urls and branches from .repos file
$(shell  [ ! -f .repos ] && cp default-repos .repos)
modules := $(shell cat .repos | $(SED) -e 's/[[:blank:]]\+/ /g' | cut -d' ' -f1)
get_url = $(shell grep $(1) .repos | $(SED) -e 's/[[:blank:]]\+/ /g' | cut -d' ' -f2)
get_branch = $(shell grep $(1) .repos | $(SED) -e 's/[[:blank:]]\+/ /g' | cut -d' ' -f3)
$(foreach modu,$(modules),$(eval $(modu)_URL=$(call get_url,$(modu))))
$(foreach modu,$(modules),$(eval $(modu)_BRANCH=$(call get_branch,$(modu))))

CFLAGS ?= -Os
CXXFLAGS ?= $(CFLAGS)
CFLAGS_FOR_TARGET ?= -O2 -fomit-frame-pointer -fno-jump-tables
CXXFLAGS_FOR_TARGET ?= $(CFLAGS_FOR_TARGET) -fno-exceptions -fno-rtti

E:=CFLAGS="$(CFLAGS)" CXXFLAGS="$(CXXFLAGS)" CFLAGS_FOR_BUILD="$(CFLAGS)" CXXFLAGS_FOR_BUILD="$(CXXFLAGS)" CFLAGS_FOR_TARGET="$(CFLAGS_FOR_TARGET)" CXXFLAGS_FOR_TARGET="$(CFLAGS_FOR_TARGET)"

# =================================================
# determine exe extension for cygwin
$(eval MYMAKE = $(shell which $(MAKE) 2>/dev/null) )
$(eval MYMAKEEXE = $(shell which "$(MYMAKE:%=%.exe)" 2>/dev/null) )
EXEEXT:=$(MYMAKEEXE:%=.exe)

# Files for GMP, MPC and MPFR
GMP := gmp-6.1.2
GMPFILE := $(GMP).tar.bz2
MPC := mpc-1.0.3
MPCFILE := $(MPC).tar.gz
MPFR := mpfr-3.1.6
MPFRFILE := $(MPFR).tar.bz2

# =================================================
# pretty output
# =================================================
TEEEE := >&

$(eval has_flock = $(shell which flock 2>/dev/null))
ifeq ($(has_flock),)
FLOCK := echo >/dev/null
else
FLOCK := $(has_flock)
endif

L0 = @__p=
L00 = __p=
ifneq ($(VERBOSE),)
verbose = $(VERBOSE)
endif
ifeq ($(verbose),)
L1 = ; ($(FLOCK) 200; echo -e \\033[33m$$__p...\\033[0m >>.state; echo -ne \\033[33m$$__p...\\033[0m ) 200>.lock; mkdir -p log; __l="log/$$__p.log" ; (
L2 = )$(TEEEE) "$$__l"; __r=$$?; ($(FLOCK) 200; if (( $$__r > 0 )); then \
  echo -e \\n\\033[K\\033[31m$$__p...failed\\033[0m; \
   $(SED) -n '1,/\*\*\*/p' "$$__l" | tail -n 100; \
  echo -e \\033[31m$$__p...failed\\033[0m; \
  echo -e use \\033[1mless \"$$__l\"\\033[0m to view the full log and search for \*\*\*; \
  else echo -e \\n\\033[K\\033[32m$$__p...done\\033[0m; fi \
  ;grep -v "$$__p" .state >.state0 2>/dev/null; mv .state0 .state ;echo -n $$(cat .state | paste -sd " " -); ) 200>.lock; [[ $$__r -gt 0 ]] && exit $$__r; echo -n ""
else
L1 = ;(
L2 = )
endif

# =================================================
# download files
# =================================================
define get-file
$(L0)"downloading $(1)"$(L1) cd $(DOWNLOAD); \
  mv $(3) $(3).bak; \
  wget $(2) -O $(3).neu; \
  if [ -s $(3).neu ]; then \
    if [ "$$(cmp --silent $(3).neu $(3).bak); echo $$?" == 0 ]; then \
      mv $(3).bak $(3); \
      rm $(3).neu; \
    else \
      mv $(3).neu $(3); \
      rm -f $(3).bak; \
    fi \
  else \
    rm $(3).neu; \
  fi; \
  cd .. $(L2)
endef

# =================================================
.PHONY: x init
x:
	@$(MAKE) help

# =================================================
# help
# =================================================
.PHONY: help
help:
	@echo "make help                    display this help"
	@echo "make info                    print prefix and other flags"
	@echo "make all                     build and install all"
	@echo "make min                     build and install the minimal to use gcc"
	@echo "make <target>                builds a target: binutils, gcc, newlib, libgcc, gdb, vasm"
	@echo "make clean                   remove the build folder"
	@echo "make clean-<target>          remove the target's build folder"
	@echo "make drop-prefix             remove all content from the prefix folder"
	@echo "make update                  perform git pull for all targets"
	@echo "make update-<target>         perform git pull for the given target"
	@echo "make init                    clone repos and create human68k branches"

# =================================================
# all / min
# =================================================
.PHONY: all min gcc gdb binutils newlib libgcc

all: binutils gcc newlib libgcc gdb tools vasm

min: binutils gcc newlib libgcc tools vasm

# =================================================
# clean
# =================================================
.PHONY: drop-prefix clean clean-gcc clean-binutils clean-libgcc clean-newlib clean-gdb clean-vasm

clean: clean-gcc clean-binutils clean-newlib
	rm -rf $(BUILD)
	rm -rf *.log
	mkdir -p $(BUILD)

clean-gcc:
	rm -rf $(BUILD)/gcc

clean-libgcc:
	rm -rf $(BUILD)/gcc/$(TARGET)
	rm -rf $(BUILD)/gcc/_libgcc_done

clean-binutils:
	rm -rf $(BUILD)/binutils

clean-newlib:
	rm -rf $(BUILD)/newlib

clean-gdb:
	rm -rf $(BUILD)/binutils/_gdb

# drop-prefix drops the files from prefix folder
drop-prefix:
	rm -rf $(PREFIX)/bin
	rm -rf $(PREFIX)/etc
	rm -rf $(PREFIX)/info
	rm -rf $(PREFIX)/libexec
	rm -rf $(PREFIX)/lib/gcc
	rm -rf $(PREFIX)/$(TARGET)
	rm -rf $(PREFIX)/man
	rm -rf $(PREFIX)/share
	@mkdir -p $(PREFIX)/bin

# =================================================
# init: clone repos and create human68k branches
# =================================================
init: $(PROJECTS)/binutils/configure $(PROJECTS)/gcc/configure $(PROJECTS)/newlib/newlib/configure $(PROJECTS)/run68x/CMakeLists.txt
	@for proj in binutils gcc newlib; do \
		cd $(PROJECTS)/$$proj && \
		if ! git rev-parse --verify human68k >/dev/null 2>&1; then \
			echo "Creating human68k branch in $$proj..."; \
			git checkout -b human68k; \
		else \
			echo "human68k branch already exists in $$proj"; \
			git checkout human68k; \
		fi; \
		cd $(PROJECTS); \
	done

# =================================================
# update all projects
# =================================================
.PHONY: update update-gcc update-binutils update-newlib update-vasm

update: update-gcc update-binutils update-newlib update-vasm

update-gcc: $(PROJECTS)/gcc/configure
	@cd $(PROJECTS)/gcc && git pull || (export DEPTH=16; while true; do echo "trying depth=$$DEPTH"; git pull --depth $$DEPTH && break; export DEPTH=$$(($$DEPTH+$$DEPTH));done)

update-binutils: $(PROJECTS)/binutils/configure
	@cd $(PROJECTS)/binutils && git pull || (export DEPTH=16; while true; do echo "trying depth=$$DEPTH"; git pull --depth $$DEPTH && break; export DEPTH=$$(($$DEPTH+$$DEPTH));done)

update-newlib: $(PROJECTS)/newlib/newlib/configure
	@cd $(PROJECTS)/newlib && git pull || (export DEPTH=16; while true; do echo "trying depth=$$DEPTH"; git pull --depth $$DEPTH && break; export DEPTH=$$(($$DEPTH+$$DEPTH));done)

# =================================================
# binutils
# =================================================
CONFIG_BINUTILS = --prefix=$(PREFIX) --target=$(TARGET) --disable-werror --disable-nls --disable-plugins

# FreeBSD, OSX : libs added by the command brew install gmp
ifeq (Darwin, $(findstring Darwin, $(UNAME_S)))
	BREW_PREFIX := $$(brew --prefix)
	CONFIG_BINUTILS += --with-libgmp-prefix=$(BREW_PREFIX)
endif

ifeq (FreeBSD, $(findstring FreeBSD, $(UNAME_S)))
	PORTS_PREFIX?=/usr/local
	CONFIG_BINUTILS += --with-libgmp-prefix=$(PORTS_PREFIX)
endif

BINUTILS_CMD := $(TARGET)-addr2line $(TARGET)-ar $(TARGET)-as $(TARGET)-c++filt \
	$(TARGET)-ld $(TARGET)-nm $(TARGET)-objcopy $(TARGET)-objdump $(TARGET)-ranlib \
	$(TARGET)-readelf $(TARGET)-size $(TARGET)-strings $(TARGET)-strip
BINUTILS := $(patsubst %,$(PREFIX)/bin/%$(EXEEXT), $(BINUTILS_CMD))

BINUTILS_DIR := . bfd gas ld binutils opcodes
BINUTILSD := $(patsubst %,$(PROJECTS)/binutils/%, $(BINUTILS_DIR))

binutils: $(BUILD)/binutils/_done

$(BUILD)/binutils/_done: $(BUILD)/binutils/Makefile $(shell find 2>/dev/null $(PROJECTS)/binutils -not \( -path $(PROJECTS)/binutils/.git -prune \) -not \( -path $(PROJECTS)/binutils/gprof -prune \) -type f)
	@touch -t 0001010000 $(PROJECTS)/binutils/binutils/arparse.y
	@touch -t 0001010000 $(PROJECTS)/binutils/binutils/arlex.l
	@touch -t 0001010000 $(PROJECTS)/binutils/ld/ldgram.y
	@touch -t 0001010000 $(PROJECTS)/binutils/intl/plural.y
	$(L0)"make binutils bfd"$(L1)$(MAKE) -C $(BUILD)/binutils all-bfd $(L2)
	$(L0)"make binutils gas"$(L1)$(MAKE) -C $(BUILD)/binutils all-gas $(L2)
	$(L0)"make binutils binutils"$(L1)$(MAKE) -C $(BUILD)/binutils all-binutils $(L2)
	$(L0)"make binutils ld"$(L1)$(MAKE) -C $(BUILD)/binutils all-ld $(L2)
	$(L0)"install binutils"$(L1)$(MAKE) -C $(BUILD)/binutils install-gas install-binutils install-ld $(L2)
	@echo "done" >$@

$(BUILD)/binutils/Makefile: $(PROJECTS)/binutils/configure
	@mkdir -p $(BUILD)/binutils
	$(L0)"configure binutils"$(L1) cd $(BUILD)/binutils && $(E) $(PROJECTS)/binutils/configure $(CONFIG_BINUTILS) $(L2)

$(PROJECTS)/binutils/configure:
	@cd $(PROJECTS) && git clone -b $(binutils_BRANCH) --depth 16 $(binutils_URL) binutils

# =================================================
# gdb
# =================================================
gdb: $(BUILD)/binutils/_gdb

$(BUILD)/binutils/_gdb: $(BUILD)/binutils/_done
	$(L0)"make gdb configure"$(L1)$(MAKE) -C $(BUILD)/binutils configure-gdb $(L2)
	$(L0)"make gdb libs"$(L1)$(MAKE) -C $(BUILD)/binutils/gdb all-lib $(L2)
	$(L0)"make gdb"$(L1)$(MAKE) -C $(BUILD)/binutils all-gdb $(L2)
	$(L0)"install gdb"$(L1)$(MAKE) -C $(BUILD)/binutils install-gdb $(L2)
	@echo "done" >$@

# =================================================
# gcc
# =================================================
CONFIG_GCC = --prefix=$(PREFIX) --target=$(TARGET) --enable-languages=c,c++ --disable-lto --disable-libssp --disable-nls \
	--with-newlib --without-headers --disable-shared --disable-werror \
	--with-headers=$(PROJECTS)/newlib/newlib/libc/sys/human68k/include/

# FreeBSD, OSX : libs added by the command brew install gmp mpfr libmpc
ifeq (Darwin, $(findstring Darwin, $(UNAME_S)))
	BREW_PREFIX := $$(brew --prefix)
	CONFIG_GCC += --with-gmp=$(BREW_PREFIX) \
		--with-mpfr=$(BREW_PREFIX) \
		--with-mpc=$(BREW_PREFIX)
endif

ifeq (FreeBSD, $(findstring FreeBSD, $(UNAME_S)))
	PORTS_PREFIX?=/usr/local
	CONFIG_GCC += --with-gmp=$(PORTS_PREFIX) \
		--with-mpfr=$(PORTS_PREFIX) \
		--with-mpc=$(PORTS_PREFIX)
endif

GCC_CMD := $(TARGET)-c++ $(TARGET)-g++ $(TARGET)-gcc-$(GCC_VERSION) $(TARGET)-gcc-nm \
	$(TARGET)-gcov $(TARGET)-gcov-tool $(TARGET)-cpp $(TARGET)-gcc $(TARGET)-gcc-ar \
	$(TARGET)-gcc-ranlib $(TARGET)-gcov-dump
GCC := $(patsubst %,$(PREFIX)/bin/%$(EXEEXT), $(GCC_CMD))

GCC_DIR := . gcc gcc/c gcc/c-family gcc/cp gcc/config/m68k libiberty libcpp libdecnumber
GCCD := $(patsubst %,$(PROJECTS)/gcc/%, $(GCC_DIR))

gcc: $(BUILD)/gcc/_done

$(BUILD)/gcc/_done: $(BUILD)/gcc/Makefile $(shell find 2>/dev/null $(GCCD) -maxdepth 1 -type f )
	$(L0)"make gcc"$(L1) $(MAKE) -C $(BUILD)/gcc all-gcc $(L2)
	$(L0)"install gcc"$(L1) $(MAKE) -C $(BUILD)/gcc install-gcc $(L2)
	@echo "done" >$@

$(BUILD)/gcc/Makefile: $(PROJECTS)/gcc/configure $(BUILD)/binutils/_done
	@mkdir -p $(BUILD)/gcc
ifneq ($(OWNGMP),)
	@mkdir -p $(PROJECTS)/gcc/gmp
	@mkdir -p $(PROJECTS)/gcc/mpc
	@mkdir -p $(PROJECTS)/gcc/mpfr
	@rsync -a --no-group $(PROJECTS)/$(GMP)/* $(PROJECTS)/gcc/gmp
	@rsync -a --no-group $(PROJECTS)/$(MPC)/* $(PROJECTS)/gcc/mpc
	@rsync -a --no-group $(PROJECTS)/$(MPFR)/* $(PROJECTS)/gcc/mpfr
endif
	$(L0)"configure gcc"$(L1) cd $(BUILD)/gcc && $(E) $(PROJECTS)/gcc/configure $(CONFIG_GCC) $(L2)

$(PROJECTS)/gcc/configure:
	@cd $(PROJECTS) && git clone -b $(gcc_BRANCH) --depth 16 $(gcc_URL)

# =================================================
# newlib
# =================================================
NEWLIB_CONFIG := CC=$(TARGET)-gcc CXX=$(TARGET)-g++
NEWLIB_FILES = $(shell find 2>/dev/null $(PROJECTS)/newlib/newlib -type f)

.PHONY: newlib
newlib: $(BUILD)/newlib/_done

$(BUILD)/newlib/_done: $(BUILD)/newlib/newlib/libc.a
	@echo "done" >$@

$(BUILD)/newlib/newlib/libc.a: $(BUILD)/newlib/newlib/Makefile $(NEWLIB_FILES)
	@rsync -a --no-group $(PROJECTS)/newlib/newlib/libc/include/ $(PREFIX)/$(TARGET)/sys-include
	$(L0)"make newlib"$(L1) $(MAKE) -C $(BUILD)/newlib/newlib \
	  || ($(MAKE) -C $(BUILD)/newlib/newlib/libc/stdlib lib_a-ldtoa.o CFLAGS="-O0 -fno-jump-tables" \
	      && $(MAKE) -C $(BUILD)/newlib/newlib) $(L2)
	$(L0)"install newlib"$(L1) $(MAKE) -C $(BUILD)/newlib/newlib install $(L2)
	@touch $@

$(BUILD)/newlib/newlib/Makefile: $(PROJECTS)/newlib/newlib/configure $(BUILD)/gcc/_done
	@mkdir -p $(BUILD)/newlib/newlib
	@if [ ! -f "$(BUILD)/newlib/newlib/Makefile" ]; then \
	$(L00)"configure newlib"$(L1) cd $(BUILD)/newlib/newlib && $(NEWLIB_CONFIG) CFLAGS="$(CFLAGS_FOR_TARGET)" CC_FOR_BUILD="$(CC)" CXXFLAGS="$(CXXFLAGS_FOR_TARGET)" $(PROJECTS)/newlib/newlib/configure --host=$(TARGET) --prefix=$(PREFIX) --enable-newlib-nano-malloc $(L2) \
	; else touch "$(BUILD)/newlib/newlib/Makefile"; fi

$(PROJECTS)/newlib/newlib/configure:
	@cd $(PROJECTS) && git clone -b $(newlib_BRANCH) --depth 16 $(newlib_URL) newlib

# =================================================
# libgcc (rebuild after newlib)
# =================================================
libgcc: $(BUILD)/gcc/_libgcc_done

$(BUILD)/gcc/_libgcc_done: $(BUILD)/newlib/_done $(shell find 2>/dev/null $(PROJECTS)/gcc/libgcc -type f)
	$(L0)"make libgcc"$(L1) $(MAKE) -C $(BUILD)/gcc all-target \
	  || ($(SED) -i 's/^GCC_CFLAGS = -O2/GCC_CFLAGS = -O0/' $(BUILD)/gcc/gcc/libgcc.mvars \
	      && $(MAKE) -C $(BUILD)/gcc all-target) $(L2)
	$(L0)"install libgcc"$(L1) $(MAKE) -C $(BUILD)/gcc install-target $(L2)
	@echo "done" >$@

# =================================================
# tools (elf2x68k converter + run68 emulator)
# =================================================
.PHONY: tools
tools: $(PREFIX)/bin/elf2x68k $(PREFIX)/bin/run68 $(PREFIX)/bin/hudson-bridge

$(PREFIX)/bin/elf2x68k: tools/elf2x68k.c
	$(L0)"build elf2x68k"$(L1) $(CC) -Wall -O2 -o $@ $< $(L2)

$(PREFIX)/bin/hudson-bridge: tools/hudson-bridge.c
	$(L0)"build hudson-bridge"$(L1) $(CC) -Wall -O2 -o $@ $< $(L2)

$(PREFIX)/bin/run68: $(BUILD)/run68x/run68
	@install -s $< $@

$(BUILD)/run68x/run68: $(PROJECTS)/run68x/CMakeLists.txt $(shell find 2>/dev/null $(PROJECTS)/run68x/src -type f)
	@mkdir -p $(BUILD)/run68x
	$(L0)"build run68"$(L1) cd $(BUILD)/run68x && cmake $(PROJECTS)/run68x -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="-Wno-format-truncation" && $(MAKE) $(L2)

$(PROJECTS)/run68x/CMakeLists.txt:
	@cd $(PROJECTS) && git clone -b $(run68x_BRANCH) --depth 16 $(run68x_URL) run68x

# =================================================
# vasm (m68k assembler)
# =================================================
VASM_CMD := vasmm68k_mot
VASM := $(patsubst %,$(PREFIX)/bin/%$(EXEEXT), $(VASM_CMD))

.PHONY: vasm asm-inc

vasm: $(BUILD)/vasm/_done asm-inc

$(BUILD)/vasm/_done: $(BUILD)/vasm/Makefile
	$(L0)"make vasm"$(L1) $(MAKE) -C $(BUILD)/vasm CPU=m68k SYNTAX=mot $(L2)
	@mkdir -p $(PREFIX)/bin/
	$(L0)"install vasm"$(L1) install $(BUILD)/vasm/vasmm68k_mot $(PREFIX)/bin/ ;\
	install $(BUILD)/vasm/vobjdump $(PREFIX)/bin/ $(L2)
	@echo "done" >$@

$(BUILD)/vasm/Makefile: $(PROJECTS)/vasm/Makefile $(shell find 2>/dev/null $(PROJECTS)/vasm -not \( -path $(PROJECTS)/vasm/.git -prune \) -type f)
	@rsync -a --no-group $(PROJECTS)/vasm $(BUILD)/ --exclude .git
	@touch $(BUILD)/vasm/Makefile

$(PROJECTS)/vasm/Makefile:
	@cd $(PROJECTS) && git clone -b $(vasm_BRANCH) --depth 4 $(vasm_URL)

clean-vasm:
	rm -rf $(BUILD)/vasm

update-vasm: $(PROJECTS)/vasm/Makefile
	@cd $(PROJECTS)/vasm && git pull

# =================================================
# assembly include files (dos.inc, iocs.inc)
# =================================================
ASM_INC_DIR := $(PREFIX)/$(TARGET)/include/asm

asm-inc: $(ASM_INC_DIR)/dos.inc $(ASM_INC_DIR)/iocs.inc

$(ASM_INC_DIR)/dos.inc $(ASM_INC_DIR)/iocs.inc: tools/gen-asm-inc.sh $(PROJECTS)/newlib/newlib/configure
	@mkdir -p $(ASM_INC_DIR)
	$(L0)"generate asm includes"$(L1) tools/gen-asm-inc.sh $(PROJECTS)/newlib/newlib/libc/sys/human68k $(ASM_INC_DIR) $(L2)

# =================================================
# run gcc torture check
# =================================================
.PHONY: check check-torture check-human68k check-vasm
check: check-human68k check-vasm check-torture

check-human68k:
	HUMAN68K_PREFIX=$(PREFIX) testsuite/human68k/run-tests.sh

check-vasm:
	HUMAN68K_PREFIX=$(PREFIX) testsuite/vasm/run-tests.sh

check-torture:
	@grep -q 'boards_dir.*testsuite/boards' $(BUILD)/gcc/gcc/site.exp 2>/dev/null || \
		echo 'lappend boards_dir "$(shell pwd)/testsuite/boards"' >> $(BUILD)/gcc/gcc/site.exp
	HUMAN68K_PREFIX=$(PREFIX) $(MAKE) -C $(BUILD)/gcc check-gcc-c "RUNTESTFLAGS=--target_board=human68k execute.exp=* SIM=run68" | grep '# of\|PASS\|FAIL\|===\|Running\|Using'

# =================================================
# info
# =================================================
.PHONY: info v r b l
info:
	@echo $@ $(UNAME_S)
	@echo PREFIX=$(PREFIX)
	@echo GCC_VERSION=$(GCC_VERSION)
	@echo CFLAGS=$(CFLAGS)
	@echo CFLAGS_FOR_TARGET=$(CFLAGS_FOR_TARGET)
	@$(CC) -v -E - </dev/null |& grep " version "
	@echo $(BUILD)
	@echo $(PROJECTS)
	@echo MODULES = $(modules)

# print the latest git log entry for all projects
l:
	@for i in $(PROJECTS)/* ; do pushd . >/dev/null; cd $$i 2>/dev/null && ([[ -d ".git" ]] && echo $$i && git log -n1 --pretty=format:'%C(yellow)%h %Cred%ad %Cblue%an%Cgreen%d %Creset%s' --date=short); popd >/dev/null; done
	@echo "." && git log -n1 --pretty=format:'%C(yellow)%h %Cred%ad %Cblue%an%Cgreen%d %Creset%s' --date=short

# print the git remotes for all projects
r:
	@for i in $(PROJECTS)/* ; do pushd . >/dev/null; cd $$i 2>/dev/null && ([[ -d ".git" ]] && echo $$i && git remote -v); popd >/dev/null; done
	@echo "." && git remote -v

# print the git branches for all projects
b:
	@for i in $(PROJECTS)/* ; do pushd . >/dev/null; cd $$i 2>/dev/null && ([[ -d ".git" ]] && echo $$i && (git branch | grep '*')); popd >/dev/null; done
	@echo "." && git branch | grep '*'
