FROM nvidia/cuda:12.9.1-devel-ubuntu24.04 AS builder

# Env variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONPATH="/code/SuperBuild/install/lib/python3.12/dist-packages:/code/SuperBuild/install/bin/opensfm" \
    LD_LIBRARY_PATH="/code/SuperBuild/install/lib:/usr/local/cudss/lib" \
    CUDSS_ROOT="/usr/local/cudss"

# Prepare directories
WORKDIR /code

# Copy everything
COPY . ./

# cuDSS for Ceres/COLMAP GPU bundle adjustment (sparse Schur solver)
RUN chmod +x docker/install-cudss.sh && bash docker/install-cudss.sh

# Run the build
RUN PORTABLE_INSTALL=YES GPU_INSTALL=YES bash configure.sh install

# Clean Superbuild
RUN bash configure.sh clean

### END Builder

### Use a second image for the final asset to reduce the number and
# size of the layers.
FROM nvidia/cuda:12.9.1-runtime-ubuntu24.04

# Env variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONPATH="/code/SuperBuild/install/lib/python3.12/dist-packages:/code/SuperBuild/install/lib/python3.12:/code/SuperBuild/install/bin/opensfm" \
    LD_LIBRARY_PATH="/code/SuperBuild/install/lib:/usr/local/cudss/lib" \
    CUDSS_ROOT="/usr/local/cudss" \
    PDAL_DRIVER_PATH="/code/SuperBuild/install/bin"

WORKDIR /code

# Copy everything we built from the builder (includes /usr/local/cudss + pip)
COPY --from=builder /code /code
COPY --from=builder /usr/local /usr/local

RUN apt-get update -y \
 && apt-get install -y ffmpeg libtbbmalloc2
# Install shared libraries that we depend on via APT, but *not*
# the -dev packages to save space!
# Also run a smoke test on ODX and OpenSfM
RUN bash configure.sh installruntimedeps \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && bash run.sh --help \
  && /code/SuperBuild/install/bin/colmap -h \
  && bash -c "eval $(python3 -m opendm.context) && python3 -c 'from opensfm import io, pymap'"

# Entry point
ENTRYPOINT ["python3", "/code/run.py"]
