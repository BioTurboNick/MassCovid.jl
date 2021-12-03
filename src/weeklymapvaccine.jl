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
    geoms, pop2010, table.TOWN
end

function downloadweeklyreport(datestring)
    path = joinpath("input","$(datestring)-vaccine.xlsx")
    ispath(path) && return path
    Downloads.download("https://www.mass.gov/doc/weekly-covid-19-municipality-vaccination-report-$(datestring)/download", path)
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

    sheet = XLSX.hassheet(data, "Age - municipality") ? data["Age - municipality"] : data["Age – municipality"]
    nrows ="5-11 Years" ∈ sheet["C"][3:end] ? 9 : "12-15 Years" ∈ sheet["C"][3:end] ? 8 : 7
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
    unmergetowns!(names, ages, pops, onepluspercent, fullpercent, "Granville", "Tolland", nrows)
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

    # remove Unspecified
    unknowntownstart = findfirst(==("Unspecified"), names)
    unknowntownend = findlast(==("Unspecified"), names)
    names = [names[1:unknowntownstart - 1]; names[unknowntownend + 1:end]]
    ages = [ages[1:unknowntownstart - 1]; ages[unknowntownend + 1:end]]
    pops = [pops[1:unknowntownstart - 1]; pops[unknowntownend + 1:end]]
    onepluspercent = [onepluspercent[1:unknowntownstart - 1]; onepluspercent[unknowntownend + 1:end]]
    fullpercent = [fullpercent[1:unknowntownstart - 1]; fullpercent[unknowntownend + 1:end]]
    

    # put 5-11 and 12-15 and 16-19 back into 0-19
    @views if any(==(8), ages)
        shape = (nrows, length(pops) ÷ nrows)
        pops = reshape(pops, shape)
        childpop = pops[end,:] .- sum(pops[end-5:end-1,:], dims = 1)'
        onepluspercentr = reshape(onepluspercent, shape)
        fullpercentr = reshape(fullpercent, shape)
        oneplussum = zeros(size(pops, 2))
        fullsum = zeros(size(pops, 2))
        for i ∈ 1:size(pops, 1) - 6
            oneplussum .+= pops[i,:] .* onepluspercentr[i,:]
            fullsum .+= pops[i,:] .* fullpercentr[i,:]
        end
        onepluspercentr[end-6,:] = oneplussum ./ childpop
        fullpercentr[end-6,:] = fullsum ./ childpop
        onepluspercent = vec(onepluspercentr[end-6:end,:])
        fullpercent = vec(fullpercentr[end-6:end,:])
    end

    # dim 1 = town, dim 2 = age range
    onepluspercent = permutedims(reshape(onepluspercent, (7, 351)), (2, 1))
    fullpercent = permutedims(reshape(fullpercent, (7, 351)), (2, 1))
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

datefmt = dateformat"U-d-yyyy"
weeks = Date("march-11-2021", datefmt):Day(7):today()

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

mkpath("output")


oneplusmaps = AbstractArray[[], [], [], [], [], [], []]
fullmaps = AbstractArray[[], [], [], [], [], [], []]
onepluscategorycounts = AbstractArray[[], [], [], [], [], [], []]
fullcategorycounts = AbstractArray[[], [], [], [], [], [], []]

