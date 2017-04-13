using StructsOfArrays
using Base.Test
using Compat

regular = @compat complex.(randn(10000), randn(10000))
soa = convert(StructOfArrays, regular)
@test regular == soa
@test sum(regular) ≈ sum(soa)

soa64 = convert(StructOfArrays{Complex64}, regular)
@test convert(Array{Complex64}, regular) == soa64

sim = similar(soa)
@test typeof(sim) == typeof(soa)
@test size(sim) == size(soa)

regular = @compat complex.(randn(10, 5), randn(10, 5))
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

# Recursive structs
immutable TwoField
    one::OneField
    two::OneField
end

small = StructOfArrays(TwoField, 2, 2)
small[1,1] = TwoField(OneField(1), OneField(2))
@test small[1,1] == TwoField(OneField(1), OneField(2))

# SoA with explicit leaves
immutable Complex3D
    x::Complex{Float64}
    y::Complex{Float64}
    z::Complex{Float64}
end

ComplexA = Complex3D(Complex{Float64}(1.0,2.0),
                     Complex{Float64}(3.0,4.0),
                     Complex{Float64}(5.0,6.0))
full_rec = StructOfArrays{Complex3D}(2, 2)
@test length(full_rec.arrays) == 6
full_rec[1,1] = ComplexA
@test full_rec[1,1] == ComplexA

partial_rec = StructOfArrays{Complex3D,Complex}(2, 2)
@test length(partial_rec.arrays) == 3
partial_rec[2,2] = ComplexA
@test partial_rec[2,2] == ComplexA

struct Bundle
    x::Complex{Float64}
    y::Complex{Int64}
    z::Rational{Int64}
end

BundleA = Bundle(Complex{Float64}(1.0,2.0),
           Complex{Int64}(1.0,2.0),
           1//2)
full_rec = StructOfArrays{Bundle}(2, 2)
@test length(full_rec.arrays) == 6
full_rec[1,1] = BundleA
@test full_rec[1,1] == BundleA

partial_rec = StructOfArrays{Bundle,Any}(2, 2)
@test length(partial_rec.arrays) == 3
partial_rec[2,2] = BundleA
@test partial_rec[2,2] == BundleA

# SoA with parameterized leaves
immutable ParamComplex3D{T}
    x::Complex{T}
    y::Complex{T}
    z::Complex{T}
end

ParamComplexA = ParamComplex3D{Float64}(ComplexA.x, ComplexA.y, ComplexA.z)
full_rec = StructOfArrays{ParamComplex3D{Float64}}(2, 2)
@test length(full_rec.arrays) == 6
full_rec[1,2] = ParamComplexA
@test full_rec[1,2] == ParamComplexA

partial_rec = StructOfArrays{ParamComplex3D{Float64},Complex}(2, 2)
@test length(partial_rec.arrays) == 3
full_rec[2,1] = ParamComplexA
@test full_rec[2,1] == ParamComplexA

const SoAParamComplex3D{T} = similar(StructOfArrays, Matrix{ParamComplex3D{T}})
soa = SoAParamComplex3D{Float64}(2, 2)
@test length(soa.arrays) == 6
@test eltype(soa.arrays[1]) == Float64
full_rec[2,2] = ParamComplexA
@test full_rec[2,2] == ParamComplexA
  
immutable Param3D{T}
    x::T
    y::T
    z::T
end
OtherParamComplexA = Param3D{Complex{Float64}}(ComplexA.x, ComplexA.y, ComplexA.z)
const OtherSoAParamComplex3D{T} = similar(StructOfArrays, Matrix{Param3D{T}})
soa = OtherSoAParamComplex3D{Complex{Float64}}(2, 2)
@test length(soa.arrays) == 3
@test eltype(soa.arrays[1]) == Complex{Float64}
soa[1,1] = OtherParamComplexA
@test soa[1,1] == OtherParamComplexA

NesetedA = Param3D{Param3D{Complex{Float64}}}(OtherParamComplexA, OtherParamComplexA, OtherParamComplexA)
nestedsoa = OtherSoAParamComplex3D{Param3D{Complex{Float64}}}(2, 2)
@test length(soa.arrays) == 3
@test eltype(soa.arrays[1]) == Complex{Float64}
nestedsoa[1,1] = NesetedA
@test nestedsoa[1,1] == NesetedA

# NTuples
V = Vector{NTuple{4, Int64}}()
ntuplesoa = similar(StructOfArrays, V)
@test length(ntuplesoa.arrays) == 4
push!(ntuplesoa, (1,2,3,4))
@test ntuplesoa[1] == (1,2,3,4)
ntuplesoa[1] = (5,6,7,8)
@test ntuplesoa[1] == (5,6,7,8)

# Parameterized NTuples
immutable SVec{T}
    data::NTuple{3, T}
end
SVecSoA{T} = similar(StructOfArrays, Vector{SVec{T}})
svecsoa = SVecSoA{Float64}()
@test length(svecsoa.arrays) == 3
push!(svecsoa, SVec((1.,2.,3.)))
@test svecsoa[1] == SVec((1.,2.,3.))
svecsoa[1] = SVec((4.,5.,6.))
@test svecsoa[1] == SVec((4.,5.,6.))
