# zig-lambda-runtime

An AWS lambda custom runtime built in Zig, suitable for consumption by Zig and C projects.
Experimental, but works -- the larger question is probably not whether you should use this runtime,
but why you would want to write AWS lambda functions in Zig or C (other than for fun, in which case,
by all means use this runtime if you want).

## Installation

Minimum required zig version: 0.14.0

Two usages are currently supported:

1. Simply copy `./src/runtime.zig` into your project. This file is itself a standalone library and
   can be included in any zig project on its own. It depends only on the zig standard library.
2. After building the project via `zig build`, copy the provided header files in the `include`
   directory, and the static library from `./zig-out/lib/liblambda.a`, to whatever location you
   desire, and configure your (zig or C) compiler to link and include them. This is the recommended
   usage for C projects.

Note that the experimental zig package manager is not currently supported, as I have no interest in
hosting, distributing and validating tarballs of a single-file library.

## Usage

Please see `./src/example.zig` for an example of a lambda function built in Zig with this runtime.
Please see `./src/example.c` for an example of a C lambda built with this runtime.

## LICENSE

MIT
