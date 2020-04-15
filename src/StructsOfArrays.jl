module StructsOfArrays

export StructOfArrays
export replace_storage

using Base.Broadcast
import Base.Broadcast: BroadcastStyle, Broadcasted, AbstractArrayStyle

using Adapt
using LinearAlgebra

"""
    StructOfArrays{T, N, AT, U} <: AbstractArray{T,N}

Transparent Struct of Arrays transformation.
Given an array like `Array{ComplexF64, 2}`, we want to represent it as:

```
struct ComplexArray{N}
    re::Array{Float64}
    im::Array{Float64}
end

getindex(A::ComplexArray, i) = ComplexF64(A.re[i], A.im[i])
```

Since the memory-access patterns of `ComplexArray` are much more SIMD friendly than
`Array{ComplexF64}`. This version of `StructOfArrays` also has a notion of underlying
storage and works both on CPU arrays and CuArrays. In most cases single field access of
the struct should be fast as well since Julia and LLVM both do DCE.
"""
struct StructOfArrays{T,N, AT<:AbstractArray{T, N},U<:Tuple} <: AbstractArray{T,N}
    arrays::U
end

# Storage types of StructOfArrays need to implement this
_type_with_eltype(::Type{<:Array}, T, N) = Array{T, N}
_type(::Type{<:Array}) = Array

function replace_storage(f, x::StructOfArrays{T, N}) where {T, N}
    arrays = map(f, x.arrays)
    TT = typeof(arrays)
    AT = _type_with_eltype(eltype(arrays), T, N)
    StructOfArrays{T, N, AT, TT}(arrays)
end

Adapt.adapt_structure(to, x::StructOfArrays{T, N}) where {T, N} = replace_storage(y -> adapt(to, y), x)

function gather_eltypes(T, visited = Set{Type}())
    (!isconcretetype(T) || T.mutable) && throw(ArgumentError("can only create an StructOfArrays of leaf type immutables"))
    if isempty(T.types)
        return Type[T]
    end
    types = Type[]
    push!(visited, T)
    for S in T.types
        sizeof(S) == 0 && continue
        (S in visited) && throw(ArgumentError("Recursive types are not allowed for SoA conversion"))
        if isempty(S.types)
            push!(types, S)
        else
            append!(types, gather_eltypes(S, copy(visited)))
        end
    end
    types
end

@generated function StructOfArrays(::Type{T}, ::Type{ArrayT}, dims::Integer...) where {T, ArrayT<:AbstractArray}
    N         = length(dims)
    pArrayT   = _type_with_eltype(ArrayT, T, N)
    types     = gather_eltypes(T)
    arrtypes  = map(t->_type_with_eltype(ArrayT, t, N), types)
    arrtuple  = Tuple{arrtypes...}

    :(StructOfArrays{T,$N,$(pArrayT),$arrtuple}(($([:($(arrtypes[i])(undef,dims)) for i = 1:length(types)]...),)))
end
StructOfArrays(T::Type, AT::Type, dims::Tuple{Vararg{Integer}}) = StructOfArrays(T, AT, dims...)

Base.size(A::StructOfArrays) = size(@inbounds(A.arrays[1]))
Base.size(A::StructOfArrays, i) = size(@inbounds(A.arrays[1]), i)

Base.show(io::IO, a::StructOfArrays{T,N,A}) where {T,N,A} = print(io, "$(length(a))-element SoA{$T,$N,$A}")

Base.print_array(::IO, ::StructOfArrays) = nothing

function generate_getindex(T, getindex, arraynum)
    members = Expr[]
    for S in T.types
        if sizeof(S) == 0
            if S <: Tuple
                exprs2 = Expr[]
                for S2 in S.parameters
                    push!(exprs2, :($(S2)()))
                end
                push!(members, Expr(:tuple, exprs2))
            else
                push!(members, :($(S)()))
            end
        elseif isempty(S.types)
            push!(members, :($(getindex)(A.arrays[$arraynum], i...)))
            arraynum += 1
        else
            member, arraynum = generate_getindex(S, getindex, arraynum)
            push!(members, member)
        end
    end
    Expr(:new, T, members...), arraynum
end

