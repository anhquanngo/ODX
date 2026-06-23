set(_proj_name ceres)
set(_SB_BINARY_DIR "${SB_BINARY_DIR}/${_proj_name}")

# GPU COLMAP BA needs Ceres master (2.3 dev) + CUDA + cuDSS. CPU builds stay on 2.2.0.
set(_ceres_cmake_args
    -DCMAKE_C_FLAGS=-fPIC
    -DCMAKE_CXX_FLAGS=-fPIC
    -DBUILD_EXAMPLES=OFF
    -DBUILD_TESTING=OFF
    -DCMAKE_INSTALL_PREFIX:PATH=${SB_INSTALL_DIR}
    ${WIN32_CMAKE_ARGS}
)

if(ODX_GPU_BUILD)
    # Pinned master commit with cuDSS / USE_CUDA support (no 2.3.0 release tag yet).
    set(_ceres_download
        GIT_REPOSITORY https://github.com/ceres-solver/ceres-solver.git
        GIT_TAG        8a566fcc156322160b96f8ca5f0ff755241c2d33
    )
    set(_ceres_depends gflags abseil)
    list(APPEND _ceres_cmake_args
        -DUSE_CUDA=ON
        -DMINIGLOG=OFF
        -DCMAKE_CXX_STANDARD=17
        "-DCMAKE_PREFIX_PATH=${SB_INSTALL_DIR}"
    )
    include(${CMAKE_CURRENT_LIST_DIR}/FindCUDSS.cmake)
    if(cudss_DIR)
        list(APPEND _ceres_cmake_args -Dcudss_DIR=${cudss_DIR})
    endif()
    if(cudss_INCLUDE_DIR)
        list(APPEND _ceres_cmake_args -Dcudss_INCLUDE_DIR=${cudss_INCLUDE_DIR})
    endif()
    message(STATUS "Ceres: GPU build (USE_CUDA=ON, MINIGLOG=OFF)")
else()
    set(_ceres_download
        URL http://ceres-solver.org/ceres-solver-2.2.0.tar.gz
    )
    list(APPEND _ceres_cmake_args
        -DUSE_CUDA=OFF
        -DMINIGLOG=ON
        -DMINIGLOG_MAX_LOG_LEVEL=-100
    )
    message(STATUS "Ceres: CPU build (2.2.0, USE_CUDA=OFF)")
endif()

if(NOT ODX_GPU_BUILD)
    set(_ceres_depends gflags)
endif()

ExternalProject_Add(${_proj_name}
  DEPENDS           ${_ceres_depends}
  PREFIX            ${_SB_BINARY_DIR}
  TMP_DIR           ${_SB_BINARY_DIR}/tmp
  STAMP_DIR         ${_SB_BINARY_DIR}/stamp
  DOWNLOAD_DIR      ${SB_DOWNLOAD_DIR}
  ${_ceres_download}
  UPDATE_COMMAND    ""
  SOURCE_DIR        ${SB_SOURCE_DIR}/${_proj_name}
  CMAKE_ARGS        ${_ceres_cmake_args}
  BINARY_DIR        ${_SB_BINARY_DIR}
  INSTALL_DIR       ${SB_INSTALL_DIR}
  LOG_DOWNLOAD      OFF
  LOG_CONFIGURE     OFF
  LOG_BUILD         OFF
)
