FROM apache/shenyu-bootstrap:2.6.1

LABEL maintainer="shenyu-client-java"
LABEL description="ShenYu 2.6.1 bootstrap with sign SPI (redis-backed public key)"
ARG BUILD_DATE
LABEL build-date="${BUILD_DATE}"

COPY /shenyu-bootstrap/ext-lib/shenyu-sign-gateway-spi-2.6.1.jar /opt/shenyu-bootstrap/ext-lib/
# COPY target/lib/*.jar /opt/shenyu-bootstrap/ext-lib/  # shade 后无需单独拷依赖
