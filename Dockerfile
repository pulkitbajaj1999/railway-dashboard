# ===============================================
# STAGE: 0 - CLONE GITHUB REPOS
# ===============================================

# Stage 1: Clone repository with submodules
FROM alpine/git:latest AS prebuild

ARG GITHUB_USERNAME
ARG GITHUB_REPO_URL
ARG GITHUB_TOKEN
ARG RAILWAY_GIT_COMMIT_SHA

ENV GITHUB_TOKEN=${GITHUB_TOKEN}
ENV RAILWAY_GIT_COMMIT_SHA=${RAILWAY_GIT_COMMIT_SHA}

RUN echo "Cache bust: ${RAILWAY_GIT_COMMIT_SHA}"

WORKDIR /repo

RUN git config --global url."https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
RUN git clone --depth=1 --single-branch --branch main ${GITHUB_REPO_URL} .
RUN git submodule init && git submodule update --depth=1


# ===============================================
# STAGE: 1 - BUILD APP : PORTFOLIO
# ===============================================
FROM oven/bun:1.3-slim AS builder1
WORKDIR /apps/portfolio

# Copy only dependency files first for better caching
COPY --from=prebuild /repo/portfolio/package.json /repo/portfolio/bun.lock* ./
RUN bun install

# Copy source and build
COPY --from=prebuild /repo/portfolio .

# declare args and environment variables
ARG APP1_BASE_PATH
ENV BASE_PATH=$APP1_BASE_PATH


RUN bun run build

# ===============================================
# STAGE: 2 - BUILD APP : DOCKER-SCRAM
# ===============================================
FROM oven/bun:1.3-slim AS builder2
WORKDIR /apps/docker-scram

# Copy the package manager files and install dependencies
COPY --from=prebuild /repo/docker-scram/frontend/package.json /repo/docker-scram/frontend/bun.lock* ./
RUN bun install

# copy rest of the files for the build creation
COPY --from=prebuild /repo/docker-scram/frontend .

# Declare the specific ARG for this stage
ARG APP2_BASE_PATH
ARG APP2_VITE_API_BASE_URL

ENV BASE_PATH=$APP2_BASE_PATH

# run the build
RUN VITE_API_BASE_URL=$APP2_VITE_API_BASE_URL bun run build

# ===============================================
# STAGE: 3 - NGINX RUNTIME (Final Image)
# ===============================================
FROM nginx:alpine AS runtime

# Set up directories for different apps
# For example: app-a at root, app-b at /app-b
WORKDIR /usr/share/nginx/html

# Copy Build-1
COPY --from=builder1 /apps/portfolio/dist ./portfolio

# Copy Build-2
COPY --from=builder2 /apps/docker-scram/dist ./docker-scram

# Copy your custom nginx config from the main repo
COPY nginx-default.conf /etc/nginx/conf.d/default.conf

ENV PORT=80
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]