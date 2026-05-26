#!/usr/bin/env bash
#
# Build & push ODX Docker images.
# Order: GPU first, then CPU.
# Tags: anhquan01/odx:gpu (GPU), anhquan01/odx:cpu (CPU)
#
# Environment variables (optional):
#   DOCKER_USER=anhquan01
#   PUSH=0|1                (default: 1)
#   BUILD_GPU=0|1           (default: 1) — built first
#   BUILD_CPU=0|1           (default: 1) — built after GPU
#   NO_CACHE=0|1            (default: 1)
#   SKIP_GPU_CHECK=0|1      (default: 0)
#
set -euo pipefail

DOCKER_USER="${DOCKER_USER:-anhquan01}"
PUSH="${PUSH:-1}"
BUILD_GPU="${BUILD_GPU:-1}"
BUILD_CPU="${BUILD_CPU:-1}"
NO_CACHE="${NO_CACHE:-1}"
SKIP_GPU_CHECK="${SKIP_GPU_CHECK:-0}"

ODX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMG_CPU="${DOCKER_USER}/odx:cpu"
IMG_GPU="${DOCKER_USER}/odx:gpu"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
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

build_gpu() {
  # check_gpu
  log "========== ODX GPU (gpu.Dockerfile) → ${IMG_GPU} =========="
  docker_build gpu.Dockerfile -t "${IMG_GPU}"
  if [[ "${PUSH}" == "1" ]]; then
    docker_push "${IMG_GPU}"
  fi
  log "Done: ${IMG_GPU}"
}

build_cpu() {
  log "========== ODX CPU (portable.Dockerfile) → ${IMG_CPU} =========="
  docker_build portable.Dockerfile -t "${IMG_CPU}"
  if [[ "${PUSH}" == "1" ]]; then
    docker_push "${IMG_CPU}"
  fi
  log "Done: ${IMG_CPU}"
}

print_summary() {
  log "========== ODX SUMMARY =========="
  echo "Directory: ${ODX_DIR}"
  echo "User:      ${DOCKER_USER}"
  echo "Push:      ${PUSH}"
  echo "Build order: GPU → CPU"
  if [[ "${BUILD_GPU}" == "1" ]]; then
    echo "  GPU: ${IMG_GPU}"
  fi
  if [[ "${BUILD_CPU}" == "1" ]]; then
    echo "  CPU: ${IMG_CPU}"
  fi
  echo ""
  echo "Next: cd ../NodeODX && ./build-push-images.sh"
  if [[ "${BUILD_GPU}" == "1" ]]; then
    echo "  docker run --rm --gpus all ${IMG_GPU} --help"
  fi
}

main() {
  log "ODX dir: ${ODX_DIR}"
  check_prerequisites
  # GPU first (NodeODX GPU depends on this image)
  if [[ "${BUILD_GPU}" == "1" ]]; then
    build_gpu
  fi
  if [[ "${BUILD_CPU}" == "1" ]]; then
    build_cpu
  fi
  print_summary
  log "ODX build finished."
}

main "$@"
