using StructsOfArrays
using Test
using Random
using StaticArrays

@testset "StructsOfArrays.jl" begin
    @testset "constructor" begin
        regular = rand(MersenneTwister(0), ComplexF64, 10000)
        soa = convert(StructOfArrays, regular)
        @test regular == soa
        @test sum(regular) ≈ sum(soa)

        soa64 = convert(StructOfArrays{ComplexF64}, regular)
        @test convert(Array{ComplexF64}, regular) == soa64

        sim = similar(soa)
        @test typeof(sim) == typeof(soa)
        @test size(sim) == size(soa)

        regular = randn(MersenneTwister(0), ComplexF64, 10, 5)
        soa = convert(StructOfArrays, regular)
        for i = 1:10, j = 1:5
            @test regular[i, j] == soa[i, j]
        end
        @test size(soa, 1) == 10
        @test size(soa, 2) == 5
    end

    @testset "similar" begin
        struct OneField
            x::Int
        end

        small = StructOfArrays(ComplexF64, Array, 2)
        @test typeof(small) <: AbstractArray{Complex{T}} where T
        @test typeof(similar(small, ComplexF64)) <: AbstractArray{Complex{Float64}}
        @test typeof(similar(small, Int)) <: AbstractArray{Int}
        @test typeof(similar(small, OneField)) <: AbstractArray{OneField}
        @test typeof(similar(small, ComplexF64)) <: StructOfArrays
    end

    @testset "broadcast" begin
        regular = rand(MersenneTwister(0), ComplexF64, 100)
        soa = convert(StructOfArrays, regular)
        @test regular .+ regular == soa .+ soa
        @test typeof(soa .+ soa) === typeof(soa)
        @test typeof(regular .+ soa) === typeof(soa)
        @test sin.(soa)[2] == sin(regular[2])
    end

    @testset "recursive structs" begin
        struct OneField
            x::Int
        end

        struct TwoField
            one::OneField
            two::OneField
        end

        small = StructOfArrays(TwoField, Array, 2, 2)
        small[1,1] = TwoField(OneField(1), OneField(2))
        @test small[1,1] == TwoField(OneField(1), OneField(2))
    end

    @testset "StaticArrays" begin
        type = SArray{Tuple{3},Float64,1,3}
        regular = rand(MersenneTwister(0), type, 10000)
        soa = convert(StructOfArrays, regular)
        @test regular == soa
        @test sum(regular) ≈ sum(soa)
        @test eltype(regular) === eltype(soa)
        @test regular[3] === soa[3]
    end
end
