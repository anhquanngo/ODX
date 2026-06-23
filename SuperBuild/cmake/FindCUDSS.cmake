# Locate NVIDIA cuDSS for Ceres USE_CUDA sparse solvers (Ubuntu / manual install).
# Sets cudss_DIR before find_package(cudss CONFIG) in External-Ceres.cmake.

if(cudss_FOUND)
  return()
endif()

if(DEFINED ENV{CUDSS_ROOT} AND NOT cudss_DIR)
  set(_cudss_root "$ENV{CUDSS_ROOT}")
  if(EXISTS "${_cudss_root}/lib/cmake/cudss")
    set(cudss_DIR "${_cudss_root}/lib/cmake/cudss" CACHE PATH "cuDSS CMake config directory")
  endif()
endif()

if(NOT cudss_DIR AND EXISTS "/usr/local/cudss/lib/cmake/cudss")
  set(cudss_DIR "/usr/local/cudss/lib/cmake/cudss" CACHE PATH "cuDSS CMake config directory")
endif()

if(NOT cudss_DIR)
  file(GLOB _cudss_cfg
    "/usr/lib/*/libcudss/*/cmake/cudss/cudss-config.cmake"
    "/usr/lib/*/libcudss/*/cmake/cudss/cudssConfig.cmake"
    "/usr/local/cudss/lib/cmake/cudss/cudss-config.cmake"
    "/usr/local/cudss/lib/cmake/cudss/cudssConfig.cmake"
  )
  if(_cudss_cfg)
    list(GET _cudss_cfg 0 _cudss_first)
    get_filename_component(cudss_DIR "${_cudss_first}" DIRECTORY)
    set(cudss_DIR "${cudss_DIR}" CACHE PATH "cuDSS CMake config directory")
  endif()
endif()

if(NOT cudss_INCLUDE_DIR)
  file(GLOB _cudss_inc_dirs "/usr/include/libcudss/*" "/usr/local/cudss/include/*")
  foreach(_inc IN LISTS _cudss_inc_dirs)
    if(EXISTS "${_inc}/cudss.h")
      set(cudss_INCLUDE_DIR "${_inc}" CACHE PATH "cuDSS include directory")
      break()
    endif()
  endforeach()
endif()

find_package(cudss CONFIG QUIET)
if(cudss_FOUND)
  message(STATUS "Found cuDSS ${cudss_VERSION} (GPU sparse BA for Ceres/COLMAP)")
else()
  message(WARNING "cuDSS not found; Ceres/COLMAP GPU sparse BA will fall back to CPU")
endif()

unset(_cudss_cfg)
unset(_cudss_first)
unset(_cudss_root)
unset(_cudss_inc_dirs)
unset(_inc)
