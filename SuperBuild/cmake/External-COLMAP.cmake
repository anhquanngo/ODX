set(_proj_name colmap)
set(_SB_BINARY_DIR "${SB_BINARY_DIR}/${_proj_name}")

set(GPU_CMAKE_ARGS "")
if(UNIX AND NOT APPLE)
    if(EXISTS "/usr/local/cuda/lib64/stubs")
        set(GPU_CMAKE_ARGS -DCMAKE_LIBRARY_PATH=/usr/local/cuda/lib64/stubs)
    endif()
endif()

if(ODX_GPU_BUILD)
    # 3.11+ provides Mapper.ba_use_gpu (needs Ceres built with CUDA/cuDSS).
    set(COLMAP_GIT_TAG 3.11.1)
    set(COLMAP_CUDA_ARGS -DCUDA_ENABLED=OFF)
    if(NOT WIN32 AND NOT APPLE)
        if(EXISTS "/usr/local/cuda/bin/nvcc")
            set(COLMAP_CUDA_ARGS
                -DCUDA_ENABLED=ON
                "-DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
                # Common datacenter / consumer NVIDIA archs (SiftGPU + Ceres CUDA).
                "-DCMAKE_CUDA_ARCHITECTURES=75;80;86;89"
            )
        endif()
    endif()
    message(STATUS "COLMAP: GPU pipeline tag ${COLMAP_GIT_TAG}")
    list(APPEND COLMAP_CUDA_ARGS "-DCMAKE_PREFIX_PATH=${SB_INSTALL_DIR}")
else()
    # CPU image: stay on 3.9.1 (no PoseLib FetchContent churn).
    set(COLMAP_GIT_TAG 3.9.1)
    set(COLMAP_CUDA_ARGS -DCUDA_ENABLED=OFF)
    if(NOT WIN32 AND NOT APPLE)
        if(EXISTS "/usr/local/cuda/bin/nvcc")
            set(COLMAP_CUDA_ARGS
                -DCUDA_ENABLED=ON
                "-DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
                "-DCMAKE_CUDA_ARCHITECTURES=75;80;86;89"
            )
        endif()
    endif()
    message(STATUS "COLMAP: CPU pipeline tag ${COLMAP_GIT_TAG}")
endif()

set(_colmap_cxx_flags "")
if(NOT ODX_GPU_BUILD AND COLMAP_GIT_TAG VERSION_LESS 3.10)
    # GCC 13+ (Ubuntu 24.04): COLMAP 3.9.1 missing <memory> in some TUs.
    set(_colmap_cxx_flags "-DCMAKE_CXX_FLAGS=-include memory")
endif()

ExternalProject_Add(${_proj_name}
  DEPENDS           ceres opencv gflags
  PREFIX            ${_SB_BINARY_DIR}
  TMP_DIR           ${_SB_BINARY_DIR}/tmp
  STAMP_DIR         ${_SB_BINARY_DIR}/stamp
  DOWNLOAD_DIR      ${SB_DOWNLOAD_DIR}
  GIT_REPOSITORY    https://github.com/colmap/colmap.git
  GIT_TAG           ${COLMAP_GIT_TAG}
  UPDATE_COMMAND    ""
  PATCH_COMMAND     ${CMAKE_COMMAND}
                      -DCOLMAP_OPTION_MANAGER_CC=<SOURCE_DIR>/src/colmap/controllers/option_manager.cc
                      -DODX_GPU_BUILD=${ODX_GPU_BUILD}
                      -P ${CMAKE_CURRENT_LIST_DIR}/PatchCOLMAP-option-manager-miniglog.cmake
  SOURCE_DIR        ${SB_SOURCE_DIR}/${_proj_name}
  CMAKE_GENERATOR   Ninja
  CMAKE_ARGS
    -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
    ${_colmap_cxx_flags}
    -DCMAKE_INSTALL_PREFIX=${SB_INSTALL_DIR}
    -DCeres_DIR=${SB_INSTALL_DIR}/lib/cmake/Ceres
    -DOpenCV_DIR=${SB_INSTALL_DIR}/lib/cmake/opencv4
    -Dgflags_DIR=${SB_INSTALL_DIR}/lib/cmake/gflags
    -DGUI_ENABLED=OFF
    -DOPENGL_ENABLED=OFF
    -DCGAL_ENABLED=OFF
    -DTESTS_ENABLED=OFF
    -DCCACHE_ENABLED=OFF
    -DIPO_ENABLED=OFF
    ${COLMAP_CUDA_ARGS}
    ${GPU_CMAKE_ARGS}
    ${WIN32_CMAKE_ARGS}
    ${APPLE_CMAKE_ARGS}
  BINARY_DIR        ${_SB_BINARY_DIR}
  INSTALL_DIR       ${SB_INSTALL_DIR}
  LOG_DOWNLOAD      ON
  LOG_CONFIGURE     ON
  LOG_BUILD         ON
)
