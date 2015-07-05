#!/usr/bin/env bash

# Script parameters:
# $1 is the compiled js, relative to "bin"
# $2 (optional) is a trace/console success message to look for.

# Copy html file to bin and replace the javascript reference
cp src-phantomjs/phantomjs.html bin/phantomjs.html
sed -i "s/\[PHANTOMJS\]/$1/g" bin/phantomjs.html

# Run the html file, looking for the success message
phantomjs src-phantomjs/phantomjs.js "$2"
