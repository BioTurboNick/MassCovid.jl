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
    path = joinpath("input","$(datestring).xlsx")
    ispath(path) && return path
    download("https://www.mass.gov/doc/weekly-public-health-report-raw-data-$(datestring)/download", path)
end

function loadweekdata(path)
    data = XLSX.readxlsx(path)
    sheet = XLSX.hassheet(data, "City_town") ? data["City_town"] : data["City_Town_Data"]
    countsraw = sheet["C2:C352"]
    counts = [c == "<5" ? 2 : c for c ∈ countsraw] # replace "<5" with a number in range
    rates = sheet["D2:D352"]
    state_rate = sheet["D354"]
    return counts, rates, state_rate
end

function calculaterisklevels(counts, rates)
    risklevel = [r == 0 ? 0 :
                 c == 2 ? 1 :
                 r < 4 ? 2 :
                 r < 8 ? 3 :
                 r < 16 ? 4 :
                 r < 32 ? 5 :
                 r < 64 ? 6 : 7 for (c, r) ∈ zip(counts, rates)]
end

geoms, pop2010 = loadtowndata()

weeks = ["august-12-2020",
         "august-19-2020",
         "august-26-2020",
         "september-2-2020",
         "september-9-2020",
         "september-16-2020",
         "september-23-2020",
         "september-30-2020",
         "october-7-2020",
         "october-14-2020",
         "october-22-2020",
         "october-29-2020",
         "november-5-2020"]

labels = ["0 total",
          "<5 total",
          "<4 /100k/day",
          "4-8 /100k/day",
          "8-16 /100k/day",
          "16-32 /100k/day",
          "32-64 /100k/day",
          ">64 /100k/day"]

riskcolors = Dict(0 => :gray95,
                  1 => :gray85,
                  2 => :limegreen,
                  3 => :yellow,
                  4 => :red,
                  5 => :red3,
                  6 => :darkred,
                  7 => :black)

maps = []
risklevelΔs = []
categorycounts = []

for w ∈ weeks
    path = downloadweeklyreport(w)
    counts, rates, state_rate = loadweekdata(path)
    risklevel = calculaterisklevels(counts, rates)

    colors = [riskcolors[r] for r ∈ risklevel] |> permutedims
    push!(maps, plot(geoms, fillcolor=colors, linecolor=:gray75, linewidth=0.5, size=(1024,640), grid=false, showaxis=false, ticks=false, title=w, labels=labels))
    savefig(joinpath("output", "$(w).png"))

    # calculate weighted categories and append them
    weightedcategorycounts = AbstractFloat[]
    for k ∈ keys(sort(riskcolors))
        push!(weightedcategorycounts, sum(pop2010[dropdims(risklevel, dims=2) .== k]))
    end
    weightedcategorycounts = permutedims(weightedcategorycounts)
    categorycounts = isempty(categorycounts) ? weightedcategorycounts : [categorycounts; weightedcategorycounts]
end

# State Animation
anim = Plots.Animation()
for i ∈ eachindex(weeks)
    plot(maps[i])
    areaplot!(categorycounts[1:i,:], fillcolor=permutedims(collect(values(sort(riskcolors)))), linewidth=0, widen=false,
                     xaxis=((1,length(weeks)),30), xticks=(1:13,weeks),
                     inset=(1, bbox(0.08, 0.1, 0.5, 0.3, :bottom)), subplot=2,
                     title="risk level by population", legend=:outerright, labels=permutedims(labels))
    plot!(size=(1024,640))
    Plots.frame(anim)
end
for i = 1:4 # insert 4 more of the same frame at end
    Plots.frame(anim)
end
gif(anim, joinpath("output", "mass-covid-map.gif"), fps = 1)
