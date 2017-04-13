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

## Advanced Usage

When embedding a StructOfArrays in a larger, data structure, it can be useful
to automatically compute the SoA type corresponding to a regular arrays type.
This can be accomplished using the `similar` function:

```
struct Vectors
    x::similar(StructOfArrays, Vector{Complex{Float64}})
    y::similar(StructOfArrays, Vector{Complex{Float64}})
end
# equivalent in layout to
struct Vectors
    x_real::Vector{Float64}
    x_imag::Vector{Float64}
    y_real::Vector{Float64}
    y_imag::Vector{Float64}
end
```

Note that this feature also works with parameterized types. However, if
later a composite type is substituted for type type parameter, it will not
be unpacked into separate arrays:

```
struct Vector3D{T}
    x::T
    y::T
    z::T
end
struct Container{T}
    soa::similar(StructOfArrays, Vector{Vector3D{T}})
end
# Container{Float64} is equivalent to
struct ContainerFloat64
    soa_x::Vector{Float64}
    soa_y::Vector{Float64}
    soa_z::Vector{Float64}
end
# Container{Complex{Float64}} is equivalent to
struct ContainerFloat64
    soa_x::Vector{Complex{Float64}}
    soa_y::Vector{Complex{Float64}}
    soa_z::Vector{Complex{Float64}}
end
# Note that this is different from similar(StructOfArrays, Vector{Vector3D{Complex{Float64}}}), which would expand to
struct ContainerFloat64
    soa_x_real::Vector{Float64}
    soa_x_imag::Vector{Float64}
    soa_y_real::Vector{Float64}
    soa_y_imag::Vector{Float64}
    soa_y_real::Vector{Float64}
    soa_y_imag::Vector{Float64}
end
```

This behavior was chosen to accomodate julia's handling of parameterize element,
types. If future versions of julia expand these capabilities, the default behavior
may need to be revisited.

Lastly, note that it is possible to choose control the recursion explicitly, 
by providing a type (as the second type parameters) whose subtypes should be
considered leaves for the purpose of recursion. E.g.:
```
struct Bundle
    x::Complex{Float64}
    y::Complex{Int64}
    z::Rational{Int64}
end
# Consider
A = StructOfArrays{Bundle, Any}(2,2)
# Since all types are <: Any, no recusion will occur, and the SoaA is equivalent to
struct SoAAny
    x::Matrix{Complex{Float64}}
    y::Matrix{Complex{Int64}}    
    z::Matrix{Rational{Int64}}
end
# Next, let's say we want to have separate SoA for the complex values. Consider
B = StructOfArrays{Bundle, Complex}(2,2)
# which will be equivalent to
struct SoAComplex
    x_real::Matrix{Float64}
    x_imag::Matrix{Float64}
    y_real::Matrix{Int64}
    y_imag::Matrix{Int64}
    z::Matrix{Rational{Int64}}
end
# Lastly it is of course possible to specify a union:
C = StructOfArrays{Bundle, Union{Complex{Float64},Rational}}(2,2)
struct SoAUnion
    x_real::Matrix{Float64}
    x_imag::Matrix{Float64}
    y::Matrox{Complex{Int64}}
    z_num::Matrix{Int64}
    z_den::Matrix{Int64}
end
```


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
