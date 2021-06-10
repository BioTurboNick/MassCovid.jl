using Dates
using Shapefile
using Plots
using XLSX

function loadtowndata()
    path = joinpath("geodata", "TOWNSSURVEY_POLYM.shp")
    table = Shapefile.Table(path)
    sorted_order = sortperm(table.TOWN)
    geoms = Shapefile.shapes(table)[sorted_order]
    pop2010 = table.POP2010[sorted_order]
    geoms, pop2010
end

function downloadweeklyreport(datestring)
    path = joinpath("input","$(datestring)-vaccine.xlsx")
    ispath(path) && return path
    download("https://www.mass.gov/doc/weekly-covid-19-municipality-vaccination-report-$(datestring)/download", path)
end

agecat = ["0-19 Years", "20-29 Years", "30-49 Years", "50-64 Years", "65-74 Years", "75+ Years", "Total"]

function agecategory(agestring)
    return agestring == "0-19 Years" ? 1 :
           agestring == "20-29 Years" ? 2 :
           agestring == "30-49 Years" ? 3 :
           agestring == "50-64 Years" ? 4 :
           agestring == "65-74 Years" ? 5 :
           agestring == "75+ Years" ? 6 :
           agestring == "Total" ? 7 :
           8 # youth categories
end

function unmergetowns!(names, ages, pops, onepluspercent, fullpercent, maintown, subtown, nrows)
    append!(names, fill(subtown, nrows))
    append!(ages, collect(((1:nrows - 1)...,0)))
    range = findfirst(x -> startswith(x, "$maintown "), names) .+ (0:nrows - 1)
    append!(onepluspercent, onepluspercent[range])
    append!(fullpercent, fullpercent[range])
    append!(pops, pops[range])
    nothing
end

function loadweekdata(path)
    data = XLSX.readxlsx(path)

    sheet = data["Age - municipality"]
    nrows = "12-15 Years" ∈ sheet["C"][3:end] ? 8 : 7
    range = 2 .+ (1:nrows * 337)
    names = sheet["B"][range]
    pops = sheet["D"][range]
    ages = agecategory.(sheet["C"][range])
    onepluspercent = sheet["G"][range]
    fullpercent = sheet["J"][range]
    replace!(onepluspercent, "*" => 0, ">95%" => 1)
    replace!(fullpercent, "*" => 0, ">95%" => 1)

    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Amherst", "Pelham", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Athol", "Phillipston", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Becket", "Washington", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Charlemont", "Hawley", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Chilmark", "Aquinnah", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Easthampton", "Westhampton", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Egremont", "Mount Washington", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Granville", "Westhampton", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Great Barrington", "Alford", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Greenfield", "Leyden", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Hinsdale", "Peru", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Lanesborough", "Hancock", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Lanesborough", "New Ashford", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "North Adams", "Clarksburg", nrows)
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Westfield", "Montgomery", nrows)

    order = sortperm(names)
    names = names[order]
    ages = ages[order]
    pops = pops[order]
    onepluspercent = onepluspercent[order]
    fullpercent = fullpercent[order]

    # put 12-15 and 16-19 back into 0-19
    @views if any(==(8), ages)
        shape = (8, length(pops) ÷ 8)
        pops = reshape(pops, shape)
        childpop = pops[8,:] .- sum(pops[3:7,:], dims = 1)'
        onepluspercentr = reshape(onepluspercent, shape)
        fullpercentr = reshape(fullpercent, shape)
        onepluspop12to15 = pops[1,:] .* onepluspercentr[1,:]
        onepluspop16to19 = pops[2,:] .* onepluspercentr[2,:]
        fullpop12to15 = pops[1,:] .* fullpercentr[1,:]
        fullpop16to19 = pops[2,:] .* fullpercentr[2,:]
        onepluspercentr[2,:] = (onepluspop12to15 .+ onepluspop16to19) ./ childpop
        fullpercentr[2,:] = (fullpop12to15 .+ fullpop16to19) ./ childpop
        onepluspercent = vec(onepluspercentr[2:8,:])
        fullpercent = vec(fullpercentr[2:8,:])
    end
    
    # place "Unspecified" at end
    unknowntown = findfirst(==("Unspecified"), names)
    onepluspercent = [onepluspercent[1:unknowntown - 1]; onepluspercent[unknowntown + 7:end]; onepluspercent[unknowntown:unknowntown + 6]]
    fullpercent = [fullpercent[1:unknowntown - 1]; fullpercent[unknowntown + 7:end]; fullpercent[unknowntown:unknowntown + 6]]
    
    # dim 1 = town, dim 2 = age range
    onepluspercent = permutedims(reshape(onepluspercent, (7, 352)), (2, 1))
    fullpercent = permutedims(reshape(fullpercent, (7, 352)), (2, 1))
    return onepluspercent, fullpercent
end

function calculaterisklevels(fraction)
    risklevel = [r == 0.0 ? 10 :
                r < 0.1 ? 9 :
                 r < 0.2 ? 8 :
                 r < 0.3 ? 7 :
                 r < 0.4 ? 6 :
                 r < 0.5 ? 5 :
                 r < 0.6 ? 4 :
                 r < 0.7 ? 3 :
                 r < 0.8 ? 2 :
                 r < 0.9 ? 1 :
                 0 for r ∈ fraction]
end

geoms, pop2010 = loadtowndata()

weeks = ["march-11-2021",
         "march-18-2021",
         "march-25-2021",
         "april-1-2021",
         "april-8-2021",
         "april-15-2021",
         "april-22-2021",
         "april-29-2021",
         "may-6-2021",
         "may-13-2021",
         "may-20-2021",
         "may-27-2021",
         "june-3-2021",
         "june-10-2021"]

