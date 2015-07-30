using SoArrays
using Base.Test

regular = complex(randn(10000000), randn(10000000))
soa = SoArray(Complex128, size(regular))
copy!(soa, regular)
@test_approx_eq regular soa
