#!/usr/bin/env bash

set -eoux pipefail

LAMBDA_TARGET_AARCH64=1 zig build --release=small

cd ./zig-out/bin

zip lambda.zip bootstrap

PAGER="" aws lambda update-function-code --function-name=$1 --zip-file=fileb://lambda.zip
