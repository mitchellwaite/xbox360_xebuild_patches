#!/bin/bash
# Build and run the host tests: ./run.sh <64MB+spare big block image> [iterations] [seed]
set -e
cd "$(dirname "$0")"
gcc -O1 -g -Wall -Wextra -Wno-unused-parameter -Wno-clobbered -fsanitize=address,undefined -fno-omit-frame-pointer \
    -o test_bb ../bb_engine.c nandsim.c fs1888.c test_main.c
ASAN_OPTIONS=detect_leaks=0 ./test_bb "$@"
