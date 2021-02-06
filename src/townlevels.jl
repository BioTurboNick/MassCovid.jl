using Dates
using Shapefile
using Plots
using XLSX

#=

How have all the towns in MA progressed over time?

=#

function loadtowndata()
    path = joinpath("geodata", "TOWNSSURVEY_POLYM.shp")
    table = Shapefile.Table(path)
    sorted_order = sortperm(table.TOWN)
    geoms = Shapefile.shapes(table)[sorted_order]
    pop2010 = table.POP2010[sorted_order]
    townnames = table.TOWN[sorted_order]
    townnames, geoms, pop2010
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
        unknowntown = findfirst(x -> x ∈ ("Unknown town", "Unknown"), names)
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

townnames, geoms, pop2010 = loadtowndata()

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
         "january-14-2021",
         "january-21-2021",
         "january-28-2021",
         "february-4-2021"]

weekrates = []
for w ∈ weeks
    path = w ∈ weeks[1:22] ? downloadweeklyreport(w) :
                             downloadweeklyreport2(w)
    date = Date(w, DateFormat("U-d-y"))
    counts, rates = loadweekdata(path, date)
    rates[rates .== "<5"] .= 2
    push!(weekrates, rates |> vec .|> AbstractFloat)
end

upcat(x::AbstractArray) = reshape(vcat(x...), (size(x[1])..., size(x)...))

rates = weekrates |> upcat |> permutedims

maxrate = maximum(rates, dims = 1)

rates ./= maxrate

allplots = [plot(rates[:, i], linecolor=:red, legend=false, ticks=:none, title=(townnames[i], 4)) for i ∈ eachindex(pop2010)]

plot(allplots..., size=(2048,2048))
