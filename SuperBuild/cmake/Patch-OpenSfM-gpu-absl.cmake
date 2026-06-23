# GPU OpenSfM: pybundle must link Ceres::ceres (pulls shared Abseil from SuperBuild install).
# Linking every libabsl_*.so explicitly duplicates Ceres::ceres deps and breaks the link step.

if(NOT DEFINED OPENSFM_BUNDLE_CMAKE)
  message(FATAL_ERROR "OPENSFM_BUNDLE_CMAKE is not set")
endif()

if(NOT EXISTS "${OPENSFM_BUNDLE_CMAKE}")
  message(FATAL_ERROR "OpenSfM bundle CMakeLists not found: ${OPENSFM_BUNDLE_CMAKE}")
endif()

if(NOT DEFINED SB_INSTALL_DIR)
  message(FATAL_ERROR "SB_INSTALL_DIR is not set")
endif()

file(READ "${OPENSFM_BUNDLE_CMAKE}" _content)

if(_content MATCHES "ODX_GPU_ABSL")
  message(STATUS "OpenSfM: pybundle GPU Ceres link patch already applied")
  return()
endif()

if(NOT _content MATCHES "pybind11_add_module\\(pybundle")
  message(FATAL_ERROR "OpenSfM bundle/CMakeLists.txt layout changed; update Patch-OpenSfM-gpu-absl.cmake")
endif()

file(GLOB _absl_libs "${SB_INSTALL_DIR}/lib/libabsl_*.so")
if(NOT _absl_libs)
  message(FATAL_ERROR "ODX GPU: no libabsl_*.so in ${SB_INSTALL_DIR}/lib — build External-Abseil first")
endif()

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
