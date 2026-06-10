set(_proj_name colmap)
set(_SB_BINARY_DIR "${SB_BINARY_DIR}/${_proj_name}")

# COLMAP SiftGPU may need CUDA stub libs at link time (same pattern as OpenMVS).
set(GPU_CMAKE_ARGS "")
if(UNIX AND NOT APPLE)
    if(EXISTS "/usr/local/cuda/lib64/stubs")
        set(GPU_CMAKE_ARGS -DCMAKE_LIBRARY_PATH=/usr/local/cuda/lib64/stubs)
    endif()
endif()

# Headless ODX pipeline: feature_extractor, exhaustive_matcher, mapper only.
# Use COLMAP 3.9.1 (no PoseLib FetchContent — avoids network/hash failures in Docker).
set(COLMAP_CUDA_ARGS -DCUDA_ENABLED=OFF)
if(NOT WIN32 AND NOT APPLE)
    if(EXISTS "/usr/local/cuda/bin/nvcc")
        set(COLMAP_CUDA_ARGS
            -DCUDA_ENABLED=ON
            "-DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
            # RTX 2080 Ti (sm_75); single arch avoids CMake list ";" pitfalls.
            "-DCMAKE_CUDA_ARCHITECTURES=75"
        )
    endif()
endif()

ExternalProject_Add(${_proj_name}
  DEPENDS           ceres opencv gflags
  PREFIX            ${_SB_BINARY_DIR}
  TMP_DIR           ${_SB_BINARY_DIR}/tmp
  STAMP_DIR         ${_SB_BINARY_DIR}/stamp
  #--Download step--------------
  DOWNLOAD_DIR      ${SB_DOWNLOAD_DIR}
  GIT_REPOSITORY    https://github.com/colmap/colmap.git
  GIT_TAG           3.9.1
  #--Update/Patch step----------
  UPDATE_COMMAND    ""
  #--Configure step-------------
  SOURCE_DIR        ${SB_SOURCE_DIR}/${_proj_name}
  CMAKE_GENERATOR   Ninja
  CMAKE_ARGS
    -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
    # GCC 13+ (Ubuntu 24.04): COLMAP 3.9.1 uses std::unique_ptr without <memory> in several TUs.
    "-DCMAKE_CXX_FLAGS=-include memory"
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
  #--Build step-----------------
  BINARY_DIR        ${_SB_BINARY_DIR}
  #--Install step---------------
  INSTALL_DIR       ${SB_INSTALL_DIR}
  #--Output logging-------------
  LOG_DOWNLOAD      ON
  LOG_CONFIGURE     ON
  LOG_BUILD         ON
)
