import CuArrays
import CuArrays: CuArray
_type_with_eltype(::Type{<:CuArray}, T, N) = CuArray{T, N, Nothing}
_type(::Type{<:CuArray}) = CuArray

import CUDAnative
import CUDAnative: CuDeviceArray
_type_with_eltype(::Type{<:CuDeviceArray}, T, N) = CuDeviceArray{T, N}
_type(::Type{<:CuDeviceArray}) = CuDeviceArray

const AbstractStructOfCuArrays = StructOfArrays{T,N,<:CuArray} where {T, N}

@eval const DestStructOfCuArrays =
    Union{AbstractStructOfCuArrays,
          $((:($W where {AT <: AbstractStructOfCuArrays}) for (W, _) in Adapt.wrappers)...),
          Base.RefValue{<:AbstractStructOfCuArrays} }

function broadcast_kernel!(dest, bc′)
    i = (CUDAnative.blockIdx().x-1)*CUDAnative.blockDim().x + CUDAnative.threadIdx().x
    if i <= length(dest)
        let I = CartesianIndex(CartesianIndices(dest)[i])
            @inbounds dest[I] = bc′[I]
        end
    end
    return nothing
end

@inline function Base.copyto!(dest::DestStructOfCuArrays, bc::Broadcasted{Nothing})
    axes(dest) == axes(bc) || Broadcast.throwdm(axes(dest), axes(bc))
    bc′ = Broadcast.preprocess(dest, bc)

    threads = 256
    blocks = cld(length(dest), threads)

    CUDAnative.@cuda threads=threads blocks=blocks broadcast_kernel!(dest, bc′)

    return dest
end
