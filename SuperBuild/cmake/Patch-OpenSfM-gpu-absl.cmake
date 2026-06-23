# Link pybundle against shared Abseil from SuperBuild (Ceres 2.3 / COLMAP 3.11).
# Appends CMake rules after pybundle is defined (robust vs string-replace).

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
  message(STATUS "OpenSfM: pybundle Abseil patch already applied")
  return()
endif()

if(NOT _content MATCHES "pybind11_add_module\\(pybundle")
  message(FATAL_ERROR "OpenSfM bundle/CMakeLists.txt layout changed; update Patch-OpenSfM-gpu-absl.cmake")
endif()

file(GLOB _absl_libs "${SB_INSTALL_DIR}/lib/libabsl_*.so")
list(SORT _absl_libs)
if(NOT _absl_libs)
  message(FATAL_ERROR "ODX GPU: no libabsl_*.so in ${SB_INSTALL_DIR}/lib — build External-Abseil first")
endif()

set(_absl_link "")
foreach(_lib IN LISTS _absl_libs)
  string(APPEND _absl_link " ${_lib}")
endforeach()

string(APPEND _content "
# ODX_GPU_ABSL: pybundle must link Ceres + shared Abseil (static bundle.a does not propagate deps).
target_link_libraries(pybundle PRIVATE Ceres::ceres \${CERES_LIBRARIES}${_absl_link})
")

file(WRITE "${OPENSFM_BUNDLE_CMAKE}" "${_content}")
message(STATUS "OpenSfM: patched pybundle with Ceres::ceres + ${SB_INSTALL_DIR}/lib/libabsl_*.so")
