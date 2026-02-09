# docker build -t human68k .
# docker run -v $PWD:/host --rm -it human68k (...)
# ( --platform linux/amd64 )

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && apt-get install -y \
    build-essential git wget bison flex texinfo \
    libgmp-dev libmpfr-dev libmpc-dev libncurses-dev \
    cmake

RUN git clone -b gcc-6.5.0 https://github.com/erique/human68k-gcc.git /tmp/human68k-gcc
WORKDIR /tmp/human68k-gcc
RUN make min
RUN rm -rf /tmp/human68k-gcc

ENV PATH=/opt/human68k/bin:$PATH
