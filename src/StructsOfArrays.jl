module StructsOfArrays

using Compat

export StructOfArrays

immutable StructOfArrays{T,N,U<:Tuple} <: AbstractArray{T,N}
    arrays::U
end

function gather_eltypes(T, visited = Set{Type}())
    (!isleaftype(T) || T.mutable) && throw(ArgumentError("can only create an StructOfArrays of leaf type immutables"))
    isempty(T.types) && throw(ArgumentError("cannot create an StructOfArrays of an empty or bitstype"))
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

@generated function StructOfArrays{T}(::Type{T}, dims::Integer...)
    N = length(dims)
    types = gather_eltypes(T)
    arrtuple = Tuple{[Array{S,N} for S in types]...}
    :(StructOfArrays{T,$N,$arrtuple}(($([:(Array{$(S)}(dims)) for S in types]...),)))
end
StructOfArrays(T::Type, dims::Tuple{Vararg{Integer}}) = StructOfArrays(T, dims...)

@compat Base.IndexStyle{T<:StructOfArrays}(::Type{T}) = IndexLinear()

@generated function Base.similar{T}(A::StructOfArrays, ::Type{T}, dims::Dims)
    if isbits(T) && length(T.types) > 1
        :(StructOfArrays(T, dims))
    else
        :(Array{T}(dims))
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

function generate_getindex(T, arraynum)
    members = Expr[]
    for S in T.types
        sizeof(S) == 0 && push!(members, :($(S())))
        if isempty(S.types)
            push!(members, :(A.arrays[$arraynum][i...]))
            arraynum += 1
        else
            member, arraynum = generate_getindex(S, arraynum)
            push!(members, member)
        end
    end
    Expr(:new, T, members...), arraynum
end

@generated function Base.getindex{T}(A::StructOfArrays{T}, i::Integer...)
    strct, _ = generate_getindex(T, 1)
    Expr(:block, Expr(:meta, :inline), strct)
end

function generate_setindex(T, x, arraynum)
    s = gensym()
    exprs = Expr[:($s = $x)]
    for (el,S) in enumerate(T.types)
        sizeof(S) == 0 && push!(members, :($(S())))
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

@generated function Base.setindex!{T}(A::StructOfArrays{T}, x, i::Integer...)
    exprs = Expr(:block, generate_setindex(T, :x, 1)[1]...)
    quote
        $(Expr(:meta, :inline))
        v = convert(T, x)
        $exprs
        x
    end
end
end # module
