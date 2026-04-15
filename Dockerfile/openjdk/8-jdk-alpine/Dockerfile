# Stage 1: Build
FROM openjdk:8-jdk-alpine AS builder

# Set timezone and mirror once
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    sed -i "s/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g" /etc/apk/repositories

# Install build dependencies (fonts, build tools)
RUN apk add --no-cache ttf-dejavu fontconfig

# [Your application build steps go here - COPY source, RUN build, etc.]
# Example: COPY . /app
#          WORKDIR /app
#          RUN ./gradlew build -x test

# Stage 2: Runtime
FROM openjdk:8-jre-alpine

# Set timezone and mirror in runtime image
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    sed -i "s/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g" /etc/apk/repositories

# Install only runtime fonts
RUN apk add --no-cache ttf-dejavu fontconfig

# Create non-root user for security
RUN addgroup -g 1000 appgroup && adduser -D -u 1000 -G appgroup appuser

# Copy application from builder stage
# COPY --from=builder /app/build/libs/app.jar /app/app.jar

WORKDIR /app

# Switch to non-root user
USER appuser

# Health check example (adjust command for your app)
# HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
#     CMD wget --quiet --tries=1 --spider http://localhost:8080/health || exit 1

# Run application
# CMD ["java", "-jar", "/app/app.jar"]