labels = reverse(["*",
          "<10 %",
          "10-20 %",
          "20-30 %",
          "30-40 %",
          "40-50 %",
          "50-60 %",
          "60-70 %",
          "70-80 %",
          "80-90 %",
          ">90 %"])

riskcolors = Dict(0 => :deepskyblue,
                  1 => :green,
                  2 => :chartreuse2,
                  3 => :yellow,
                  4 => RGB(243/255, 12/255, 0),
                  5 => :red3,
                  6 => :darkred,
                  7 => RGB(85/255, 0, 0),
                  8 => :indigo,
                  9 => RGB(0, 0, 85/255),
                  10 => :black
                  )

push!(geoms, Shapefile.Polygon(Shapefile.Rect(0, 0, 1, 1), [1], [Shapefile.Point(1, 1)])) # add dummy shape for Unspecified

mkpath("output")

for i = 1:7 # age categories
    oneplusmaps = []
    fullmaps = []
    onepluscategorycounts = []
    fullcategorycounts = []

    for w ∈ weeks
        path = downloadweeklyreport(w)
        onepluspercent, fullpercent = loadweekdata(path)
        date = Date(w, DateFormat("U-d-y"))

        oneplusrisklevel = calculaterisklevels(onepluspercent)[:, i]
        ndims(oneplusrisklevel) == 1 || (oneplusrisklevel = dropdims(oneplusrisklevel, dims = 2))

        colors = [riskcolors[r] for r ∈ oneplusrisklevel] |> permutedims
        push!(oneplusmaps, plot(geoms, fillcolor=colors, linecolor=:gray75, linewidth=0.5, size=(1024,640), grid=false, showaxis=false, ticks=false, title="Massachusetts COVID-19 Vaccination Level (At Least One; $(agecat[i]))\n$(date)", labels=labels))
        savefig(joinpath("output", "$(w)-vaccine-oneplus_$(agecat[i]).png"))

        fullrisklevel = calculaterisklevels(fullpercent)[:, i]
        ndims(fullrisklevel) == 1 || (fullrisklevel = dropdims(fullrisklevel, dims = 2))
        colors = [riskcolors[r] for r ∈ fullrisklevel] |> permutedims
        push!(fullmaps, plot(geoms, fillcolor=colors, linecolor=:gray75, linewidth=0.5, size=(1024,640), grid=false, showaxis=false, ticks=false, title="Massachusetts COVID-19 Vaccination Level (Full; $(agecat[i]))\n$(date)", labels=labels))
        savefig(joinpath("output", "$(w)-vaccine-full_$(agecat[i]).png"))

        # calculate weighted categories and append them
        weightedcategorycounts = AbstractFloat[]
        for k ∈ keys(sort(riskcolors))
            push!(weightedcategorycounts, sum(pop2010[oneplusrisklevel[1:end - 1] .== k]))
        end
        weightedcategorycounts = permutedims(weightedcategorycounts)
        onepluscategorycounts = isempty(onepluscategorycounts) ? weightedcategorycounts : [onepluscategorycounts; weightedcategorycounts]

        # calculate weighted categories and append them
        fullweightedcategorycounts = AbstractFloat[]
        for k ∈ keys(sort(riskcolors))
            push!(fullweightedcategorycounts, sum(pop2010[fullrisklevel[1:end - 1] .== k]))
        end
        fullweightedcategorycounts = permutedims(fullweightedcategorycounts)
        fullcategorycounts = isempty(fullcategorycounts) ? fullweightedcategorycounts : [fullcategorycounts; fullweightedcategorycounts]
    end

    dates = Date.(weeks, DateFormat("U-d-y"))

    # State Animation
    anim = Plots.Animation()
    for i ∈ eachindex(weeks)
        plot(oneplusmaps[i])
        areaplot!(onepluscategorycounts[1:i,:], fillcolor=permutedims(collect(values(sort(riskcolors)))), linewidth=0, widen=false,
                        xaxis=((1,length(weeks)),30), xticks=(1:2:length(dates), dates[1:2:end]),
                        yaxis=("Population (millions)",), yformatter = x -> x / 1000000,
                        tick_direction=:in,
                        inset=(1, bbox(0.06, 0.1, 0.52, 0.3, :bottom)), subplot=2,
                        legend=:outerright, labels=permutedims(labels))
        Plots.frame(anim)
    end
    for i = 1:4 # insert 4 more of the same frame at end
        Plots.frame(anim)
    end
    gif(anim, joinpath("output", "animation_map_vaccine_oneplus_$(agecat[i]).gif"), fps = 1)
    savefig(joinpath("output", "current_week_map_vaccine_oneplus_$(agecat[i]).png"))

    anim = Plots.Animation()
    for i ∈ eachindex(weeks)
        plot(fullmaps[i])
        areaplot!(fullcategorycounts[1:i,:], fillcolor=permutedims(collect(values(sort(riskcolors)))), linewidth=0, widen=false,
                        xaxis=((1,length(weeks)),30), xticks=(1:2:length(dates), dates[1:2:end]),
                        yaxis=("Population (millions)",), yformatter = x -> x / 1000000,
                        tick_direction=:in,
                        inset=(1, bbox(0.06, 0.1, 0.52, 0.3, :bottom)), subplot=2,
                        legend=:outerright, labels=permutedims(labels))
        Plots.frame(anim)
    end
    for i = 1:4 # insert 4 more of the same frame at end
        Plots.frame(anim)
    end
    gif(anim, joinpath("output", "animation_map_vaccine_full_$(agecat[i]).gif"), fps = 1)
    savefig(joinpath("output", "current_week_map_vaccine_full_$(agecat[i]).png"))

end
