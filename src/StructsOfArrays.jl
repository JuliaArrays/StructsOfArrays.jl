module StructsOfArrays
export StructOfArrays, ScalarRepeat

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

function StructOfArrays(T::Type, first_array::AbstractArray, rest::AbstractArray...)
    (!isleaftype(T) || T.mutable) && throw(ArgumentError(
        "can only create an StructOfArrays of leaf type immutables"
    ))
    arrays = (first_array, rest...)
    target_eltypes = flattened_bitstypes(T)
    source_eltypes = DataType[]
    #flatten array eltypes
    for elem in arrays
        append!(source_eltypes, flattened_bitstypes(eltype(elem)))
    end
    # flattened eltypes don't match with flattened struct type
    if target_eltypes != source_eltypes
        throw(ArgumentError("""$T does not match the given parameters.
        Argument types: $(map(typeof, arrays))
        Flattened struct types: $target_eltypes
        Flattened argument types: $source_eltypes
        """))
    end
    # flattened they match! ♥💕
    typetuple = Tuple{map(typeof, arrays)...}
    StructOfArrays{T, ndims(first_array), typetuple}(arrays)
end

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

Base.size(A::StructOfArrays) = size(first(A.arrays))
Base.size(A::StructOfArrays, d) = size(first(A.arrays), d)

"""
returns all field types of a composite type or tuple.
If it's neither composite, nor tuple, it will just return the DataType.
"""
fieldtypes{T<:Tuple}(::Type{T}) = (T.parameters...)
function fieldtypes{T}(::Type{T})
    if nfields(T) > 0
        return ntuple(i->fieldtype(T, i), nfields(T))
    else
        return T
    end
end

"""
Returns a flattened and unflattened view of the elemenents of a type
E.g:
immutable X
x::Float32
y::Float32
end
immutable Y
a::X # tuples would get expanded as well
b::Float32
c::Float32
end
Would return
[Float32, Float32, Float32, Float32]
and
[(Y, [(X, [Float32, Float32]), Float32, Float32]]
"""
function flattened_bitstypes{T}(::Type{T}, flattened=DataType[])
    fields = fieldtypes(T)
    if isa(fields, DataType)
        if (!isleaftype(T) || T.mutable)
            throw(ArgumentError("can only create an StructOfArrays of leaf type immutables"))
        end
        push!(flattened, fields)
        return flattened
    else
        for T in fields
            flattened_bitstypes(T, flattened)
        end
    end
    flattened
end

"""
Takes a tuple of array types with arbitrary structs as elements.
return `flat_indices` and `temporaries`. `flat_indices` is a vector with indices to every elemen in the array.
`temporaries` is a vector of temporaries, which effectively store the elemens from the arrays
E.g.
flatindexes((Vector{Vec3f0}) will return:
with `array_expr=(A.arrays)` and `index_expr=:([i...])`:
`temporaries`:
    [:(value1 = A.arrays[i...])]
`flat_indices`:
    [:(value1.(1).(1)), :(value1.(1).(2)), :(value1.(1).(3))] # .(1) to acces tuple of Vec3
"""
function flatindexes(arrays)
    temporaries = []
    flat_indices = []
    for (i, array) in enumerate(arrays)
        tmpsym = symbol("value$i")
        push!(temporaries, :($(tmpsym) = A.arrays[$i][i...]))
        index_expr = :($tmpsym)
        flatindexes(eltype(array), index_expr, flat_indices)
    end
    flat_indices, temporaries
end

function flatindexes(T, index_expr, flat_indices)
    fields = fieldtypes(T)
    if isa(fields, DataType)
        push!(flat_indices, index_expr)
        return nothing
    else
        for (i,T) in enumerate(fields)
            new_index_expr = :($(index_expr).($i))
            flatindexes(T, new_index_expr, flat_indices)
        end
    end
    nothing
end

"""
Creates a nested type T from elements in `flat_indices`.
`flat_indices` can be any array with expressions inside, as long as there is an
element for every field in `T`.
"""
function typecreator(T, lower_constr, flat_indices, i=1)
    i>length(flat_indices) && return i
    # we need to special case tuples, since e.g. Tuple{Float32, Float32}(1f0, 1f0)
    # is not defined.
    if T<:Tuple
        constructor = Expr(:tuple)
    else
        constructor = Expr(:call, T)
    end
    push!(lower_constr.args, constructor)
    fields = fieldtypes(T)
    if isa(fields, DataType)
        push!(constructor.args, flat_indices[i])
        return i+1
    else
        for T in fields
            i = typecreator(T, constructor, flat_indices, i)
        end
    end
    return i
end

@generated function Base.getindex{T, N, ArrayTypes}(A::StructOfArrays{T, N, ArrayTypes}, i::Integer...)
    #flatten the indices,
    flat_indices, temporaries = flatindexes((ArrayTypes.parameters...))
    type_constructor = Expr(:block)
    # create a constructor expression, which uses the flattened indexes to create the type
    typecreator(T, type_constructor, flat_indices)
    # put everything in a block!
    Expr(:block, Expr(:meta, :inline), temporaries..., type_constructor)
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