for w ∈ weeks
    println(w)
    weekstr = lowercase(Dates.format(w, datefmt))
    path = downloadweeklyreport(weekstr)
    onepluspercent, fullpercent = loadweekdata(path)
    for i = 1:7 # age categories
        oneplusrisklevel = calculaterisklevels(onepluspercent)[:, i]
        ndims(oneplusrisklevel) == 1 || (oneplusrisklevel = dropdims(oneplusrisklevel, dims = 2))

        colors = [riskcolors[r] for r ∈ oneplusrisklevel] |> permutedims
        push!(oneplusmaps[i], plot(geoms, fillcolor=colors, linecolor=:gray75, linewidth=0.5, size=(1024,640), grid=false, showaxis=false, ticks=false, title="Massachusetts COVID-19 Vaccination Level (At Least One; $(agecat[i]))\n$(w)", labels=labels))
        savefig(joinpath("output", "$(weekstr)-vaccine-oneplus_$(agecat[i]).png"))

        fullrisklevel = calculaterisklevels(fullpercent)[:, i]
        ndims(fullrisklevel) == 1 || (fullrisklevel = dropdims(fullrisklevel, dims = 2))
        colors = [riskcolors[r] for r ∈ fullrisklevel] |> permutedims
        push!(fullmaps[i], plot(geoms, fillcolor=colors, linecolor=:gray75, linewidth=0.5, size=(1024,640), grid=false, showaxis=false, ticks=false, title="Massachusetts COVID-19 Vaccination Level (Full; $(agecat[i]))\n$(w)", labels=labels))
        savefig(joinpath("output", "$(weekstr)-vaccine-full_$(agecat[i]).png"))

        # calculate weighted categories and append them
        weightedcategorycounts = AbstractFloat[]
        for k ∈ keys(sort(riskcolors))
            push!(weightedcategorycounts, sum(pop2010[oneplusrisklevel[1:end] .== k]))
        end
        weightedcategorycounts = permutedims(weightedcategorycounts)
        onepluscategorycounts[i] = isempty(onepluscategorycounts[i]) ? weightedcategorycounts : [onepluscategorycounts[i]; weightedcategorycounts]

        # calculate weighted categories and append them
        fullweightedcategorycounts = AbstractFloat[]
        for k ∈ keys(sort(riskcolors))
            push!(fullweightedcategorycounts, sum(pop2010[fullrisklevel[1:end] .== k]))
        end
        fullweightedcategorycounts = permutedims(fullweightedcategorycounts)
        fullcategorycounts[i] = isempty(fullcategorycounts[i]) ? fullweightedcategorycounts : [fullcategorycounts[i]; fullweightedcategorycounts]
    end
end
for j ∈ 1:7 # ages
    # State Animation
    anim = Plots.Animation()
    for i ∈ eachindex(weeks)
        plot(oneplusmaps[j][i])
        areaplot!(onepluscategorycounts[j][1:i,:], fillcolor=permutedims(collect(values(sort(riskcolors)))), linewidth=0, widen=false,
                        xaxis=((1,length(weeks)),30), xticks=(1:3:length(weeks), weeks[1:3:end]),
                        yaxis=("Population (millions)",), yformatter = x -> x / 1000000,
                        tick_direction=:in,
                        inset=(1, bbox(0.06, 0.1, 0.52, 0.3, :bottom)), subplot=2,
                        legend=:outerright, labels=permutedims(labels))
        Plots.frame(anim)
    end
    for i = 1:4 # insert 4 more of the same frame at end
        Plots.frame(anim)
    end
    gif(anim, joinpath("output", "animation_map_vaccine_oneplus_$(agecat[j]).gif"), fps = 1)
    savefig(joinpath("output", "current_week_map_vaccine_oneplus_$(agecat[j]).png"))

    anim = Plots.Animation()
    for i ∈ eachindex(weeks)
        plot(fullmaps[j][i])
        areaplot!(fullcategorycounts[j][1:i,:], fillcolor=permutedims(collect(values(sort(riskcolors)))), linewidth=0, widen=false,
                        xaxis=((1,length(weeks)),30), xticks=(1:3:length(weeks), weeks[1:3:end]),
                        yaxis=("Population (millions)",), yformatter = x -> x / 1000000,
                        tick_direction=:in,
                        inset=(1, bbox(0.06, 0.1, 0.52, 0.3, :bottom)), subplot=2,
                        legend=:outerright, labels=permutedims(labels))
        Plots.frame(anim)
    end
    for i = 1:4 # insert 4 more of the same frame at end
        Plots.frame(anim)
    end
    gif(anim, joinpath("output", "animation_map_vaccine_full_$(agecat[j]).gif"), fps = 1)
    savefig(joinpath("output", "current_week_map_vaccine_full_$(agecat[j]).png"))

end
