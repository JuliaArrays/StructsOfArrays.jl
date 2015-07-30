module SoArrays
export SoArray

immutable SoArray{T,N,U<:Tuple} <: AbstractArray{T,N}
    arrays::U
end

@generated function SoArray{T}(::Type{T}, dims::Integer...)
    !isleaftype(T) || T.mutable && return :(throw(ArgumentError("can only create an SoArray of leaf type immutables")))
    isempty(T.types) && return :(throw(ArgumentError("cannot create an SoArray of an empty type")))
    N = length(dims)
    arrtuple = Tuple{[Array{T.types[i],N} for i = 1:length(T.types)]...}
    :(SoArray{T,$N,$arrtuple}(($([:(Array($(T.types[i]), dims)) for i = 1:length(T.types)]...),)))
end
SoArray(T::Type, dims::Tuple{Vararg{Integer}}) = SoArray(T, dims...)

Base.size(A::SoArray) = size(A.arrays[1])
@generated function Base.getindex{T}(A::SoArray{T}, i::Integer)
    Expr(:block, Expr(:meta, :inline),
         Expr(:new, T, [:(A.arrays[$j][i]) for j = 1:length(T.types)]...))
end
@generated function Base.setindex!{T}(A::SoArray{T}, x, i::Integer)
    quote
        $(Expr(:meta, :inline))
        v = convert(T, x)
        $([:(A.arrays[$j][i] = getfield(v, $j)) for j = 1:length(T.types)]...)
        x
    end
end
end # module
