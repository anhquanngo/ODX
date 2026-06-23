# Link pybundle against Abseil shared libs from SuperBuild (Ceres 2.3 / COLMAP 3.11).
# Without this, pybundle.so can miss absl::lts_20250127 symbols at runtime.

if(NOT DEFINED OPENSFM_BUNDLE_CMAKE)
  message(FATAL_ERROR "OPENSFM_BUNDLE_CMAKE is not set")
endif()

if(NOT EXISTS "${OPENSFM_BUNDLE_CMAKE}")
  message(FATAL_ERROR "OpenSfM bundle CMakeLists not found: ${OPENSFM_BUNDLE_CMAKE}")
endif()

file(READ "${OPENSFM_BUNDLE_CMAKE}" _content)

if(_content MATCHES "ODX_GPU_ABSL")
  message(STATUS "OpenSfM: pybundle Abseil patch already applied")
  return()
endif()

set(_marker
"set_target_properties(pybundle PROPERTIES
 LIBRARY_OUTPUT_DIRECTORY \"\${opensfm_SOURCE_DIR}/..\"
)")

set(_replacement
"set_target_properties(pybundle PROPERTIES
 LIBRARY_OUTPUT_DIRECTORY \"\${opensfm_SOURCE_DIR}/..\"
)
# ODX_GPU_ABSL: Ceres 2.3+ / COLMAP 3.11 expose Abseil in headers used by pybundle.
file(GLOB ODX_ABSL_LIBS \"\${CERES_ROOT_DIR}/lib/libabsl_*.so\")
if(ODX_ABSL_LIBS)
  target_link_libraries(pybundle PRIVATE \${ODX_ABSL_LIBS})
endif()")

if(NOT _content MATCHES "pybind11_add_module\\(pybundle")
  message(FATAL_ERROR "OpenSfM bundle/CMakeLists.txt layout changed; update Patch-OpenSfM-gpu-absl.cmake")
endif()

string(REPLACE "${_marker}" "${_replacement}" _content "${_content}")
file(WRITE "${OPENSFM_BUNDLE_CMAKE}" "${_content}")
message(STATUS "OpenSfM: patched pybundle to link Abseil from SuperBuild install")
