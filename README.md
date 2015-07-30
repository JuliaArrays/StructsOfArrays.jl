# StructsOfArrays

[![Build Status](https://travis-ci.org/simonster/StructsOfArrays.jl.svg?branch=master)](https://travis-ci.org/simonster/StructsOfArrays.jl)
[![codecov.io](http://codecov.io/github/simonster/StructsOfArrays.jl/coverage.svg?branch=master)](http://codecov.io/github/simonster/StructsOfArrays.jl?branch=master)

A traditional Julia array of immutable objects is an array of structures. Fields
of a given object are stored adjacent in memory. However, this often inhibits
SIMD optimizations. StructsOfArrays implements the classic structure of arrays
optimization. The contents of a given field for all objects is stored linearly
in memory, and different fields are stored in different arrays. This permits
SIMD optimizations in more cases and can also save a bit of memory if the object
contains padding. It is especially useful for arrays of complex numbers.

## Usage

You can construct a StructOfArrays directly:

```julia
using StructsOfArrays
A = StructOfArrays(Complex128, 10, 10)
```

or by converting an AbstractArray:

```julia
A = convert(StructOfArrays, complex(randn(10), randn(10)))
```

Beyond that, there's not much to say. Assignment and indexing works as with
other AbstractArray types. Indexing a `StructOfArrays{T}` yields an object of
type `T`, and you can assign objects of type `T` to a given index. The "magic"
is in the optimizations that the alternative memory layout allows LLVM to
perform.

While you can create a StructOfArrays of non-`isbits` immutables, this is
probably slower than an ordinary array, since a new object must be heap
allocated every time the StructOfArrays is indexed. In practice, StructsOfArrays
works best with `isbits` immutables such as `Complex{T}`.

## Benchmark

```julia
using StructsOfArrays
regular = complex(randn(1000000), randn(1000000))
soa = convert(StructOfArrays, regular)

function f(x, a)
    s = zero(eltype(x))
    @simd for i in 1:length(x)
        @inbounds s += x[i] * a
    end
    s
end

using Benchmarks
@benchmark f(regular, 0.5+0.5im)
@benchmark f(soa, 0.5+0.5im)
```

The time for `f(regular, 0.5+0.5im)` is:

```
Average elapsed time: 1.244 ms
  95% CI for average: [1.183 ms, 1.305 ms]
Minimum elapsed time: 1.177 ms
```

and for `f(soa, 0.5+0.5im)`:

```
Average elapsed time: 832.198 μs
  95% CI for average: [726.349 μs, 938.048 μs]
Minimum elapsed time: 713.730 μs
```

In this case, StructsOfArrays are about 1.5x faster than ordinary arrays.
Inspection of generated code demonstrates that `f(soa, a)` uses SIMD
instructions, while `f(regular, a)` does not.
