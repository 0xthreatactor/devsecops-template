# Multi-stage build for security
FROM node:18-alpine AS builder

# Add non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY yarn.lock ./

# Install dependencies with security audit
RUN yarn install --frozen-lockfile --production=false && \
    yarn audit --level=moderate

# Copy source code
COPY --chown=nodejs:nodejs . .

# Build application
RUN yarn build

# Production stage
FROM node:18-alpine

# Install tini for proper signal handling
RUN apk add --no-cache tini

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app

# Copy built assets from builder
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --from=builder --chown=nodejs:nodejs /app/package*.json ./
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules

# Security hardening
RUN apk del apk-tools && \
    rm -rf /var/cache/apk/* && \
    rm -rf /tmp/*

# Switch to non-root user
USER nodejs

# Security labels
LABEL security.privileged="false" \
      security.readonly-rootfs="true" \
      security.capabilities.drop="all"

# Use tini as init
ENTRYPOINT ["/sbin/tini", "--"]

# Start application
CMD ["node", "dist/main.js"]

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"
