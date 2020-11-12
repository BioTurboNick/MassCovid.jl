using Shapefile
using Plots
using XLSX

function loadmapgeometry()
    path = joinpath("geodata", "TOWNSSURVEY_POLYM.shp")
    table = Shapefile.Table(path)
    sorted_order = sortperm(table.TOWN)
    geoms = Shapefile.shapes(table)[sorted_order]
end

function loadweekdata(datestring)
    # cache data
    path = download("https://www.mass.gov/doc/weekly-public-health-report-raw-data-$(datestring)-2020/download")
    data = XLSX.readxlsx(path)
    sheet = XLSX.hassheet(data, "City_town") ? data["City_town"] : data["City_Town_Data"]
    # sheet["C1"] == "Two Week Case Count" && sheet["D1"] == "Average Daily Incidence Rate per 100000"
    countsraw = sheet["C2:C352"]
    counts = [c == "<5" ? 2 : c for c ∈ countsraw] # replace "<5" with a number in range
    rates = sheet["D2:D352"]
    state_rate = sheet["D354"]
    return counts, rates, state_rate
end

function drawsavemap(datestring)
    counts, rates, state_rate = loadweekdata(datestring)

    risklevel = [r == 0 ? 0 :
                c == 2 ? 1 :
                r < 4 ? 2 :
                r < 8 ? 3 :
                r < 16 ? 4 :
                r < 32 ? 5 :
                r < 64 ? 6 : 7 for (c, r) ∈ zip(counts, rates)]

    riskcolors = Dict(0 => :gray95,
                      1 => :gray85,
                      2 => :limegreen,
                      3 => :yellow,
                      4 => :red,
                      5 => :red3,
                      6 => :darkred,
                      7 => :black)

    colors = [riskcolors[r] for r ∈ risklevel] |> permutedims

    plot(geoms, fillcolor=colors, linecolor=:gray75, linewidth=0.5, size=(1024,640), grid=false, showaxis=false, ticks=false)
    savefig(joinpath("output", "$(datestring).png"))
end

geoms = loadmapgeometry()

files = ["august-12",
         "august-19",
         "august-26",
         "september-2",
         "september-9",
         "september-16",
         "september-23",
         "september-30",
         "october-7",
         "october-14",
         "october-22",
         "october-29",
         "november-5"]

anim = Plots.Animation()
for f ∈ files
    drawsavemap(f)
    Plots.frame(anim)
end
for i = 1:5 # insert 4 more of the same frame at end
    drawsavemap(files[end])
    Plots.frame(anim)
end
gif(anim, joinpath("output", "mass-covid-map.gif"), fps = 1)
