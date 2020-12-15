using Shapefile
using Plots
using XLSX

#=

What effect did not moving to Phase 3 Step 2 have?

What effect did rolling back to Phase 3 Step 1 have?

=#

function loadtowndata()
    path = joinpath("geodata", "TOWNSSURVEY_POLYM.shp")
    table = Shapefile.Table(path)
    sorted_order = sortperm(table.TOWN)
    geoms = Shapefile.shapes(table)[sorted_order]
    pop2010 = table.POP2010[sorted_order]
    table.TOWN[sorted_order], geoms, pop2010
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
    ratesraw = sheet["D2:D352"]
    rates = [c == "<5" ? 0.1 : c for c ∈ ratesraw] # replace "<5" with a number in range
    state_rate = sheet["D354"]
    return counts, rates, state_rate
end

names, geoms, pop2010 = loadtowndata()

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
         "december-3-2020"]

week_restricted = Dict(["ATTLEBORO" => 1,
                        "AVON" => 1,
                        "BOSTON" => 1,
                        "CHELSEA" => 1,
                        "DRACUT" => 1,
                        "EVERETT" => 1,
                        "FRAMINGHAM" => 1,
                        "HAVERHILL" => 1,
                        "HOLLISTON" => 1,
                        "LAWRENCE" => 1,
                        "LOWELL" => 1,
                        "LYNN" => 1,
                        "LYNNFIELD" => 1,
                        "MARLBOROUGH" => 1,
                        "METHUEN" => 1,
                        "MIDDLETON" => 1,
                        "NANTUCKET" => 1,
                        "NEW BEDFORD" => 1,
                        "NORTH ANDOVER" => 1,
                        "REVERE" => 1,
                        "SAUGUS" => 1,
                        "SPRINGFIELD" => 1,
                        "WINTHROP" => 1,
                        "WORCESTER" => 1,
                        "WRENTHAM" => 1,
                        "TYNGSBOROUGH" => 2,
                        "ACUSHNET" => 3,
                        "BROCKTON" => 3,
                        "CHELMSFORD" => 3,
                        "HOLYOKE" => 3,
                        "HUDSON" => 3,
                        "KINGSTON" => 3,
                        "LEICESTER" => 3,
                        "MALDEN" => 3,
                        "PLYMOUTH" => 3,
                        "RANDOLPH" => 3,
                        "WALTHAM" => 3,
                        "WEBSTER" => 3,
                        "WOBURN" => 3,
                        "ABINGTON" => 4,
                        "BERKLEY" => 4,
                        "CANTON" => 4,
                        "EAST LONGMEADOW" => 4,
                        "FAIRHAVEN" => 4,
                        "FALL RIVER" => 4,
                        "HANOVER" => 4,
                        "HANSON" => 4,
                        "HINGHAM" => 4,
                        "MARSHFIELD" => 4,
                        "MILFORD" => 4,
                        "PEMBROKE" => 4,
                        "ROCKLAND" => 4,
                        "WAKEFIELD" => 4,
                        "WEYMOUTH" => 4,
                        "FITCHBURG" => 5
                   ])

reopened_nov_19 = ["AVON", "BERKLEY", "BOSTON", "CANTON", "CHELMSFORD", "EAST LONGMEADOW",
                   "HANOVER", "HANSON", "HAVERHILL", "HINGHAM", "HOLLISTON", "HUDSON",
                   "KINGSTON", "LEICESTER", "LYNNFIELD", "MARLBOROUGH", "MARSHFIELD",
                   "MIDDLETON", "NORTH ANDOVER", "PEMBROKE", "PLYMOUTH", "RANDOLPH",
                   "WAKEFIELD", "WALTHAM", "WEBSTER", "WEYMOUTH", "WINTHROP", "WORCESTER",
                   "WRENTHAM"]

week_offset = 9 # index of Oct 7

# make sure I didn't make a mistake
for name ∈ keys(week_restricted)
    @assert name ∈ names "$(name) not in names"
end
for name ∈ reopened_nov_19
    @assert name ∈ names "$(name) not in names"
end

# collect those that never went to Phase 3 Step 2
never_entered_p3s2 = filter(n -> haskey(week_restricted, n) && week_restricted[n] == 1, names)

rolled_back = filter(n -> haskey(week_restricted, n) && week_restricted[n] > 1, names)

stayed_in = filter(n -> !haskey(week_restricted, n), names)

weekrates = []
for w ∈ weeks
    path = downloadweeklyreport(w)
    counts, rates, state_rate = loadweekdata(path)
    push!(weekrates, rates)
end

never_entered_p3s2_rates = []
for name ∈ never_entered_p3s2
    i = findfirst(x -> x == name, names)
    townrates = [weekrates[j][i] for j ∈ eachindex(weeks)]
    push!(never_entered_p3s2_rates, townrates)
end

rolled_back_rates = []
for name ∈ rolled_back
    i = findfirst(x -> x == name, names)
    townrates = [weekrates[j][i] for j ∈ eachindex(weeks)]
    push!(rolled_back_rates, townrates)
end

rolled_back_rates_offset = []
rolled_back_rates_indexes = []
for name ∈ rolled_back
    i = findfirst(x -> x == name, names)
    townrates = [weekrates[j][i] for j ∈ eachindex(weeks)]
    weekindexes = eachindex(weeks) .- week_offset .+ week_restricted[name]
    push!(rolled_back_rates_offset, townrates)
    push!(rolled_back_rates_indexes, weekindexes)
end

stayed_in_rates = []
for name ∈ stayed_in
    i = findfirst(x -> x == name, names)
    townrates = [weekrates[j][i] for j ∈ eachindex(weeks)]
    push!(stayed_in_rates, townrates)
end

p1 = plot(never_entered_p3s2_rates, linecolor=:red, xaxis=((1,length(weeks)),30), xticks=(eachindex(weeks),weeks), legend=false, alpha=0.5, title="Towns that never entered 3.2")
p2 = plot(rolled_back_rates, linecolor=:orange, xaxis=((1,length(weeks)),30), xticks=(eachindex(weeks),weeks), legend=false, alpha=0.5, title="Towns that rolled back from 3.2")
p3 = plot(rolled_back_rates_indexes, rolled_back_rates_offset, linecolor=:black, legend=false, alpha=0.5, title="Towns that rolled back from 3.2, 0 = rollback week")
p4 = plot(stayed_in_rates, linecolor=:green, xaxis=((1,length(weeks)),30), xticks=(eachindex(weeks),weeks), legend=false, alpha=0.5, title="Towns that stayed in 3.2")

plot(p1, p2, p3, p4, layout=grid(4,1), size=(512,1024))
savefig(joinpath("output", "3_2_rollback.png"))
