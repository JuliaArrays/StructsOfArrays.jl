# StructsOfArrays

A traditional Julia array of immutable objects is an array of structures. Fields
of a given object are stored adjacent in memory. However, this often inhibits
SIMD optimizations. StructsOfArrays implements the classic structure of arrays
optimization. The contents of a given field for all objects is stored linearly
in memory, and different fields are stored in different arrays. This permits
SIMD optimizations in more cases and can also save a bit of memory if the object
contains padding. It is especially useful for arrays of complex numbers.

## Usage

You can construct a `StructOfArrays` directly with:

```julia
using StructsOfArrays
A = StructOfArrays(ComplexF64, Array, 10, 10)
```

or by converting an `AbstractArray`:

```julia
A = convert(StructOfArrays, rand(ComplexF64, 10, 10))
```

A `StructOfArrays` can have different storage arrays.  You can construct a
`CuArray`-based `StructOfArrays` directly with:

```julia
using CuArrays
A = StructOfArrays(ComplexF64, CuArray, 10, 10)
```

or by converting an existing `StructOfArrays` using `replace_storage`:

```julia
A = replace_storage(CuArray, convert(StructOfArrays, rand(ComplexF64, 10, 10)))
```

This array can be used either in a kernel:

```julia
using CUDAnative
function kernel!(A)
    i = (blockIdx().x-1)*blockDim().x + threadIdx().x
    if i <= length(A)
        A[i] += A[i]
    end
    return nothing
end
threads = 256
blocks = cld(length(A), threads)
@cuda threads=threads blocks=blocks kernel!(A)
```

or via broadcasting:

```julia
A .+= A
```

Assignment and indexing works as with other `AbstractArray` types. Indexing a
`StructOfArrays{T}` yields an object of type `T`, and you can assign objects of
type `T` to a given index.
