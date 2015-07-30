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
