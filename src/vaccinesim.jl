using Statistics
using Plots

@enum Status S I R D

abstract type AbstractAgent end

mutable struct Agent <: AbstractAgent
    status::Status
    days_infected::Int
end

mutable struct VaccinatingAgent <: AbstractAgent
    status::Status
    days_infected::Int
end

mutable struct RelaxingAgent <: AbstractAgent
    status::Status
    days_infected::Int
end

isinfected(a::AbstractAgent) = a.status == I
issusceptible(a::AbstractAgent) = a.status == S
isrecovered(a::AbstractAgent) = a.status == R
isdead(a::AbstractAgent) = a.status == D

pdeath(a::AbstractAgent) = 0.005
preinfection(a::AbstractAgent) = 0.05
pexposure(a::AbstractAgent) = 0.1 # social distancing factor
envfactor() = 1.5
vaccinationrate(a::AbstractAgent) = 0

mutable struct World
    frame::Int
    agents::Vector{AbstractAgent}
end

fractioninfected(as::AbstractVector{AbstractAgent}) = count(isinfected, as) / count(!isdead, as)

#=

In Simulation 1, agents (people) have a chance of being infected each frame (day) based on the fraction
of the population currently infected, modulated by a factor summarizing the net effect of social
distancing, masking, and climate. An infection lasts 14 frames, at which point the agent will recover,
or die with probability 0.005. A recovered agent may be reinfected with chance reduced by a factor of
0.01.

=#

function update!(a::AbstractAgent, pinfection::Float64)
    if issusceptible(a)
        if rand() < pinfection * pexposure(a)
            a.status = I
            a.days_infected = 0
        elseif rand() < vaccinationrate(a)
            a.status = R
        end
    elseif isinfected(a)
        if a.days_infected == 14
            a.status = rand() < pdeath(a) ? D : R
        else
            a.days_infected += 1
        end
    elseif isrecovered(a)
        if rand() < pinfection * preinfection(a) * pexposure(a)
            a.status = I
            a.days_infected = 0
        end
    end
    return a
end

function update!(w::World)
    w.frame += 1
    pinfection = fractioninfected(w.agents) * envfactor()
    update!.(w.agents, pinfection)
    return w
end

function simulate(::Type{T}, nagents::Int, ninfected::Int, nframes::Int) where T <: AbstractAgent
    world = World(1, [[T(S, 0) for i ∈ 1:(nagents - ninfected)]; [T(I, 0) for i ∈ 1:ninfected]])

    history = [world]
    for i ∈ 1:nframes
        world = deepcopy(world)
        update!(world)
        push!(history, world)
    end
    return history
end

function metasimulate(::Type{T}) where T <: AbstractAgent
    metahistory = []
    for i ∈ 1:100
        history = simulate(T, 1000, 10, 180)
        push!(metahistory, [[count(issusceptible, w.agents); count(isinfected, w.agents); count(isrecovered, w.agents); count(isdead, w.agents)] for w ∈ history])
    end
    return mean(metahistory)
end

# normal
results1 = metasimulate(Agent)
p1 = plot(permutedims(hcat(results1...)), labels = ["susceptible" "infected" "recovered" "dead"], linewidth = 3, legend = :none)

# 2 / 330 vaccinations per day
vaccinationrate(::VaccinatingAgent) = 2 / 330
results2 = metasimulate(VaccinatingAgent)
p2 = plot(permutedims(hcat(results2...)), labels = ["susceptible" "infected" "recovered" "dead"], linewidth = 3, legend = :none)

# recovereds have 5x higher exposure risk
pexposure(a::RelaxingAgent) = isrecovered(a) ? 0.5 : 0.1
vaccinationrate(::RelaxingAgent) = 2 / 330
results3 = metasimulate(RelaxingAgent)
p3 = plot(permutedims(hcat(results3...)), labels = ["susceptible" "infected" "recovered" "dead"], linewidth = 3, legend = :none)


plot(p1, p2, p3, layout = grid(1, 3))
savefig(joinpath("output", "models.png"))

plot(permutedims(hcat(results1[end][end], results2[end][end], results3[end][end])), seriestype=:bar, legend=:none)
savefig(joinpath("output", "modeldeaths.png"))
