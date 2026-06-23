set(_proj_name opensfm)
set(_SB_BINARY_DIR "${SB_BINARY_DIR}/${_proj_name}")
include(ProcessorCount)
ProcessorCount(nproc)

set(EXTRA_INCLUDE_DIRS "")
if(WIN32)
  set(OpenCV_DIR "${SB_INSTALL_DIR}/x64/vc17/lib")
  set(BUILD_CMD ${CMAKE_COMMAND} --build "${SB_BUILD_DIR}/opensfm" --config "${CMAKE_BUILD_TYPE}")
else()
  set(BUILD_CMD make "-j${nproc}")
  if (APPLE)
    set(OpenCV_DIR "${SB_INSTALL_DIR}")
    set(EXTRA_INCLUDE_DIRS "${HOMEBREW_INSTALL_PREFIX}/include")
  else()
    set(OpenCV_DIR "${SB_INSTALL_DIR}/lib/cmake/opencv4")
  endif()
endif()

set(_opensfm_deps ceres opencv gflags)
set(_opensfm_patch_cmd "")

if(ODX_GPU_BUILD AND NOT WIN32)
  # Install Abseil shared libs from COLMAP/Ceres before OpenSfM builds pybundle.
  list(APPEND _opensfm_deps colmap)
  set(_opensfm_patch_cmd
    PATCH_COMMAND ${CMAKE_COMMAND}
      -DOPENSFM_BUNDLE_CMAKE=<SOURCE_DIR>/opensfm/src/bundle/CMakeLists.txt
      -DSB_INSTALL_DIR=${SB_INSTALL_DIR}
      -P ${CMAKE_CURRENT_LIST_DIR}/Patch-OpenSfM-gpu-absl.cmake
  )
endif()

ExternalProject_Add(${_proj_name}
  DEPENDS           ${_opensfm_deps}
  PREFIX            ${_SB_BINARY_DIR}
  TMP_DIR           ${_SB_BINARY_DIR}/tmp
  STAMP_DIR         ${_SB_BINARY_DIR}/stamp
  #--Download step--------------
  DOWNLOAD_DIR      ${SB_DOWNLOAD_DIR}
  GIT_REPOSITORY    https://github.com/WebODM/OpenSfM/
  GIT_TAG           91f58841370b0c28bc1248d038b1930fa11d0637
  #--Update/Patch step----------
  UPDATE_COMMAND    git submodule update --init --recursive
  ${_opensfm_patch_cmd}
  #--Configure step-------------
  SOURCE_DIR        ${SB_INSTALL_DIR}/bin/${_proj_name}
  CONFIGURE_COMMAND ${CMAKE_COMMAND} <SOURCE_DIR>/${_proj_name}/src
    -DCERES_ROOT_DIR=${SB_INSTALL_DIR}
    -DOpenCV_DIR=${OpenCV_DIR}
    -DADDITIONAL_INCLUDE_DIRS=${SB_INSTALL_DIR}/include
    -DYET_ADDITIONAL_INCLUDE_DIRS=${EXTRA_INCLUDE_DIRS}
    -DOPENSFM_BUILD_TESTS=off
    -DPYTHON_EXECUTABLE=${PYTHON_EXE_PATH}
    ${WIN32_CMAKE_ARGS}
  BUILD_COMMAND ${BUILD_CMD}
  #--Build step-----------------
  BINARY_DIR        ${_SB_BINARY_DIR}
  #--Install step---------------
  INSTALL_COMMAND    ""
  #--Output logging-------------
  LOG_DOWNLOAD      OFF
  LOG_CONFIGURE     OFF
  LOG_BUILD         OFF
)
