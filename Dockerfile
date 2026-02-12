# docker build -t human68k .
# docker run -v $PWD:/host --rm -it human68k
# ( --platform linux/amd64 )

FROM debian:12-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && apt-get install -y \
    build-essential git wget bison flex texinfo rsync \
    libgmp-dev libmpfr-dev libmpc-dev libncurses-dev \
    cmake

RUN git clone -b gcc-6.5.0 https://github.com/erique/human68k-gcc.git /tmp/human68k-gcc
WORKDIR /tmp/human68k-gcc
RUN make min

FROM debian:12-slim

COPY --from=builder /opt/human68k /opt/human68k

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    make git libmpc3 libmpfr6 libgmp10 && \
    rm -rf /var/lib/apt/lists/* && \
    chmod o+r -R /opt/human68k && \
    useradd -m -s /bin/bash user && \
    echo 'export PATH=/opt/human68k/bin:$PATH' >> /home/user/.bashrc

USER user
ENV PATH=/opt/human68k/bin:$PATH
WORKDIR /home/user
