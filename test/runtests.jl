using StructsOfArrays
using Test

regular = complex.(randn(10000), randn(10000))
soa = convert(StructOfArrays, regular)
@test regular == soa
@test sum(regular) ≈ sum(soa)

soa64 = convert(StructOfArrays{ComplexF32}, regular)
@test convert(Array{ComplexF32}, regular) == soa64

sim = similar(soa)
@test typeof(sim) == typeof(soa)
@test size(sim) == size(soa)

regular = complex.(randn(10, 5), randn(10, 5))
soa = convert(StructOfArrays, regular)
for i = 1:10, j = 1:5
    @test regular[i, j] == soa[i, j]
end
@test size(soa, 1) == 10
@test size(soa, 2) == 5

struct OneField
    x::Int
end

small = StructOfArrays(ComplexF32, 2)
@test typeof(similar(small, Complex)) === Vector{Complex}
@test typeof(similar(small, Int)) === Vector{Int}
@test typeof(similar(small, SubString)) === Vector{SubString}
@test typeof(similar(small, OneField)) === Vector{OneField}
@test typeof(similar(small, ComplexF64)) <: StructOfArrays

# Recursive structs
struct TwoField
    one::OneField
    two::OneField
end

small = StructOfArrays(TwoField, 2, 2)
small[1,1] = TwoField(OneField(1), OneField(2))
@test small[1,1] == TwoField(OneField(1), OneField(2))
