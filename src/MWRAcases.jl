using Dates
using Downloads
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
    Downloads.download("https://www.mass.gov/doc/weekly-public-health-report-raw-data-$(datestring)/download", path)
end

function downloadweeklyreport2(datestring)
    path = joinpath("input","$(datestring).xlsx")
    ispath(path) && return path
    Downloads.download("https://www.mass.gov/doc/covid-19-raw-data-$(datestring)/download", path)
end

function loadweekdata(path, date)
    date == Date("november-12-2021", dateformat"U-d-yyyy") && (date = Date("november-11-2021", dateformat"U-d-yyyy"))
    date == Date("november-26-2021", dateformat"U-d-yyyy") && (date = Date("november-25-2021", dateformat"U-d-yyyy"))
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
        if !isnothing(unknowntown)
            deleteat!(daterows, unknowntown)
            deleteat!(names, unknowntown)
        end
        allmass = findfirst(==("All of Massachusetts"), names)
        if !isnothing(allmass)
            deleteat!(daterows, allmass)
            deleteat!(names, allmass)
        end

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

datefmt = dateformat"U-d-yyyy"
weeks = [Date("august-12-2020", datefmt):Day(7):Date("october-14-2020", datefmt);
         Date("october-22-2020", datefmt):Day(7):Date("november-19-2020", datefmt);
         Date("november-27-2020", datefmt);
         Date("december-3-2020", datefmt):Day(7):Date("november-4-2021", datefmt);
         Date("november-12-2021", datefmt);
         Date("november-18-2021", datefmt);
         Date("november-26-2021", datefmt);
         Date("december-2-2021", datefmt):Day(7):today()]

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


equity_towns = sort(["BROCKTON",
                    "CHELSEA",
                    "EVERETT",
                    "FALL RIVER",
                    "FITCHBURG",
                    "FRAMINGHAM",
                    "HAVERHILL",
                    "HOLYOKE",
                    "LAWRENCE",
                    "LEOMINSTER",
                    "LOWELL",
                    "LYNN",
                    "MALDEN",
                    "METHUEN",
                    "NEW BEDFORD",
                    "RANDOLPH",
                    "REVERE",
                    "SPRINGFIELD",
                    "WORCESTER"])


nonequity_towns = setdiff(towns, ["BOSTON", equity_towns])


mwra_indexes = indexin(mwra_towns, towns)
boston_index = indexin(["BOSTON"], towns)
mwra_north_indexes = indexin(mwra_north_towns, towns)
mwra_south_indexes = indexin(mwra_south_towns, towns)
other_indexes = indexin(other_towns, towns)
equity_indexes = indexin(equity_towns, towns)
nonequity_indexes = indexin(nonequity_towns, towns)

mwra_counts = []
boston_counts = []
mwra_north_counts = []
mwra_south_counts = []
other_counts = []
equity_counts = []
nonequity_counts = []
for w ∈ weeks
    weekstr = lowercase(Dates.format(w, datefmt))
    path = w ∈ weeks[1:22] ? downloadweeklyreport(weekstr) :
                             downloadweeklyreport2(weekstr)
    counts, rates, ppos = loadweekdata(path, w)

    push!(mwra_counts, sum(counts[mwra_indexes]))
    push!(boston_counts, sum(counts[boston_index]))
    push!(mwra_north_counts, sum(counts[mwra_north_indexes]))
    push!(mwra_south_counts, sum(counts[mwra_south_indexes]))
    push!(other_counts, sum(counts[other_indexes]))
    push!(equity_counts, sum(counts[equity_indexes]))
    push!(nonequity_counts, sum(counts[nonequity_indexes]))
end

plot([mwra_counts mwra_south_counts mwra_north_counts other_counts] ./ 2, labels = ["MWRA" "MWRA South" "MWRA North" "Non-MWRA"], lw = 3, yformatter=:plain,
     xaxis=((1,length(weeks)),30), xticks=(1:2:length(weeks), weeks[1:2:end]),
     ylabel="New cases/week", title="Massachusetts weekly cases by MWRA service area")
