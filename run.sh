#!/bin/bash

RUNPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -e $RUNPATH/venv ]; then
    source $RUNPATH/venv/bin/activate
fi
export CUDSS_ROOT="${CUDSS_ROOT:-/usr/local/cudss}"
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$RUNPATH/SuperBuild/install/lib:${CUDSS_ROOT}/lib
export DYLD_LIBRARY_PATH=$RUNPATH/SuperBuild/install/lib
python3 $RUNPATH/run.py "$@"

