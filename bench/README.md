# 2JZ Benchmark

### Inspiration
As mentioned in the source, the inspiration for the benchmarking setup here was
taken from this benchmarking comparison regarding the Rust ECS libraries specs
and legion: [article](https://csherratt.github.io/blog/posts/specs-and-legion/).
It isn't a one to one comparison, as those libraries are currently a bit more
featureful than this one, but it provides an excellent point of comparison.

### Running the Benchmark
`zig build bench -Drelease-fast=true`
