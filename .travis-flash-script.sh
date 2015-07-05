#!/usr/bin/env bash

# The flash player has some issues with unexplained crashes,
# but if it runs about 8 times, it should succeed one of those.
for i in 1 2 3 4 5 6 7 8
do
	xvfb-run ~/flashplayerdebugger "$1"
	test $? -eq 0 && exit 0
done
exit 1
