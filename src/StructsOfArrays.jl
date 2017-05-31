__precompile__()
module StructsOfArrays

using Compat

export StructOfArrays

immutable StructOfArrays{T,Leaves,N,U<:Tuple} <: AbstractArray{T,N}
    arrays::U
    StructOfArrays{T,Leaves,N,U}(arrays::U) where {T,Leaves,N,U} = new{T,Leaves,N,U}(arrays)
end

function gather_eltypes(T, Leaves=Union{}, visited = Set{Type}(); allow_typevar=false)
    @assert !isa(T, UnionAll)
    T.mutable && throw(ArgumentError("can not create StructOfArray for a mutable type"))
    isempty(T.types) && throw(ArgumentError("cannot create an StructOfArrays of an empty or bitstype"))
    types = Any[]
    typevars = TypeVar[]
    push!(visited, T)
    for S in T.types
        (S in visited) && throw(ArgumentError("Recursive types are not allowed for SoA conversion"))
        if isa(S, TypeVar)
            !allow_typevar && throw(ArgumentError("TypeVars are not allowed when constructing an SoA array"))
            push!(typevars, S)
        elseif isa(S, UnionAll)
            throw(ArgumentError("Interior UnionAlls are not allowed"))
        elseif isleaftype(S) && S.size == 0
            continue
        end
        if isa(S, DataType) && S.name.wrapper == Vararg
            n = S.parameters[2]
            elT = S.parameters[1]
            isa(n, Integer) || throw(ArgumentError("Tuple are only supported with definite lengths"))
            isa(elT, TypeVar) && push!(typevars, elT)
            if isa(elT, TypeVar) || isempty(eT.types) || elT <: Leaves
                append!(types, [elT for i = 1:n])
            else
                ntypes, ntypevars = gather_eltypes(S, Leaves, copy(visited); allow_typevar=allow_typevar)
                for i = 1:n
                    append!(types, ntypes)
                end
                append!(typevars, ntypevars)
            end
        elseif isa(S, TypeVar) || isempty(S.types) || S <: Leaves
            push!(types, S)
        else
            ntypes, ntypevars = gather_eltypes(S, Leaves, copy(visited); allow_typevar=allow_typevar)
            append!(types, ntypes)
            append!(typevars, ntypevars)
        end
    end
    types, typevars
end

@generated function StructOfArrays{T,Leaves,N,arrtuple}(dims::Tuple{Vararg{Integer}}) where {T,Leaves,N,arrtuple}
    Expr(:new, StructOfArrays{T,Leaves,N,arrtuple},
        Expr(:tuple,
          (:($arr(dims)) for arr in arrtuple.parameters)...))
end

@generated function StructOfArrays{T,Leaves}(dims::Tuple{Vararg{Integer}}) where {T,Leaves}
    types = gather_eltypes(T, Leaves)[1]
    arrtuple = Expr(:curly, Tuple, [:(Array{$S,length(dims)}) for S in types]...)
    :(StructOfArrays{T,Leaves,length(dims),$arrtuple}(dims...))
end

@generated function StructOfArrays{T}(dims::Tuple{Vararg{Integer}}) where {T}
    types, typevars = gather_eltypes(T)
    @assert isempty(typevars)
    arrtuple = Expr(:curly, Tuple, [:(Array{$S,length(dims)}) for S in types]...)
    :(StructOfArrays{T,Union{},length(dims),$arrtuple}(($([:(Array{$(S)}(dims)) for S in types]...),)))
end
StructOfArrays(T::Type, dims::Integer...) = StructOfArrays{T}(dims)
StructOfArrays(T::Type, dims::Tuple{Vararg{Integer}}) = StructOfArrays{T}(dims)
StructOfArrays{T}(dims::Integer...) where {T} = StructOfArrays{T}(dims)
StructOfArrays{T,Leaves}(dims::Integer...) where {T,Leaves} = StructOfArrays{T,Leaves}(dims)
StructOfArrays{T,Leaves,N,U}(dims::Integer...) where {T,Leaves,N,U} = StructOfArrays{T,Leaves,N,U}(dims)
StructOfArrays{T,<:Any,N}() where {T,N} = StructOfArrays{T}((0 for i=1:N)...)
StructOfArrays{T,Leaves,N,U}() where {T,Leaves,N,U} = StructOfArrays{T,Leaves,N,U}((0 for i=1:N)...)

@compat Base.IndexStyle{T<:StructOfArrays}(::Type{T}) = IndexLinear()

function Base.similar{T,N}(::Type{<:StructOfArrays}, ::Type{<:AbstractArray{T,N}})
    uT = Base.unwrap_unionall(T)
    types, typevars = gather_eltypes(uT, allow_typevar = true)
    Leaves = Union{typevars...}
    arrtuple = Tuple{[Array{S,N} for S in types]...}
    Base.rewrap_unionall(StructOfArrays{uT, Leaves, N, arrtuple}, T)
end

function Base.similar{T,N}(::Type{StructOfArrays}, A::AbstractArray{T,N})
    StructOfArrays{T}(size(A))
end

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

function generate_elementwise(leaff, recursef, combinef, state, T, Leaves, arraynum=1)
    for (el,S) in enumerate(T.types)
        sizeof(S) == 0 && push!(members, :($(S())))
        if isempty(S.types) || S <: Leaves
            leaff(arraynum, el, state)
            arraynum += 1
        else
            nstate, arraynum = generate_elementwise(leaff, recursef, combinef, recursef(S, arraynum, el, state), S, Leaves, arraynum)
            combinef(S, arraynum, el, state, nstate)
        end
    end
    state, arraynum
end

@generated function Base.getindex{T,Leaves}(A::StructOfArrays{T,Leaves}, i::Integer...)
    leaf(arraynum, el, members) = push!(members, :(A.arrays[$arraynum][i...]))
    recursef(S, arraynum, el, state) = Expr[]
    combinef(S, arraynum, el, members, eltmems) = push!(members, Expr(:new, S, eltmems...))
    mems, _ = generate_elementwise(leaf, recursef, combinef, Expr[], T, Leaves)
    Expr(:block, Expr(:meta, :inline, :propagate_inbounds), Expr(:new, T, mems...))
end

function setindex_recusion(exprs)
    function recursef(S, arraynum, el, state)
        s = gensym()
        push!(exprs, :($s = getfield($state, $el)))
        s
    end
end

no_combinef(args...) = nothing

@generated function Base.setindex!{T, Leaves}(A::StructOfArrays{T, Leaves}, x, i::Integer...)
    exprs = Expr[]
    function leaf(arraynum, el, state)
        push!(exprs, :(A.arrays[$arraynum][i...] = getfield($state, $el)))
    end
    generate_elementwise(leaf, setindex_recusion(exprs), no_combinef, :v, T, Leaves)
    exprs = Expr(:block, exprs...)
    quote
        $(Expr(:meta, :inline, :propagate_inbounds))
        v = convert(T, x)
        $exprs
        x
    end
end

@generated function Base.push!{T, Leaves}(A::StructOfArrays{T, Leaves}, x)
    exprs = Expr[]
    leaf(arraynum, el, state) = push!(exprs, :(push!(A.arrays[$arraynum],getfield($state,$el))))
    generate_elementwise(leaf, setindex_recusion(exprs), no_combinef, :v, T, Leaves)
    exprs = Expr(:block, exprs...)
    quote
        $(Expr(:meta, :inline))
        v = convert(T, x)
        $exprs
        x
    end
end

end # module