savefig(joinpath("output", "mwra_cases.png"))
plot([mwra_counts mwra_north_counts mwra_south_counts other_counts][(end - 12):end,:] ./ 2, labels = ["MWRA" "MWRA South" "MWRA North" "Non-MWRA"], lw = 3, yformatter=:plain,
     xaxis=((1,length(weeks[(end - 12):end])),30), xticks=(1:2:length(weeks[(end - 12):end]), weeks[(end - 12):2:end]),
     ylabel="New cases/week", title="Massachusetts weekly cases by MWRA service area", legend=:topleft)
savefig(joinpath("output", "mwra_cases_recent.png"))



# Polished version per 100k

boston_pop = sum(pop2010[boston_index])
mwra_north_pop = sum(pop2010[mwra_north_indexes]) - boston_pop
mwra_south_pop = sum(pop2010[mwra_south_indexes]) - boston_pop
other_pop = sum(pop2010[other_indexes])
equity_pop = sum(pop2010[equity_indexes])
nonequity_pop = sum(pop2010[nonequity_indexes])

mwra_north_counts .-= boston_counts
mwra_south_counts .-= boston_counts

boston_counts ./= boston_pop / 100_000
mwra_north_counts ./= mwra_north_pop / 100_000
mwra_south_counts ./= mwra_south_pop / 100_000
other_counts ./= other_pop / 100_000
equity_counts ./= equity_pop / 100_000
nonequity_counts ./= nonequity_pop / 100_000

plot([boston_counts mwra_south_counts mwra_north_counts other_counts] ./ 2, labels = ["Boston" "Greater Boston South" "Greater Boston North" "Outside Greater Boston"], lw = 3, yformatter=:plain,
     xaxis=((1,length(weeks)),30), xticks=(1:4:length(weeks), weeks[1:4:end]),
     ylabel="New cases/week", title="Massachusetts weekly cases by region\n per 100k")
#vline!([55], lw = 3, linecolor = :black, label = "2021 Boston Mask Mandate")
savefig(joinpath("output", "mwra_cases_pop_polished.png"))

plot([boston_counts mwra_north_counts mwra_south_counts other_counts][(end - 12):end,:] ./ 2, labels = ["Boston" "Greater Boston South" "Greater Boston North" "Outside Greater Boston"], lw = 3, yformatter=:plain,
     xaxis=((1,length(weeks[(end - 12):end])),30), xticks=(1:2:length(weeks[(end - 12):end]), weeks[(end - 12):2:end]),
     ylabel="New cases/week", title="Massachusetts weekly cases by region\n per 100k", legend=:topleft)
savefig(joinpath("output", "mwra_cases_pop_recent_polished.png"))

plot([boston_counts equity_counts nonequity_counts] ./ 2, labels = ["Boston" "Equity Communities" "Remaining Mass"], lw = 3, yformatter=:plain,
     xaxis=((1,length(weeks)),30), xticks=(1:4:length(weeks), weeks[1:4:end]),
     ylabel="New cases/week", title="Massachusetts weekly cases by region\n per 100k")
savefig(joinpath("output", "mwra_cases_pop_polished_equity.png"))

plot([boston_counts equity_counts nonequity_counts][(end - 12):end,:] ./ 2, labels = ["Boston" "Equity Communities" "Remaining Mass"], lw = 3, yformatter=:plain,
     xaxis=((1,length(weeks[(end - 12):end])),30), xticks=(1:2:length(weeks[(end - 12):end]), weeks[(end - 12):2:end]),
     ylabel="New cases/week", title="Massachusetts weekly cases by region\n per 100k", legend=:topleft)
savefig(joinpath("output", "mwra_cases_pop_equity_recent_polished.png"))
