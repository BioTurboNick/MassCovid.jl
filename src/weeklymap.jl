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
    path = joinpath("input","$(datestring).xlsx")
    ispath(path) && return path
    download("https://www.mass.gov/doc/weekly-public-health-report-raw-data-$(datestring)/download", path)
end

function downloadweeklyreport2(datestring)
    path = joinpath("input","$(datestring).xlsx")
    ispath(path) && return path
    download("https://www.mass.gov/doc/covid-19-raw-data-$(datestring)/download", path)
end

function loadweekdata(path, date)
    data = XLSX.readxlsx(path)

    if XLSX.hassheet(data, "Weekly_City_Town")
        sheet = data["Weekly_City_Town"]
        date_column = sheet["N1"] == "Report Date" ? "N" : "O" # they added a column
        dates = [zero(Date); Date.(sheet[date_column][2:end])] # first row is header
        daterows = findall(x -> x == date, dates)[1:end]
        names = sheet["A"][daterows]

        # remove "Unknown town"
        unknowntown = findfirst(x -> x == "Unknown town", names)
        isnothing(unknowntown) || popat!(daterows, unknowntown)

        countsraw = sheet["E"][daterows]
        rates = sheet["F"][daterows]
    else
        sheet = XLSX.hassheet(data, "City_town") ? data["City_town"] : data["City_Town_Data"]
        countsraw = sheet["C2:C352"]
        rates = sheet["D2:D352"]
    end
    counts = [c == "<5" ? 2 : c for c ∈ countsraw] # replace "<5" with a number in range
    
    return counts, rates
end

function calculaterisklevels(counts, rates)
    risklevel = [r == 0 ? 0 :
                 c == 2 ? 1 :
                 r < 4 ? 2 :
                 r < 8 ? 3 :
                 r < 16 ? 4 :
                 r < 32 ? 5 :
                 r < 64 ? 6 :
                 r < 128 ? 7 :
                 r < 256 ? 8 : 9 for (c, r) ∈ zip(counts, rates)]
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
         "november-5-2020",
         "november-12-2020",
         "november-19-2020",
         "november-27-2020",
         "december-3-2020",
         "december-10-2020",
         "december-17-2020",
         "december-24-2020",
         "december-31-2020",
         "january-7-2021",
         "january-14-2021"]

labels = ["0 total",
          "<5 total",
          "<4 /100k/day",
          "4-8 /100k/day",
          "8-16 /100k/day",
          "16-32 /100k/day",
          "32-64 /100k/day",
          "64-128 /100k/day",
          "128-256 /100k/day",
          ">256 /100k/day"]

riskcolors = Dict(0 => :gray95,
                  1 => :gray85,
                  2 => :limegreen,
                  3 => :yellow,
                  4 => :red,
                  5 => :red3,
                  6 => :darkred,
                  7 => :black,
                  8 => RGB(85/255,0,85/255), # dark purple
                  9 => :darkblue
                  )

maps = []
categorycounts = []

for w ∈ weeks
    path = w ∈ weeks[1:22] ? downloadweeklyreport(w) :
                             downloadweeklyreport2(w)
    date = Date(w, DateFormat("U-d-y"))
    counts, rates = loadweekdata(path, date)
    risklevel = calculaterisklevels(counts, rates)
    ndims(risklevel) == 1 || (risklevel = dropdims(risklevel, dims = 2))

    colors = [riskcolors[r] for r ∈ risklevel] |> permutedims
    push!(maps, plot(geoms, fillcolor=colors, linecolor=:gray75, linewidth=0.5, size=(1024,640), grid=false, showaxis=false, ticks=false, title="Massachusetts COVID-19 Risk Level\n[$(w)]", labels=labels))
    savefig(joinpath("output", "$(w).png"))

    # calculate weighted categories and append them
    weightedcategorycounts = AbstractFloat[]
    for k ∈ keys(sort(riskcolors))
        push!(weightedcategorycounts, sum(pop2010[risklevel .== k]))
    end
    weightedcategorycounts = permutedims(weightedcategorycounts)
    categorycounts = isempty(categorycounts) ? weightedcategorycounts : [categorycounts; weightedcategorycounts]
end

# State Animation
anim = Plots.Animation()
for i ∈ eachindex(weeks)
    plot(maps[i])
    areaplot!(categorycounts[1:i,:], fillcolor=permutedims(collect(values(sort(riskcolors)))), linewidth=0, widen=false,
                     xaxis=((1,length(weeks)),30), xticks=(eachindex(weeks),weeks),
                     inset=(1, bbox(0.06, 0.1, 0.52, 0.3, :bottom)), subplot=2,
                     title="By population", legend=:outerright, labels=permutedims(labels))
    Plots.frame(anim)
end
for i = 1:4 # insert 4 more of the same frame at end
    Plots.frame(anim)
end
gif(anim, joinpath("output", "mass-covid-map.gif"), fps = 1)
savefig(joinpath("output", "$(weeks[end])_and_graph.png"))
