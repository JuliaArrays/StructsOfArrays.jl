module StructsOfArrays
export StructOfArrays

immutable StructOfArrays{T,N,U<:Tuple} <: AbstractArray{T,N}
    arrays::U
end

@generated function StructOfArrays{T}(::Type{T}, dims::Integer...)
    (!isleaftype(T) || T.mutable) && return :(throw(ArgumentError("can only create an StructOfArrays of leaf type immutables")))
    isempty(T.types) && return :(throw(ArgumentError("cannot create an StructOfArrays of an empty or bitstype")))
    N = length(dims)
    arrtuple = Tuple{[Array{T.types[i],N} for i = 1:length(T.types)]...}
    :(StructOfArrays{T,$N,$arrtuple}(($([:(Array($(T.types[i]), dims)) for i = 1:length(T.types)]...),)))
end
StructOfArrays(T::Type, dims::Tuple{Vararg{Integer}}) = StructOfArrays(T, dims...)

Base.linearindexing{T<:StructOfArrays}(::Type{T}) = Base.LinearFast()

@generated function Base.similar{T}(A::StructOfArrays, ::Type{T}, dims::Dims)
    if isbits(T) && length(T.types) > 1
        :(StructOfArrays(T, dims))
    else
        :(Array(T, dims))
    end
end

Base.convert{T,S,N}(::Type{StructOfArrays{T,N}}, A::AbstractArray{S,N}) =
    copy!(StructOfArrays(T, size(A)), A)
Base.convert{T,S,N}(::Type{StructOfArrays{T}}, A::AbstractArray{S,N}) =
    convert(StructOfArrays{T,N}, A)
Base.convert{T,N}(::Type{StructOfArrays}, A::AbstractArray{T,N}) =
    convert(StructOfArrays{T,N}, A)

Base.size(A::StructOfArrays) = size(A.arrays[1])
Base.size(A::StructOfArrays, d) = size(A.arrays[1], d)

@generated function Base.getindex{T}(A::StructOfArrays{T}, i::Integer...)
    Expr(:block, Expr(:meta, :inline),
         Expr(:new, T, [:(A.arrays[$j][i...]) for j = 1:length(T.types)]...))
end
@generated function Base.setindex!{T}(A::StructOfArrays{T}, x, i::Integer...)
    quote
        $(Expr(:meta, :inline))
        v = convert(T, x)
        $([:(A.arrays[$j][i...] = getfield(v, $j)) for j = 1:length(T.types)]...)
        x
    end
end
end # module
