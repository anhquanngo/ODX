# Ceres MINIGLOG=ON (CPU builds) does not provide glog FLAGS_logtostderr / FLAGS_v.
# GPU builds use Ceres with MINIGLOG=OFF; patch is a no-op when patterns are absent.

if(NOT DEFINED COLMAP_OPTION_MANAGER_CC)
  message(FATAL_ERROR "COLMAP_OPTION_MANAGER_CC is not set")
endif()

if(NOT EXISTS "${COLMAP_OPTION_MANAGER_CC}")
  message(FATAL_ERROR "COLMAP option_manager.cc not found: ${COLMAP_OPTION_MANAGER_CC}")
endif()

file(READ "${COLMAP_OPTION_MANAGER_CC}" _content)

set(_patched FALSE)

if(_content MATCHES "AddAndRegisterDefaultOption\\(\"log_to_stderr\", &FLAGS_logtostderr\\)")
  string(REPLACE
    "  AddAndRegisterDefaultOption(\"log_to_stderr\", &FLAGS_logtostderr);\n  AddAndRegisterDefaultOption(\"log_level\", &FLAGS_v);"
    "  // ODX: Ceres miniglog has no FLAGS_logtostderr/FLAGS_v; skip log CLI options."
    _content "${_content}")
  set(_patched TRUE)
endif()

if(_content MATCHES "FLAGS_logtostderr = true")
  string(REPLACE
    "  FLAGS_logtostderr = true;\n"
    "  // ODX: Ceres miniglog has no FLAGS_logtostderr.\n"
    _content "${_content}")
  set(_patched TRUE)
endif()

if(_patched)
  file(WRITE "${COLMAP_OPTION_MANAGER_CC}" "${_content}")
  message(STATUS "COLMAP: patched option_manager.cc for Ceres miniglog")
else()
  message(STATUS "COLMAP: option_manager.cc miniglog patch already applied or not needed")
endif()
