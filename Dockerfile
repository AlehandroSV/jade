# Stage 1: Build - Install dependencies
FROM alpine:3.19 AS builder

RUN apk add --no-cache \
    lua5.4 \
    lua5.4-dev \
    luarocks5.4 \
    build-base \
    openssl-dev

RUN luarocks-5.4 install jade && \
    luarocks-5.4 install pgmoon && \
    luarocks-5.4 install luaossl && \
    luarocks-5.4 install dkjson && \
    luarocks-5.4 install luasocket

# Stage 2: Runtime - Minimal production image
FROM alpine:3.19

# Install only runtime dependencies
RUN apk add --no-cache \
    lua5.4 \
    openssl \
    ca-certificates

# Copy installed Lua libraries from builder stage
COPY --from=builder /usr/local/lib/lua /usr/local/lib/lua
COPY --from=builder /usr/local/share/lua /usr/local/share/lua

# Create non-root user for security
RUN addgroup -S jade && adduser -S jade -G jade

# Set working directory
WORKDIR /app

# Copy application files with proper ownership
COPY --chown=jade:jade . .

# Switch to non-root user
USER jade

# Health check to verify container health
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD lua5.4 -e "print('ok')" || exit 1

# Default command to run the application
CMD ["lua5.4", "lib/app.lua"]

# Stage 3: CLI (optional - for development only)
FROM node:18-alpine AS cli

RUN npm install -g @alehandrosv/esmeralda-cli
