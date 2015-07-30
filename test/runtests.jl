using SoArrays
using Base.Test

regular = complex(randn(10000), randn(10000))
soa = SoArray(Complex128, size(regular))
copy!(soa, regular)
@test_approx_eq sum(regular) sum(soa)
