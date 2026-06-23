# GPU OpenSfM: use Ceres CMake config (Ceres::ceres) like COLMAP; pybundle must
# link Ceres::ceres to pull shared Abseil from SuperBuild install.

if(NOT DEFINED OPENSFM_BUNDLE_CMAKE)
  message(FATAL_ERROR "OPENSFM_BUNDLE_CMAKE is not set")
endif()

if(NOT EXISTS "${OPENSFM_BUNDLE_CMAKE}")
  message(FATAL_ERROR "OpenSfM bundle CMakeLists not found: ${OPENSFM_BUNDLE_CMAKE}")
endif()

if(NOT DEFINED OPENSFM_SRC_CMAKE)
  get_filename_component(_bundle_dir "${OPENSFM_BUNDLE_CMAKE}" DIRECTORY)
  get_filename_component(_src_dir "${_bundle_dir}" DIRECTORY)
  set(OPENSFM_SRC_CMAKE "${_src_dir}/CMakeLists.txt")
endif()

if(NOT EXISTS "${OPENSFM_SRC_CMAKE}")
  message(FATAL_ERROR "OpenSfM src CMakeLists not found: ${OPENSFM_SRC_CMAKE}")
endif()

if(NOT DEFINED SB_INSTALL_DIR)
  message(FATAL_ERROR "SB_INSTALL_DIR is not set")
endif()

file(GLOB _absl_libs "${SB_INSTALL_DIR}/lib/libabsl_*.so")
if(NOT _absl_libs)
  message(FATAL_ERROR "ODX GPU: no libabsl_*.so in ${SB_INSTALL_DIR}/lib — build External-Abseil first")
endif()

# --- src/CMakeLists.txt: find_package(Ceres CONFIG) for Ceres::ceres target ---
file(READ "${OPENSFM_SRC_CMAKE}" _src_content)

if(_src_content MATCHES "ODX_CERES_CONFIG")
  message(STATUS "OpenSfM: Ceres CONFIG patch already applied")
else()
  if(NOT _src_content MATCHES "find_package\\(Ceres REQUIRED\\)")
    message(FATAL_ERROR "OpenSfM src/CMakeLists.txt layout changed; update Patch-OpenSfM-gpu-absl.cmake")
  endif()
  string(REPLACE
    "find_package(Ceres REQUIRED)"
    "find_package(Ceres CONFIG REQUIRED) # ODX_CERES_CONFIG"
    _src_content "${_src_content}")
  file(WRITE "${OPENSFM_SRC_CMAKE}" "${_src_content}")
  message(STATUS "OpenSfM: use find_package(Ceres CONFIG REQUIRED)")
endif()

# --- bundle/CMakeLists.txt: pybundle links Ceres::ceres; drop miniglog include ---
file(READ "${OPENSFM_BUNDLE_CMAKE}" _content)

if(_content MATCHES "ODX_GPU_ABSL")
  message(STATUS "OpenSfM: pybundle GPU Ceres link patch already applied")
else()
  if(NOT _content MATCHES "pybind11_add_module\\(pybundle")
    message(FATAL_ERROR "OpenSfM bundle/CMakeLists.txt layout changed; update Patch-OpenSfM-gpu-absl.cmake")
  endif()

  string(REPLACE
    "target_include_directories(bundle PRIVATE \${CMAKE_SOURCE_DIR} \${CERES_INCLUDE_DIR}/ceres/internal/miniglog)"
    "target_include_directories(bundle PRIVATE \${CMAKE_SOURCE_DIR}) # ODX_GPU_ABSL: Ceres CONFIG provides includes"
    _content "${_content}")

  string(APPEND _content "
# ODX_GPU_ABSL: static bundle.a does not propagate Ceres/Abseil to pybundle.so.
target_link_libraries(pybundle PRIVATE Ceres::ceres)
set_target_properties(pybundle PROPERTIES
  INSTALL_RPATH \"${SB_INSTALL_DIR}/lib\"
  BUILD_WITH_INSTALL_RPATH TRUE
)
")

  file(WRITE "${OPENSFM_BUNDLE_CMAKE}" "${_content}")
  message(STATUS "OpenSfM: patched pybundle to link Ceres::ceres (Abseil via SuperBuild install/lib)")
endif()
