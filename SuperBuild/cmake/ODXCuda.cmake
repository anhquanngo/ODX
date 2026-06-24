# Resolve nvcc and CUDA stub paths for:
# - NVIDIA installer layout (/usr/local/cuda)
# - Ubuntu/Debian nvidia-cuda-toolkit (/usr/bin/nvcc, stubs under /usr/lib/...)

set(ODX_NVCC "")
foreach(_cand IN ITEMS
    "/usr/local/cuda/bin/nvcc"
    "/usr/bin/nvcc"
    "/usr/lib/nvidia-cuda-toolkit/bin/nvcc")
    if(EXISTS "${_cand}")
        set(ODX_NVCC "${_cand}")
        break()
    endif()
endforeach()

if(NOT ODX_NVCC)
    find_program(ODX_NVCC nvcc)
endif()

set(ODX_CUDA_STUB_DIR "")
foreach(_stub IN ITEMS
    "/usr/local/cuda/lib64/stubs"
    "/usr/lib/x86_64-linux-gnu/stubs")
    if(EXISTS "${_stub}/libcuda.so")
        set(ODX_CUDA_STUB_DIR "${_stub}")
        break()
    endif()
endforeach()

if(ODX_NVCC)
    message(STATUS "ODX CUDA: nvcc at ${ODX_NVCC}")
else()
    message(STATUS "ODX CUDA: nvcc not found")
endif()

if(ODX_CUDA_STUB_DIR)
    message(STATUS "ODX CUDA: stub dir ${ODX_CUDA_STUB_DIR}")
endif()
