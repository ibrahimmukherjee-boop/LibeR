using Pkg

root = normpath(joinpath(@__DIR__, "..", ".."))
environment = joinpath(root, ".external-tools", "julia-project")
mkpath(environment)
Pkg.activate(environment)
Pkg.add([
    PackageSpec(name = "JSON3", version = "1.14.3"),
    PackageSpec(name = "OrdinaryDiffEq", version = "7.1.3"),
    PackageSpec(name = "StochasticDiffEq", version = "7.1.2"),
    PackageSpec(name = "DelayDiffEq", version = "6.1.0"),
    PackageSpec(name = "Sundials", version = "6.4.2"),
    PackageSpec(name = "SciMLSensitivity", version = "7.116.2"),
])
Pkg.instantiate()
Pkg.precompile()

println("SciML comparator environment: ", environment)
Pkg.status()
