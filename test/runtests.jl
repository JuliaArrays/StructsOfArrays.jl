using SoArrays
using Base.Test

regular = complex(randn(10000), randn(10000))
soa = convert(SoArray, regular)
@test regular == soa
@test_approx_eq sum(regular) sum(soa)

soa64 = convert(SoArray{Complex64}, regular)
@test convert(Array{Complex64}, regular) == soa64

sim = similar(soa)
@test typeof(sim) == typeof(soa)
@test size(sim) == size(soa)
