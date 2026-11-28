#!/bin/bash
# Run the host tests with several seeds: ./soak.sh <image> [iterations] [seeds...]
set -e
cd "$(dirname "$0")"
img="$1"
iters="${2:-600}"
shift 2 || true
seeds=("$@")
[ ${#seeds[@]} -eq 0 ] && seeds=(1 2 3 6502 1888 17559 31337 424242)
gcc -O1 -g -Wall -Wextra -Wno-unused-parameter -Wno-clobbered -fsanitize=address,undefined -fno-omit-frame-pointer \
    -o test_bb ../bb_engine.c nandsim.c fs1888.c test_main.c
for s in "${seeds[@]}"; do
    printf 'seed %-8s ' "$s"
    ASAN_OPTIONS=detect_leaks=0 ./test_bb "$img" "$iters" "$s" > "soak_$s.log" 2>&1 || { echo FAILED; tail -5 "soak_$s.log"; exit 1; }
    grep -E '^(random|power cuts|fill:|full volume)' "soak_$s.log" | tr '\n' ' '
    echo
done
echo "soak: all seeds passed"
