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
    geoms, pop2010, table.TOWN[sorted_order]
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
        ppos_column = sheet["N1"] == "Report Date" ? "K" : "L" # they added a column
        dates = [zero(Date); Date.(filter(!ismissing, sheet[date_column][2:end]))] # first row is header, may be trailed by missing
        daterows = findall(x -> x == date, dates)[1:end]
        names = sheet["A"][daterows]

        # remove "Unknown town"
        unknowntown = findfirst(x -> x ∈ ("Unknown town", "Unknown"), names)
        isnothing(unknowntown) || popat!(daterows, unknowntown)

        countsraw = sheet["E"][daterows]
        rates = sheet["F"][daterows]
        ppos = sheet[ppos_column][daterows]
    else
        sheet = XLSX.hassheet(data, "City_town") ? data["City_town"] : data["City_Town_Data"]
        countsraw = sheet["C2:C352"]
        rates = sheet["D2:D352"]
        ppos = sheet["I2:I352"]
    end
    counts = [c == "<5" || 0 < c < 5 ? 2 : c for c ∈ countsraw] # replace "<5" with a number in range; or if state forgets to mask them.
    
    return counts, rates, ppos
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
                 r < 256 ? 8 :
                 r < 512 ? 9 : 10 for (c, r) ∈ zip(counts, rates)]
end

function calculatepposrisklevels(counts, ppos)
    pposrisklevel = [c == 0 ? 0 :
                     c < 5 ? 1 :
                     p < 0.004 ? 2 :
                     p < 0.008 ? 3 :
                     p < 0.016 ? 4 :
                     p < 0.032 ? 5 :
                     p < 0.064 ? 6 :
                     p < 0.128 ? 7 :
                     p < 0.256 ? 8 :
                     p < 0.512 ? 9 : 10 for (c, p) ∈ zip(counts, ppos)]
end

geoms, pop2010, towns = loadtowndata()

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
        "february-4-2021",
        "february-11-2021",
        "february-18-2021",
        "february-25-2021",
        "march-4-2021",
        "march-11-2021",
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
        "june-10-2021",
        "june-17-2021",
        "june-24-2021",
        "july-1-2021",
        "july-8-2021",
        "july-15-2021",
        "july-22-2021",
        "July-29-2021",
        "august-5-2021",
        "august-12-2021"]

mwra_towns = sort(["WILMINGTON",
                "BEDFORD",
                "BURLINGTON",
                "WOBURN",
                "READING",
                "WAKEFIELD",
                "STONEHAM",
                "WINCHESTER",
                "LEXINGTON",
                "ARLINGTON",
                "MEDFORD",
                "MELROSE",
                "MALDEN",
                "WALTHAM",
                "BELMONT",
                "SOMERVILLE",
                "EVERETT",
                "REVERE",
                "CHELSEA",
                "WINTHROP",
                "CAMBRIDGE",
                "WATERTOWN",
                "BOSTON",
                "NEWTON",
                "WELLESLEY",
                "NATICK",
                "FRAMINGHAM",
                "ASHLAND",
                "NEEDHAM",
                "BROOKLINE",
                "DEDHAM",
                "WESTWOOD",
                "NORWOOD",
                "WALPOLE",
                "MILTON",
                "CANTON",
                "STOUGHTON",
                "RANDOLPH",
                "QUINCY",
                "BRAINTREE",
                "HOLBROOK",
                "WEYMOUTH",
                "HINGHAM"])

mwra_north_towns = sort(["WILMINGTON",
                          "BEDFORD",
                          "BURLINGTON",
                          "WOBURN",
                          "READING",
                          "WAKEFIELD",
                        "STONEHAM",
                        "WINCHESTER",
                        "LEXINGTON",
                        "ARLINGTON",
                        "MEDFORD",
                        "MELROSE",
                        "MALDEN",
                        "WALTHAM",
                        "BELMONT",
                        "SOMERVILLE",
                        "EVERETT",
                        "REVERE",
                        "CHELSEA",
                        "WINTHROP",
                        "CAMBRIDGE",
                        "WATERTOWN",
                        "BOSTON",
                        "NEWTON",
                        "BROOKLINE"])

mwra_south_towns = sort(["BOSTON",
                        "NEWTON",
                        "WELLESLEY",
                        "NATICK",
                        "FRAMINGHAM",
                        "ASHLAND",
                        "NEEDHAM",
                        "BROOKLINE",
                        "DEDHAM",
                        "WESTWOOD",
                        "NORWOOD",
                        "WALPOLE",
                        "MILTON",
                        "CANTON",
                        "STOUGHTON",
                        "RANDOLPH",
                        "QUINCY",
                        "BRAINTREE",
                        "HOLBROOK",
                        "WEYMOUTH",
                        "HINGHAM"])

other_towns = setdiff(towns, mwra_towns)

mwra_indexes = indexin(mwra_towns, towns)
mwra_north_indexes = indexin(mwra_north_towns, towns)
mwra_south_indexes = indexin(mwra_south_towns, towns)
other_indexes = indexin(other_towns, towns)

dates = Date.(weeks, DateFormat("U-d-y"))

mwra_counts = []
mwra_north_counts = []
mwra_south_counts = []
other_counts = []
for w ∈ weeks
    path = w ∈ weeks[1:22] ? downloadweeklyreport(w) :
                             downloadweeklyreport2(w)
    date = Date(w, DateFormat("U-d-y"))
    counts, rates, ppos = loadweekdata(path, date)

    push!(mwra_counts, sum(counts[mwra_indexes]))
    push!(mwra_north_counts, sum(counts[mwra_north_indexes]))
    push!(mwra_south_counts, sum(counts[mwra_south_indexes]))
    push!(other_counts, sum(counts[other_indexes]))
end

plot([mwra_counts mwra_north_counts mwra_south_counts other_counts] ./ 2, labels = ["MWRA" "MWRA South" "MWRA North" "Non-MWRA"], lw = 3, yformatter=:plain,
     xaxis=((1,length(weeks)),30), xticks=(1:2:length(dates), dates[1:2:end]),
     ylabel="New cases/week", title="Massachusetts weekly cases by MWRA service area")
savefig(joinpath("output", "mwra_cases.png"))
plot([mwra_counts mwra_north_counts mwra_south_counts other_counts][(end - 12):end,:] ./ 2, labels = ["MWRA" "MWRA South" "MWRA North" "Non-MWRA"], lw = 3, yformatter=:plain,
     xaxis=((1,length(weeks[(end - 12):end])),30), xticks=(1:2:length(dates[(end - 12):end]), dates[(end - 12):2:end]),
     ylabel="New cases/week", title="Massachusetts weekly cases by MWRA service area")
savefig(joinpath("output", "mwra_cases_recent.png"))