@generated function Base.getindex(A::StructOfArrays{T}, i::Integer...) where T
    exprs = Any[Expr(:meta, :inline), Expr(:meta, :propagate_inbounds)]
    if isempty(T.types)
        push!(exprs, :(return A.arrays[1][i...]))
    else
        strct, _ = generate_getindex(T, Base.getindex, 1)
        push!(exprs, strct)
    end
    quote
        $(exprs...)
    end
end

function generate_setindex(T, x, arraynum)
    s = gensym()
    exprs = Expr[:($s = $x)]
    for (el,S) in enumerate(T.types)
        if sizeof(S) == 0
            continue
        end
        if isempty(S.types)
            push!(exprs, :(A.arrays[$arraynum][i...] = getfield($s, $el)))
            arraynum += 1
        else
            nexprs, arraynum = generate_setindex(S, :(getfield($s, $el)), arraynum)
            append!(exprs, nexprs)
        end
    end
    exprs, arraynum
end

@generated function Base.setindex!(A::StructOfArrays{T}, x, i::Integer...) where {T}
    exprs = Any[Expr(:meta, :inline), Expr(:meta, :propagate_inbounds)]
    push!(exprs, :(v = convert(T, x)))
    if isempty(T.types)
        push!(exprs, :(A.arrays[1][i...] = v))
    else
        append!(exprs, generate_setindex(T, :v, 1)[1])
    end
    push!(exprs, :(return x))
    quote
        $(exprs...)
    end
end

Base.IndexStyle(::Type{<:StructOfArrays{T,N,A}}) where {T,N,A<:AbstractArray} =  Base.IndexStyle(A)
BroadcastStyle(::Type{<:StructOfArrays{T,N,A}}) where {T,N,A<:AbstractArray} = Broadcast.ArrayStyle{StructOfArrays{T,N,A}}()

function Base.similar(A::StructOfArrays{T1,N,AT}, ::Type{T}, dims::Dims) where {T1,N,AT,T}
    StructOfArrays(T, AT, dims)
end

function Base.similar(bc::Broadcasted{Broadcast.ArrayStyle{StructOfArrays{T1,N,AT}}}, ::Type{T}) where {T1,N,AT,T}
    StructOfArrays(T, AT, Base.to_shape(axes(bc)))
end

function Base.convert(::Type{<:StructOfArrays{T,N,AT}}, A::StructOfArrays{T,N}) where {T,N,AT<:AbstractArray{T,N}}
    if AT <: StructOfArrays
        error("Can't embed a SoA array in a SoA array")
    end
    arrays = map(a->convert(_type(AT), a), A.arrays)
    tt = typeof(arrays)
    StructOfArrays{T, N, AT, tt}(arrays)
end

function Base.convert(::Type{<:StructOfArrays{T,N,AT}}, A::StructOfArrays{S,N,BT}) where {T,N,AT,S,BT}
    BT != AT && AT<:CuArray && error("Can't convert from $BT to $AT with different eltypes")
    copyto!(StructOfArrays(T, _type_with_eltype(AT, T, N), size(A)), A)
end

function Base.convert(::Type{<:StructOfArrays{T,N}}, A::AbstractArray) where {T,N}
    @assert !(A isa StructOfArrays)
    copyto!(StructOfArrays(T, _type_with_eltype(typeof(A), T, N), size(A)), A)
end

Base.convert(::Type{<:StructOfArrays{T}}, A::AbstractArray{S,N}) where {T,S,N} =
    convert(StructOfArrays{T,N}, A)

Base.convert(::Type{<:StructOfArrays}, A::AbstractArray{T,N}) where {T,N} =
    convert(StructOfArrays{T,N}, A)

function Base.one(x::StructOfArrays{T}) where {T}
    # FIXME: probably not the best way, ie. don't use Base._one
    convert(StructOfArrays, Base._one(one(T), x))
end

function Base.Array{T,N}(src::StructOfArrays{T,N}) where {T,N}
    A = convert(StructOfArrays{T,N,Array{T,N}}, src)
    dst = Array{T,N}(uninitialized, size(src))
    copyto!(dst, A)
    return dst
end
Array(src::StructOfArrays{T,N}) where {T,N} = Array{T,N}(src)

include("storage/gpuarrays.jl")
using CUDAapi
if has_cuda_gpu()
    include("storage/cuda.jl")
end

end
