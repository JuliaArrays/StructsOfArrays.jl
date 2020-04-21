using GPUArrays

const AbstractStructOfGPUArrays = StructOfArrays{T,N,<:AbstractGPUArray} where {T, N}
const AbstractStructOfGPUArraysStyle{N} = Broadcast.ArrayStyle{StructOfArrays{T,N,<:AbstractGPUArray}} where T

# Wrapper types otherwise forget that they are StructOfArrays
for (W, ctor) in Adapt.wrappers
    @eval begin
        BroadcastStyle(::Type{<:$W}) where {AT<:StructOfArrays{T,N,A} where {T,N,A}} = BroadcastStyle(AT)
        backend(::Type{<:$W}) where {AT<:StructOfArrays{T,N,A} where {T,N,A}} = backend(AT)
    end
end

# This Union is a hack. Ideally Base would have a
#     Transpose <: WrappedArray <: AbstractArray
# and we could define our methods in terms of
#     Union{AbstractStructOfGPUArrays, WrappedArray{<:Any, <:AbstractStructOfGPUArrays}}
@eval const DestStructOfGPUArrays =
    Union{AbstractStructOfGPUArrays,
          $((:($W where {AT <: AbstractStructOfGPUArrays}) for (W, _) in Adapt.wrappers)...),
          Base.RefValue{<:AbstractStructOfGPUArrays} }

# Ref is special: it's not a real wrapper, so not part of Adapt,
# but it is commonly used to bypass broadcasting of an argument
# so we need to preserve its dimensionless properties.
BroadcastStyle(::Type{Base.RefValue{AT}}) where {AT<:AbstractStructOfGPUArrays} = typeof(BroadcastStyle(AT))(Val(0))
backend(::Type{Base.RefValue{AT}}) where {AT<:AbstractStructOfGPUArrays} = backend(AT)
# but make sure we don't dispatch to the optimized copy method that directly indexes
function Broadcast.copy(bc::Broadcasted{<:Broadcast.ArrayStyle{StructOfArrays{T,0,<:AbstractGPUArray}}}) where {T}
    ElType = Broadcast.combine_eltypes(bc.f, bc.args)
    isbitstype(ElType) || error("Cannot broadcast function returning non-isbits $ElType.")
    dest = copyto!(similar(bc, ElType), bc)
    return @allowscalar dest[CartesianIndex()]  # 0D broadcast needs to unwrap results
end

# Base defines this method as a performance optimization, but we don't know how to do
# `fill!` in general for all `DestStructOfGPUArrays` so we just go straight to the fallback
@inline Base.copyto!(dest::DestStructOfGPUArrays, bc::Broadcasted{<:AbstractArrayStyle{0}}) =
    copyto!(dest, convert(Broadcasted{Nothing}, bc))

## map
allequal(x) = true
allequal(x, y, z...) = x == y && allequal(y, z...)

function Base.map!(f, y::DestStructOfGPUArrays, xs::AbstractArray...)
    @assert allequal(size.((y, xs...))...)
    return y .= f.(xs...)
end

function Base.map(f, y::DestStructOfGPUArrays, xs::AbstractArray...)
    @assert allequal(size.((y, xs...))...)
    return f.(y, xs...)
end
