#!/usr/bin/env bash
#
# Build & push ODX Docker images (CPU + GPU).
# Run from ODX directory or anywhere:
#   ./build-push-images.sh
#
# Environment variables (optional):
#   DOCKER_USER=anhquan01   Docker Hub username
#   VERSION=1.0.0           Version tag
#   PUSH=0|1                Push to Docker Hub after build (default: 0)
#   BUILD_CPU=0|1           Build CPU image (default: 1)
#   BUILD_GPU=0|1           Build GPU image (default: 1)
#   NO_CACHE=0|1            docker build --no-cache (default: 1)
#   SKIP_GPU_CHECK=0|1      Skip GPU checks (default: 0)
#
# Examples:
#   ./build-push-images.sh
#   PUSH=1 ./build-push-images.sh
#   BUILD_CPU=0 BUILD_GPU=1 PUSH=1 ./build-push-images.sh
#
set -euo pipefail

DOCKER_USER="${DOCKER_USER:-anhquan01}"
VERSION="${VERSION:-1.0.0}"
PUSH="${PUSH:-1}"
BUILD_CPU="${BUILD_CPU:-1}"
BUILD_GPU="${BUILD_GPU:-1}"
NO_CACHE="${NO_CACHE:-1}"
SKIP_GPU_CHECK="${SKIP_GPU_CHECK:-0}"

ODX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMG_CPU="${DOCKER_USER}/odx:${VERSION}"
IMG_CPU_LATEST="${DOCKER_USER}/odx:latest"
IMG_GPU="${DOCKER_USER}/odx:${VERSION}-gpu"
IMG_GPU_ALIAS="${DOCKER_USER}/odx:gpu"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

docker_build() {
  local dockerfile="$1"
  shift
  local -a cache_flag=()
  if [[ "${NO_CACHE}" == "1" ]]; then
    cache_flag=(--no-cache)
  fi
  log "docker build -f ${dockerfile}"
  docker build "${cache_flag[@]}" -f "${dockerfile}" "$@" "${ODX_DIR}"
}

docker_push() {
  for tag in "$@"; do
    log "docker push ${tag}"
    docker push "${tag}"
  done
}

check_gpu() {
  if [[ "${SKIP_GPU_CHECK}" == "1" ]]; then
    return 0
  fi
  log "Checking NVIDIA GPU..."
  nvidia-smi >/dev/null 2>&1 || die "nvidia-smi failed. Install driver or SKIP_GPU_CHECK=1"
  docker run --rm --gpus all nvidia/cuda:12.9.1-base-ubuntu24.04 nvidia-smi >/dev/null 2>&1 \
    || die "Docker GPU unavailable. Install nvidia-container-toolkit."
}

check_prerequisites() {
  command -v docker >/dev/null 2>&1 || die "docker not found"
  if [[ "${BUILD_CPU}" != "1" && "${BUILD_GPU}" != "1" ]]; then
    die "Set BUILD_CPU=1 and/or BUILD_GPU=1"
  fi
  if [[ "${PUSH}" == "1" ]]; then
    log "PUSH=1: ensure you ran 'docker login' as ${DOCKER_USER}"
  fi
}

build_cpu() {
  log "========== ODX CPU (portable.Dockerfile) =========="
  docker_build portable.Dockerfile -t "${IMG_CPU}" -t "${IMG_CPU_LATEST}"
  if [[ "${PUSH}" == "1" ]]; then
    docker_push "${IMG_CPU}" "${IMG_CPU_LATEST}"
  fi
  log "Done: ${IMG_CPU}, ${IMG_CPU_LATEST}"
}

build_gpu() {
  check_gpu
  log "========== ODX GPU (gpu.Dockerfile) =========="
  docker_build gpu.Dockerfile -t "${IMG_GPU}" -t "${IMG_GPU_ALIAS}"
  if [[ "${PUSH}" == "1" ]]; then
    docker_push "${IMG_GPU}" "${IMG_GPU_ALIAS}"
  fi
  log "Done: ${IMG_GPU}, ${IMG_GPU_ALIAS}"
}

print_summary() {
  log "========== ODX SUMMARY =========="
  echo "Directory: ${ODX_DIR}"
  echo "User:      ${DOCKER_USER}"
  echo "Version:   ${VERSION}"
  echo "Push:      ${PUSH}"
  if [[ "${BUILD_CPU}" == "1" ]]; then
    echo "  CPU: ${IMG_CPU}"
  fi
  if [[ "${BUILD_GPU}" == "1" ]]; then
    echo "  GPU: ${IMG_GPU}"
  fi
  echo ""
  echo "Next step — build NodeODX:"
  echo "  cd ../NodeODX && ./build-push-images.sh"
  echo ""
  if [[ "${BUILD_CPU}" == "1" ]]; then
    echo "  docker run --rm ${IMG_CPU} --help"
  fi
  if [[ "${BUILD_GPU}" == "1" ]]; then
    echo "  docker run --rm --gpus all ${IMG_GPU} --help"
  fi
}

main() {
  log "ODX dir: ${ODX_DIR}"
  check_prerequisites
  if [[ "${BUILD_CPU}" == "1" ]]; then
    build_cpu
  fi
  if [[ "${BUILD_GPU}" == "1" ]]; then
    build_gpu
  fi
  print_summary
  log "ODX build finished."
}

main "$@"
