# Shared Abseil for GPU pipeline (Ceres 2.3 / COLMAP 3.11 / OpenSfM pybundle).
# Installed to SB_INSTALL_DIR so pybundle can link libabsl_*.so at runtime.

set(_proj_name abseil)
set(_SB_BINARY_DIR "${SB_BINARY_DIR}/${_proj_name}")

ExternalProject_Add(${_proj_name}
  PREFIX            ${_SB_BINARY_DIR}
  TMP_DIR           ${_SB_BINARY_DIR}/tmp
  STAMP_DIR         ${_SB_BINARY_DIR}/stamp
  DOWNLOAD_DIR      ${SB_DOWNLOAD_DIR}
  GIT_REPOSITORY    https://github.com/abseil/abseil-cpp.git
  GIT_TAG           20250127.0
  UPDATE_COMMAND    ""
  SOURCE_DIR        ${SB_SOURCE_DIR}/${_proj_name}
  CMAKE_ARGS
    -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
    -DCMAKE_INSTALL_PREFIX=${SB_INSTALL_DIR}
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DABSL_BUILD_TESTING=OFF
    -DABSL_USE_GOOGLETEST_HEAD=OFF
    -DABSL_PROPAGATE_CXX_STD=ON
    -DBUILD_SHARED_LIBS=ON
    -DCMAKE_CXX_STANDARD=17
    ${WIN32_CMAKE_ARGS}
    ${APPLE_CMAKE_ARGS}
  BINARY_DIR        ${_SB_BINARY_DIR}
  INSTALL_DIR       ${SB_INSTALL_DIR}
  LOG_DOWNLOAD      ON
  LOG_CONFIGURE     ON
  LOG_BUILD         ON
)
