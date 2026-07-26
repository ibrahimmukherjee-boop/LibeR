using JSON3
using OrdinaryDiffEq
using DelayDiffEq
using Sundials
using StochasticDiffEq
using Random
using Statistics

length(ARGS) == 1 || error("Usage: sciml-reference.jl OUTPUT.json")
output = ARGS[1]

qsp_times = [0.0, 0.25, 0.5, 1.0, 2.0, 4.0]
function qsp!(du, u, p, t)
    rate = p * u[1]
    du[1] = -rate
    du[2] = rate
end
qsp_problem = ODEProblem(qsp!, [10.0, 0.0], (0.0, 4.0), 0.4)
qsp_solution = solve(
    qsp_problem, Vern9(), saveat = qsp_times,
    abstol = 1e-12, reltol = 1e-12
)
qsp = permutedims(reduce(hcat, qsp_solution.u))

advan14_times = [0.0, 0.01, 0.1, 1.0]
function advan14!(du, u, p, t)
    du[1] = -p.fast * u[1]
    du[2] = p.fast * u[1] - p.slow * u[2]
end
advan14_problem = ODEProblem(
    advan14!, [100.0, 0.0], (0.0, 1.0), (fast = 1000.0, slow = 1.0)
)
advan14_solution = solve(
    advan14_problem, Rodas5P(), saveat = advan14_times,
    abstol = 1e-12, reltol = 1e-10
)
advan14 = permutedims(reduce(hcat, advan14_solution.u))

dde_times = [0.0, 0.5, 1.0, 1.5, 2.0, 3.0]
dde_parameters = (k = 0.4, feedback = 0.15, delay = 1.0)
function dde!(du, u, history, p, t)
    du[1] = -p.k * u[1] + p.feedback * history(p, t - p.delay)[1]
end
dde_history(p, t) = [10.0]
dde_problem = DDEProblem(
    dde!, [10.0], dde_history, (0.0, 3.0), dde_parameters;
    constant_lags = [dde_parameters.delay]
)
dde_solution = solve(
    dde_problem, MethodOfSteps(Vern9()), saveat = dde_times,
    abstol = 1e-11, reltol = 1e-11
)
dde = [state[1] for state in dde_solution.u]

dae_times = [0.0, 0.5, 1.0, 2.0, 3.0]
dae_k = 0.16
function dae_residual!(residual, du, u, p, t)
    residual[1] = du[1] + u[2]
    residual[2] = u[2]^2 - p * u[1]
end
dae_u0 = [10.0, sqrt(dae_k * 10.0)]
dae_du0 = [-dae_u0[2], -dae_k / 2]
dae_problem = DAEProblem(
    dae_residual!, dae_du0, dae_u0, (0.0, 3.0), dae_k;
    differential_vars = [true, false]
)
dae_solution = solve(
    dae_problem, IDA(), saveat = dae_times,
    abstol = 1e-11, reltol = 1e-11
)
dae = [state[1] for state in dae_solution.u]

Random.seed!(20260724)
ou_k = 0.4
ou_diffusion = 0.3
ou_step = 1 / 64
function ou_drift!(du, u, p, t)
    du[1] = -ou_k * u[1]
end
function ou_diffusion!(du, u, p, t)
    du[1] = ou_diffusion
end
ou_problem = SDEProblem(ou_drift!, ou_diffusion!, [1.0], (0.0, 1.0))
ou_ensemble = EnsembleProblem(ou_problem)
ou_solution = solve(
    ou_ensemble, EM(), EnsembleSerial();
    trajectories = 4000, adaptive = false, dt = ou_step, saveat = [1.0]
)
ou_terminal = [trajectory.u[end][1] for trajectory in ou_solution.u]

open(output, "w") do stream
    JSON3.write(stream, Dict(
        "schema" => "liber.sciml-reference/1",
        "julia_version" => string(VERSION),
        "qsp" => Dict("times" => qsp_times, "states" => qsp),
        "advan14" => Dict("times" => advan14_times, "states" => advan14),
        "dde" => Dict("times" => dde_times, "state" => dde),
        "dae" => Dict("times" => dae_times, "state" => dae),
        "sde" => Dict(
            "trajectories" => length(ou_terminal),
            "step" => ou_step,
            "terminal_mean" => mean(ou_terminal),
            "terminal_variance" => var(ou_terminal)
        )
    ))
end
