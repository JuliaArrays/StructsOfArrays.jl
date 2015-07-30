# SoArrays

[![Build Status](https://travis-ci.org/simonster/SoArrays.jl.svg?branch=master)](https://travis-ci.org/simonster/SoArrays.jl)
[![codecov.io](http://codecov.io/github/simonster/SoArrays.jl/coverage.svg?branch=master)](http://codecov.io/github/simonster/SoArrays.jl?branch=master)

A traditional Julia array of immutable objects is an array of structures. Fields
of a given object are stored adjacent in memory. However, this often inhibits
SIMD optimizations. SoArrays implements the classic structure of arrays
optimization. The contents of a given field for all objects is stored linearly
in memory, and different fields are stored in different arrays. This permits
SIMD optimizations in more cases and can also save a bit of memory if the object
contains padding.

## Benchmark

```julia
using SoArrays
regular = complex(randn(1000000), randn(1000000))
soa = convert(SoArray, regular)

using Benchmarks
@benchmark sum(regular)
@benchmark sum(soa)
```

The time for `sum(regular)` is:

```
Average elapsed time: 1.018 ms
  95% CI for average: [887.090 μs, 1.149 ms]
```

and for `sum(soa)`:

```
Average elapsed time: 754.942 μs
  95% CI for average: [688.003 μs, 821.880 μs]
```

Inspection of generated code demonstrates that `sum(soa)` uses SIMD
instructions, while `sum(regular)` does not.
