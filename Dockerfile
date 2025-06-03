# docker build -t human68k .
# docker run -v $PWD:/host --rm -it human68k (...)
# ( --platform linux/amd64 )
# ..

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y
RUN apt-get install -y bison texinfo flex expect build-essential git wget libncurses-dev

COPY build_x68_gcc.sh /tmp/build_x68_gcc.sh
RUN /tmp/build_x68_gcc.sh && rm -rf gcc_x68k

ENV PATH=$PATH:/opt/toolchains/x68k/bin
