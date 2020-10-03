#!/bin/bash
set -eo pipefail

clear
rm -f examples/bouncy/game.lola.lm
lola compile examples/bouncy/game.lola
lola dump -O examples/bouncy/game.lola.lm
echo "compile…"
zig-git build
echo "run"
./zig-cache/bin/zgs.pc

