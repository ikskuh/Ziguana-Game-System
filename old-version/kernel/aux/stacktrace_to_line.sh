#!/bin/bash
while IFS= read -r line
do
	printf '%s\n' "$line"
	if echo $line | grep -q 'Stack:'; then
		addr2line -e zig-cache/bin/kernel $(echo $line | cut -d ':' -f 2)
	fi
done < "${1:-/dev/stdin}"
