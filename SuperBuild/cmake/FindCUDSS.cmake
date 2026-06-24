# Locate NVIDIA cuDSS for Ceres USE_CUDA sparse solvers (Ubuntu / manual install).
# Sets cudss_DIR before find_package(cudss CONFIG) in External-Ceres.cmake.
#
# NVIDIA redist archives install CMake config under either:
#   ${root}/lib/cmake/cudss
#   ${root}/lib/<cuda-major>/cmake/cudss   (e.g. lib/12/cmake/cudss)

if(cudss_FOUND)
  return()
endif()

macro(_odx_set_cudss_dir_from_config _cfg)
  get_filename_component(_odx_cudss_dir "${_cfg}" DIRECTORY)
  set(cudss_DIR "${_odx_cudss_dir}" CACHE PATH "cuDSS CMake config directory")
endmacro()

if(DEFINED ENV{CUDSS_ROOT} AND NOT cudss_DIR)
  set(_cudss_root "$ENV{CUDSS_ROOT}")
  if(EXISTS "${_cudss_root}/lib/cmake/cudss")
    set(cudss_DIR "${_cudss_root}/lib/cmake/cudss" CACHE PATH "cuDSS CMake config directory")
  else()
    file(GLOB _cudss_cfg
      "${_cudss_root}/lib/*/cmake/cudss/cudss-config.cmake"
      "${_cudss_root}/lib/*/cmake/cudss/cudssConfig.cmake"
    )
    if(_cudss_cfg)
      list(GET _cudss_cfg 0 _cudss_first)
      _odx_set_cudss_dir_from_config("${_cudss_first}")
    endif()
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
    "/usr/local/cudss/lib/*/cmake/cudss/cudss-config.cmake"
    "/usr/local/cudss/lib/*/cmake/cudss/cudssConfig.cmake"
  )
  if(DEFINED ENV{CUDSS_ROOT})
    file(GLOB _cudss_cfg_env
      "$ENV{CUDSS_ROOT}/lib/cmake/cudss/cudss-config.cmake"
      "$ENV{CUDSS_ROOT}/lib/cmake/cudss/cudssConfig.cmake"
      "$ENV{CUDSS_ROOT}/lib/*/cmake/cudss/cudss-config.cmake"
      "$ENV{CUDSS_ROOT}/lib/*/cmake/cudss/cudssConfig.cmake"
    )
    list(APPEND _cudss_cfg ${_cudss_cfg_env})
  endif()
  if(_cudss_cfg)
    list(GET _cudss_cfg 0 _cudss_first)
    _odx_set_cudss_dir_from_config("${_cudss_first}")
  endif()
endif()

if(NOT cudss_INCLUDE_DIR)
  foreach(_cudss_inc_root IN ITEMS "$ENV{CUDSS_ROOT}" "/usr/local/cudss")
    if(_cudss_inc_root AND EXISTS "${_cudss_inc_root}/include/cudss.h")
      set(cudss_INCLUDE_DIR "${_cudss_inc_root}/include" CACHE PATH "cuDSS include directory")
      break()
    endif()
  endforeach()
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
  message(STATUS "Found cuDSS ${cudss_VERSION} at ${cudss_DIR} (GPU sparse BA for Ceres/COLMAP)")
else()
  message(WARNING "cuDSS not found; Ceres/COLMAP GPU sparse BA will fall back to CPU")
endif()

unset(_odx_cudss_dir)
unset(_cudss_cfg)
unset(_cudss_cfg_env)
unset(_cudss_first)
unset(_cudss_root)
unset(_cudss_inc_root)
unset(_cudss_inc_dirs)
unset(_inc)
