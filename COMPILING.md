# Compiling

```sh
make min                # builds binutils, gcc, newlib, libgcc, tools, vasm
make all                # builds everything including GDB and test dependencies
make check              # runs human68k tests + GCC torture suite
```

Default install prefix is `/opt/human68k`, needs to be writable:

```sh
sudo mkdir -p /opt/human68k && sudo chown $USER /opt/human68k
```

Override with `PREFIX=/path make min`.

## Linux (Debian/Ubuntu)

```sh
sudo apt-get install build-essential git wget bison flex texinfo rsync \
    libgmp-dev libmpfr-dev libmpc-dev libncurses-dev cmake lhasa
```

For running tests (`make check`), also install:

```sh
sudo apt-get install dejagnu expect
```

### Docker

```sh
docker build -t human68k .                        # toolchain only
docker build --target=test -t human68k-test .      # full build + tests
```

## macOS (Apple Silicon)

```sh
brew install bison gnu-sed bash make wget flex texinfo rsync \
    gmp mpfr libmpc ncurses cmake lhasa gcc@12 dejagnu
```

The build requires Homebrew's `bison`, `gnu-sed`, `bash`, and `gcc-12` instead of the Xcode-provided versions:

```sh
PATH="$(brew --prefix bison)/bin:$(brew --prefix gnu-sed)/libexec/gnubin:$PATH" \
CC=gcc-12 CXX=g++-12 \
gmake -j all SHELL="$(brew --prefix)/bin/bash"
```

### Tart VM (automated)

`tart-build.sh` automates the entire macOS build in an ephemeral
[Tart](https://tart.run) VM. It installs all dependencies, builds, runs
tests, and copies artifacts out. The brew-installed VM image is cached
for faster subsequent runs.

```sh
brew install cirruslabs/cli/tart hudochenkov/sshpass/sshpass
./tart-build.sh
```

Artifacts are written to `out/`. Delete the cached VM with
`tart delete human68k-brewed` to force a fresh dependency install.
