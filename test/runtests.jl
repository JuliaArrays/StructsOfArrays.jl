using StructsOfArrays
using Base.Test

regular = complex(randn(10000), randn(10000))
soa = convert(StructOfArrays, regular)
@test regular == soa
@test_approx_eq sum(regular) sum(soa)

soa64 = convert(StructOfArrays{Complex64}, regular)
@test convert(Array{Complex64}, regular) == soa64

sim = similar(soa)
@test typeof(sim) == typeof(soa)
@test size(sim) == size(soa)

regular = complex(randn(10, 5), randn(10, 5))
soa = convert(StructOfArrays, regular)
for i = 1:10, j = 1:5
    @test regular[i, j] == soa[i, j]
end
@test size(soa, 1) == 10
@test size(soa, 2) == 5

immutable OneField
    x::Int
end

small = StructOfArrays(Complex64, 2)
@test typeof(similar(small, Complex)) === Vector{Complex}
@test typeof(similar(small, Int)) === Vector{Int}
@test typeof(similar(small, SubString)) === Vector{SubString}
@test typeof(similar(small, OneField)) === Vector{OneField}
@test typeof(similar(small, Complex128)) <: StructOfArrays

immutable Vec{N,T}
    _::NTuple{N,T}
end
immutable HyperCube{N,T}
    origin::Vec{N,T}
    width::Vec{N,T}
end
immutable Instance{P, S, T, R}
    primitive::P
    scale::S
    translation::T
    rotation::R
end
immutable ScalarRepeat{T,N} <: AbstractArray{T,N}
    value::T
    size::NTuple{N,Int}
end
Base.size(sr::ScalarRepeat) = sr.size
Base.size(sr::ScalarRepeat, d) = sr.size[d]
Base.getindex(sr::ScalarRepeat, i...) = sr.value
Base.linearindexing{T<:ScalarRepeat}(::Type{T}) = Base.LinearFast()


function test_topologic_structs()
    hco_x,hco_yz = rand(Float32, 10), [Vec{2,Float32}((rand(Float32), rand(Float32))) for i=1:10]
    hcw_z,hcw_xy = rand(Float32, 10), [Vec{2,Float32}((rand(Float32), rand(Float32))) for i=1:10]
    scale = ScalarRepeat(1f0, (10,))
    translation = ScalarRepeat(Vec{3, Float32}((2,1,3)), (10,))
    rotation = [Vec{4, Float32}((rand(Float32),rand(Float32),rand(Float32),rand(Float32))) for i=1:10]
    soa = StructOfArrays(
        Instance{HyperCube{3, Float32}, Float32, Vec{3, Float32}, Vec{4,Float32}},
        hco_x,hco_yz, hcw_xy, hcw_z, scale, translation, rotation
    )
    zipped = zip(hco_x,hco_yz, hcw_xy, hcw_z, scale, translation, rotation)
    for (i,(ox,oyz, wxy, wz, s, t, r)) in enumerate(zipped)
        instance = soa[i]
        @test instance.primitive.origin.(1).(1) === ox
        @test instance.primitive.origin.(1).(2) === oyz.(1).(1)
        @test instance.primitive.origin.(1).(3) === oyz.(1).(2)

        @test instance.primitive.width.(1).(1) === wxy.(1).(1)
        @test instance.primitive.width.(1).(2) === wxy.(1).(2)
        @test instance.primitive.width.(1).(3) === wz

        @test instance.scale       === s
        @test instance.translation === t
        @test instance.rotation    === r

    end
end

test_topologic_structs()
