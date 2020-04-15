using CuArrays
using CuArrays: @allowscalar
using CUDAnative
using LinearAlgebra
CuArrays.allowscalar(false)

@testset "basic" begin
    type = SArray{Tuple{3},Float64,1,3}
    N = 1000
    data = rand(MersenneTwister(0), type, N)

    a = CuArray(data)
    b = StructOfArrays(type, CuArray, N)
    c = similar(a)
    d = replace_storage(CuArray, convert(StructOfArrays, data))

    @test eltype(d) == type
    @test eltype(eltype(d.arrays)) == Float64
    @test @allowscalar a[3] === d[3]

    function kernel!(dest, src)
        i = (blockIdx().x-1)*blockDim().x + threadIdx().x
        if i <= length(dest)
            dest[i] = src[i]
        end
        return nothing
    end

    threads = 1024
    blocks = cld(length(a), threads)

    @cuda threads=threads blocks=blocks kernel!(b, a)
    @test @allowscalar a[3] === b[3]

    @cuda threads=threads blocks=blocks kernel!(c, b)
    @test @allowscalar c[3] === b[3]
end

@testset "broadcast" begin
    type = SArray{Tuple{3},Float64,1,3}
    N = 1000
    data = rand(MersenneTwister(0), type, N)

    d = replace_storage(CuArray, convert(StructOfArrays, data))
    e = d .+ d
    @test @allowscalar e[3] == d[3] .+ d[3]
    n = norm.(d)
    @test @allowscalar n[4] == norm(d[4])

    f = convert(StructOfArrays, rand(ComplexF64, 1, 3))
    g = convert(StructOfArrays, rand(ComplexF64, 3, 1))

    cf = replace_storage(CuArray, f)
    cg = replace_storage(CuArray, g)

    o = f .+ g
    co = cf .+ cg
    @test @allowscalar o[2, 1] == co[2, 1]
end
