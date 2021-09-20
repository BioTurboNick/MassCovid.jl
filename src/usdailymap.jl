using DataFrames
using Dates
using Shapefile
using Plots
using XLSX
using CSV
using Missings
using Smoothers
using Statistics
using InvertedIndices
using Unicode

statefp_name_dict = Dict(
    1 => "Alabama",
    2 => "Alaska",
    4 => "Arizona",
    5 => "Arkansas",
    6 => "California",
    8 => "Colorado",
    9 => "Connecticut",
    10 => "Delaware",
    11 => "District of Columbia",
    12 => "Florida",
    13 => "Georgia",
    15 => "Hawaii",
    16 => "Idaho",
    17 => "Illinois",
    18 => "Indiana",
    19 => "Iowa",
    20 => "Kansas",
    21 => "Kentucky",
    22 => "Louisiana",
    23 => "Maine",
    24 => "Maryland",
    25 => "Massachusetts",
    26 => "Michigan",
    27 => "Minnesota",
    28 => "Mississippi",
    29 => "Missouri",
    30 => "Montana",
    31 => "Nebraska",
    32 => "Nevada",
    33 => "New Hampshire",
    34 => "New Jersey",
    35 => "New Mexico",
    36 => "New York",
    37 => "North Carolina",
    38 => "North Dakota",
    39 => "Ohio",
    40 => "Oklahoma",
    41 => "Oregon",
    42 => "Pennsylvania",
    44 => "Rhode Island",
    45 => "South Carolina",
    46 => "South Dakota",
    47 => "Tennessee",
    48 => "Texas",
    49 => "Utah",
    50 => "Vermont",
    51 => "Virginia",
    53 => "Washington",
    54 => "West Virginia",
    55 => "Wisconsin",
    56 => "Wyoming",
    72 => "Puerto Rico"
)

function downloadcountycasedata()
    path = joinpath("input", "time_series_covid19_confirmed_US.csv")
    download("https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_US.csv", path)
end

function loadcountydata()
    jhudata = CSV.read(downloadcountycasedata(), DataFrame)
    admin2 = Missings.replace(jhudata[!, :Admin2], "")

    poppath = joinpath("input", "co-est2019-alldata.csv")
    popdata = CSV.read(poppath, DataFrame)
    popdata[popdata[!, :CTYNAME] .== "Do\xf1a Ana County", :CTYNAME] .= "Dona Ana County"
    popdata[!, :CTYNAME] = replace.(popdata[!, :CTYNAME], " County" => "") # trim suffixes
    popdata[!, :CTYNAME] = replace.(popdata[!, :CTYNAME], " Census Area" => "")
    popdata[!, :CTYNAME] = replace.(popdata[!, :CTYNAME], " Borough" => "")
    popdata[!, :CTYNAME] = replace.(popdata[!, :CTYNAME], " Parish" => "")
    popdata[!, :CTYNAME] = replace.(popdata[!, :CTYNAME], " City and" => "")
    popdata[!, :CTYNAME] = replace.(popdata[!, :CTYNAME], " Municipality" => "")
    popdata[!, :CTYNAME] = replace.(popdata[!, :CTYNAME], " city" => " City")
    # deal with "City" suffix
    cityrows = findall(endswith.(popdata[!,:CTYNAME], " City"))
    citynames = popdata[cityrows, :CTYNAME]
    citynamesappend = deepcopy(citynames)
    citynames[endswith.(citynames, " City")] .= replace.(citynames[endswith.(citynames, " City")], " City" => "")
    citynamesappend[.!endswith.(citynamesappend, " City")] = citynamesappend[.!endswith.(citynamesappend, " City")] .* " City"
    popdata[cityrows[citynamesappend .∈ Ref(admin2)], :CTYNAME] .= citynamesappend[citynamesappend .∈ Ref(admin2)]
    popdata[cityrows[citynamesappend .∉ Ref(admin2)], :CTYNAME] .= citynames[citynamesappend .∉ Ref(admin2)]
    data = outerjoin(jhudata, popdata, on = [:Province_State => :STNAME, :Admin2 => :CTYNAME], matchmissing = :equal)

    shapepath = joinpath("usgeodata", "cb_2018_us_county_5m.shp")
    shpdata = DataFrame(Shapefile.Table(shapepath))
    shpdata[!, :NAME] .= Unicode.normalize.(shpdata[!, :NAME], stripmark = true)
    # deal with "City" suffix
    cityrows = findall(parse.(Int, shpdata[!, :COUNTYFP]) .>= 500)
    citynames = shpdata[cityrows, :NAME]
    citynamesappend = deepcopy(citynames)
    citynames[endswith.(citynames, " City")] .= replace.(citynames[endswith.(citynames, " City")], " City" => "")
    citynamesappend[.!endswith.(citynamesappend, " City")] = citynamesappend[.!endswith.(citynamesappend, " City")] .* " City"
    shpdata[cityrows[citynamesappend .∈ Ref(admin2)], :NAME] .= citynamesappend[citynamesappend .∈ Ref(admin2)]
    shpdata[cityrows[citynamesappend .∉ Ref(admin2)], :NAME] .= citynames[citynamesappend .∉ Ref(admin2)]
    shpdata[!, :STNAME] .= [haskey(statefp_name_dict, x) ? statefp_name_dict[x] : missing for x ∈ parse.(Int, shpdata[!, :STATEFP])]

    data = outerjoin(data, shpdata, on = [:Province_State => :STNAME, :Admin2 => :NAME], matchmissing = :equal)
    return data
end

selectcounty(data, statename, countyname) =
    findall((data[!, :Province_State] .== statename) .& (Missings.replace(data[!, :COUNTY], -1) .!= 0) .& (data[!, :Admin2] .== countyname))

selectcounties(data, statename, countynames) =
    findall((data[!, :Province_State] .== statename) .& (Missings.replace(data[!, :COUNTY], -1) .!= 0) .& (data[!, :Admin2] .∈ Ref(countynames)))

selectstate(data, statename) =
    findall((data[!, :Province_State] .== statename) .& (Missings.replace(data[!, :COUNTY], -1) .== 0) .& (data[!, :Admin2] .== statename))

selectstatecounties(data, statename) =
    findall((data[!, :Province_State] .== statename) .& (Missings.replace(data[!, :COUNTY], -1) .!= 0))

getstatepop(data, statename) =
    data[selectstate(data, statename), :POPESTIMATE2019] |> only

getcountypop(data, statename, countyname) =
    data[selectcounty(data, statename, countyname), :POPESTIMATE2019] |> only

addcountycases!(data, statename, destcountyname, sourceselector, statepop, datarange) =
    data[selectcounty(data, statename, destcountyname), datarange] .= 
        data[selectcounty(data, statename, destcountyname), datarange] .+
        round.(data[sourceselector, datarange] .* getcountypop(data, statename, destcountyname) ./ statepop)

function preparedata!(data, datarange)
    # The JHU dataset combines some counties. We need to reassign the data to the actual counties.
    
    # Remove island territories and corrections
    filter!(:Province_State => !ismissing, data)
    filter!(:Admin2 => !ismissing, data)
    filter!(:Admin2 => x -> !contains(x, "Correct"), data)

    # set missings to 0
    for row ∈ eachrow(data[!, datarange])
        row .= collect(Missings.replace(row, 0))
    end

    # Alaska
    akpop = getstatepop(data, "Alaska")
    data[selectcounty(data, "Alaska", "Valdez-Cordova"), datarange] .+=
        data[selectcounty(data, "Alaska", "Chugach"), datarange] .+
        data[selectcounty(data, "Alaska", "Copper River"), datarange]
    akbblprow = selectcounty(data, "Alaska", "Bristol Bay plus Lake and Peninsula") # Bristol Bay, Lake and Peninsula
    addcountycases!(data, "Alaska", "Bristol Bay", akbblprow, akpop, datarange)
    addcountycases!(data, "Alaska", "Lake and Peninsula", akbblprow, akpop, datarange)
    delete!(data, selectcounties(data, "Alaska", ["Bristol Bay plus Lake and Peninsula", "Chugach", "Copper River"]))

    # Massachusetts
    mapop = getstatepop(data, "Massachusetts")
    madnrow = selectcounty(data, "Massachusetts", "Dukes and Nantucket") # Dukes, Nantucket
    addcountycases!(data, "Massachusetts", "Dukes", madnrow, mapop, datarange)
    addcountycases!(data, "Massachusetts", "Nantucket", madnrow, mapop, datarange)
    delete!(data, madnrow)

    # Missouri
    mopop = getstatepop(data, "Missouri")
    mokcrow = selectcounty(data, "Missouri", "Kansas City") # split between overlapping counties Jackson, Clay, Cass, Platte
    addcountycases!(data, "Missouri", "Jackson", mokcrow, mopop, datarange)
    addcountycases!(data, "Missouri", "Clay", mokcrow, mopop, datarange)
    addcountycases!(data, "Missouri", "Cass", mokcrow, mopop, datarange)
    addcountycases!(data, "Missouri", "Platte", mokcrow, mopop, datarange)
    delete!(data, mokcrow)

    # Utah
    utpop = getstatepop(data, "Utah")
    utbearriverrow = selectcounty(data, "Utah", "Bear River") # Rich, Cache, Box Elder
    addcountycases!(data, "Utah", "Rich", utbearriverrow, utpop, datarange)
    addcountycases!(data, "Utah", "Cache", utbearriverrow, utpop, datarange)
    addcountycases!(data, "Utah", "Box Elder", utbearriverrow, utpop, datarange)
    utcentralrow = selectcounty(data, "Utah", "Central Utah") # Piute, Wayne, Millard, Sevier, Sanpete, Juab
    addcountycases!(data, "Utah", "Piute", utcentralrow, utpop, datarange)
    addcountycases!(data, "Utah", "Wayne", utcentralrow, utpop, datarange)
    addcountycases!(data, "Utah", "Millard", utcentralrow, utpop, datarange)
    addcountycases!(data, "Utah", "Sevier", utcentralrow, utpop, datarange)
    addcountycases!(data, "Utah", "Sanpete", utcentralrow, utpop, datarange)
    addcountycases!(data, "Utah", "Juab", utcentralrow, utpop, datarange)
    utsoutheastrow = selectcounty(data, "Utah", "Southeast Utah") # Emery, Grand, Carbon
    addcountycases!(data, "Utah", "Emery", utsoutheastrow, utpop, datarange)
    addcountycases!(data, "Utah", "Grand", utsoutheastrow, utpop, datarange)
    addcountycases!(data, "Utah", "Carbon", utsoutheastrow, utpop, datarange)
    utsouthwestrow = selectcounty(data, "Utah", "Southwest Utah") # Iron, Beaver, Garfield, Washington, Kane
    addcountycases!(data, "Utah", "Iron", utsouthwestrow, utpop, datarange)
    addcountycases!(data, "Utah", "Beaver", utsouthwestrow, utpop, datarange)
    addcountycases!(data, "Utah", "Garfield", utsouthwestrow, utpop, datarange)
    addcountycases!(data, "Utah", "Washington", utsouthwestrow, utpop, datarange)
    addcountycases!(data, "Utah", "Kane", utsouthwestrow, utpop, datarange)
    uttricountyrow = selectcounty(data, "Utah", "TriCounty") # Uintah, Daggett, Duchesne
    addcountycases!(data, "Utah", "Uintah", uttricountyrow, utpop, datarange)
    addcountycases!(data, "Utah", "Daggett", uttricountyrow, utpop, datarange)
    addcountycases!(data, "Utah", "Duchesne", uttricountyrow, utpop, datarange)
    utwebermorganrow = selectcounty(data, "Utah", "Weber-Morgan") # Weber, Morgan
    addcountycases!(data, "Utah", "Weber", utwebermorganrow, utpop, datarange)
    addcountycases!(data, "Utah", "Morgan", utwebermorganrow, utpop, datarange)
    delete!(data, selectcounties(data, "Utah", ["Bear River", "Central Utah", "Southeast Utah", "Southwest Utah", "TriCounty", "Weber-Morgan"]))

    # remove "Out of" rows which have no data
    filter!(:Admin2 => x -> !startswith(x, "Out of"), data)

    # Process unassigned
    for statename ∈ unique(data[!, :Province_State])
        if statename == "Puerto Rico" 
            # skip until I can integrate its county populations
            delete!(data, selectstatecounties(data, statename))
            delete!(data, selectstate(data, statename))
            continue
        end
        statepop = getstatepop(data, statename)
        stateunassignedrow = selectcounty(data, statename, "Unassigned")
        for countyname ∈ data[selectstatecounties(data, statename), :Admin2]
            countyname != "Unassigned" || continue
            addcountycases!(data, statename, countyname, stateunassignedrow, statepop, datarange)
        end
        delete!(data, selectcounty(data, statename, "Unassigned"))
        delete!(data, selectstate(data, statename))
    end
    
    return nothing
end

data = loadcountydata()
colnames = propertynames(data)
datarange = findfirst(==(Symbol("1/22/20")), colnames):findfirst(==(:SUMLEV), colnames) - 1
preparedata!(data, datarange)

series = Array{Float64, 2}(data[!, datarange])
series = diff(series, dims = 2)
series ./= data[!, :POPESTIMATE2019]
fixspikes!(data, series)


function fixspikes!(data, series)
    countyfix!(data, series, "Alabama", 118, [12])
    countyfix!(data, series, "Alabama", 192, [49])
    countyfix!(data, series, "Alabama", 198, [13, 49, 65])
    countyfix!(data, series, "Alabama", 200, [13, 49, 65])
    countyfix!(data, series, "Alabama", 212, [31, 34, 35])
    countyfix!(data, series, "Alabama", 246, [63])
    countyfix!(data, series, "Alabama", 254, [31, 34, 35])
    countyfix!(data, series, "Alabama", 260, [46])
    countyfix!(data, series, "Alabama", 274, [49, 65])
    countyfix!(data, series, "Alabama", 275, [8, 31, 34, 35])
    countyfix!(data, series, "Alabama", 282, [20])
    countyfix!(data, series, "Alabama", 283, [17, 30, 39])
    countyfix!(data, series, "Alabama", 313, [17])
    statefix!(data, series, "Alabama", 325)
    countyfix!(data, series, "Alabama", 328, [7])
    countyfix!(data, series, "Alabama", 366, [62])
    countyfix!(data, series, "Alabama", 378, [53])
    countyfix!(data, series, "Alabama", 382, 384, [53])
    statefix!(data, series, "Alabama", 386)
    countyfix!(data, series, "Alabama", 396, [46])
    countyfix!(data, series, "Alabama", 399, 400, [46])
    countyfix!(data, series, "Alabama", 406, [5, 7, 8, 15, 22, 25, 28, 36, 43, 44, 48, 58, 59, 67])
    statefix!(data, series, "Alabama", 418)
    countyfix!(data, series, "Alabama", 447, [49])
    countyfix!(data, series, "Alabama", 454, [49])
    countyfix!(data, series, "Alabama", 470, [44, 59])
    statefix!(data, series, "Alabama", 478)
    countyfix!(data, series, "Alabama", 477, [10])

    countyfix!(data, series, "Alaska", 180, [2, 6, 11])
    countyfix!(data, series, "Alaska", 318, [10])
    statefix!(data, series, "Alaska", 346)
    countyfix!(data, series, "Alaska", 349, [23, 29])
    countyfix!(data, series, "Alaska", 355, [29])
    countyfix!(data, series, "Alaska", 462, [23])
    countyfix!(data, series, "Alaska", 478, [27])
    countyfix!(data, series, "Alaska", 513, [27])
    countyfix!(data, series, "Alaska", 518, [24, 27])

    statefix!(data, series, "Arizona", 216)
    countyfix!(data, series, "Arizona", 216, 217, [13])
    countyfix!(data, series, "Arizona", 218, [12])
    countyfix!(data, series, "Arizona", 328, [15])
    countyfix!(data, series, "Arizona", 327, 328, [15])
    countyfix!(data, series, "Arizona", 409, [15])
    countyfix!(data, series, "Arizona", 408, [1, 10, 14])
    countyfix!(data, series, "Arizona", 409, [14])
    countyfix!(data, series, "Arizona", 409, 410, [7])
    countyfix!(data, series, "Arizona", 413, [10])
    countyfix!(data, series, "Arizona", 415, [10])
    statefix!(data, series, "Arizona", 421)
    statefix!(data, series, "Arizona", 423)
    statefix!(data, series, "Arizona", 434)
    countyfix!(data, series, "Arizona", 443, [2, 4, 5, 10])
    
    statefix!(data, series, "Arkansas", 206)
    countyfix!(data, series, "Arkansas", 386, [71])
    statefix!(data, series, "Arkansas", 403, 404)
    statefix!(data, series, "Arkansas", 428)

    statefix!(data, series, "California", 307)
    countyfix!(data, series, "California", 315, [28])
    statefix!(data, series, "California", 343, 344)
    statefix!(data, series, "California", 524)
    statefix!(data, series, "California", 536)
end

seriesavg = hcat(sma.(eachrow(series), 7)...)
seriesavg ./= maximum(seriesavg, dims = 1)




# adjust for data jumps
function countyfix!(data, series, statename, dayindex, counties)
    selector = selectstatecounties(data, statename)[counties]
    series[selector, [dayindex;]] .= mean(series[selector, [dayindex - 1, dayindex + 1]], dims = 2)
end
function countyfix!(data, series, statename, startindex, stopindex, counties)
    selector = selectstatecounties(data, statename)[counties]
    range = startindex:stopindex
    series[selector, range] .= mean(series[selector, [startindex - 1, stopindex + 1]], dims = 2)
end
function statefix!(data, series, statename, start, stop)
    selector = selectstatecounties(data, statename)
    range = start:stop
    series[selector, range] .= mean(series[selector, [start - 1, stop + 1]], dims = 2)
end
function statefix!(data, series, statename, dayindex)
    selector = selectstatecounties(data, statename)
    series[selector, [dayindex;]] .= mean(series[selector, [dayindex - 1, dayindex + 1]], dims = 2)
end
countyfix!(multidayaverages, stateids, CALIFORNIA, 519, 525, [10, 12, 16, 38, 41, 43, 45, 49, 57])
countyfix!(multidayaverages, stateids, CALIFORNIA, 305, 305, [23])
countyfix!(multidayaverages, stateids, CALIFORNIA, 312, 312, [23])
countyfix!(multidayaverages, stateids, CALIFORNIA, 326, 326, [23])
countyfix!(multidayaverages, stateids, CALIFORNIA, 328, 328, [55])
countyfix!(multidayaverages, stateids, CALIFORNIA, 519, 525, [13])
countyfix!(multidayaverages, stateids, CALIFORNIA, 541, 541, [1])
countyfix!(multidayaverages, stateids, CALIFORNIA, 548, 548, [1])
countyfix!(multidayaverages, stateids, CALIFORNIA, 553, 553, [13])
countyfix!(multidayaverages, stateids, CALIFORNIA, 560, 560, [13])
countyfix!(multidayaverages, stateids, FLORIDA, 329, 334, [4])
countyfix!(multidayaverages, stateids, FLORIDA, 296, 302, [13])
countyfix!(multidayaverages, stateids, FLORIDA, 284, 290, [66])
statefix!(multidayaverages, stateids, FLORIDA, 346, 346)
countyfix!(multidayaverages, stateids, FLORIDA, 147, 153, [29])
statefix!(multidayaverages, stateids, GEORGIA, 280, 286)
countyfix!(multidayaverages, stateids, GEORGIA, 287, 292, [143])
countyfix!(multidayaverages, stateids, HAWAII, 276, 282, [3])
countyfix!(multidayaverages, stateids, HAWAII, 287, 293, [3])
countyfix!(multidayaverages, stateids, IDAHO, 66, 71, [7])
countyfix!(multidayaverages, stateids, IDAHO, 269, 275, [22])
countyfix!(multidayaverages, stateids, IDAHO, 513, 517, [5])
countyfix!(multidayaverages, stateids, IDAHO, 512, 518, [5])
countyfix!(multidayaverages, stateids, IDAHO, 511, 519, [5])
countyfix!(multidayaverages, stateids, IDAHO, 237, 243, [25])
countyfix!(multidayaverages, stateids, IOWA, 214, 214, [13, 15, 18, 26, 30, 41, 76, 93])
countyfix!(multidayaverages, stateids, IOWA, 204, 210, [35, 40, 46, 59, 94, 99])
countyfix!(multidayaverages, stateids, IOWA, 212, 218, [25, 35, 40, 46, 59, 89, 94, 99])
countyfix!(multidayaverages, stateids, IOWA, 210, 216, [62])
countyfix!(multidayaverages, stateids, IOWA, 526, 532, [1:4..., 11:12..., 14:17..., 21, 23, 25, 26, 30, 34:38..., 42:44..., 46:50..., 51, 52, 54, 57, 59, 60:71..., 73:77..., 79:83..., 85, 88, 91:93..., 95, 97:99...])
countyfix!(multidayaverages, stateids, IOWA, 526, 532, [1:4...])
countyfix!(multidayaverages, stateids, KANSAS, 115, 121, [13, 43])
countyfix!(multidayaverages, stateids, KANSAS, 343, 349, [9, 17, 24, 34, 35, 51, 58])
countyfix!(multidayaverages, stateids, LOUISIANA, 525, 531, [13, 21, 42, 46, 62])
statefix!(multidayaverages, stateids, MISSOURI, 408, 414)
countyfix!(multidayaverages, stateids, MISSOURI, 422, 428, [23, 52, 56, 63, 82, 87, 97, 106])
statefix!(multidayaverages, stateids, MISSOURI, 445, 451)
countyfix!(multidayaverages, stateids, MONTANA, 526, 532, [38])
countyfix!(multidayaverages, stateids, NEWHAMPSHIRE, 450, 456, [4])
countyfix!(multidayaverages, stateids, NEBRASKA, 161, 162, [87])
countyfix!(multidayaverages, stateids, NEBRASKA, 156, 167, [87])
countyfix!(multidayaverages, stateids, NEVADA, 305, 311, [17])
countyfix!(multidayaverages, stateids, NEVADA, 317, 323, [17])
countyfix!(multidayaverages, stateids, NEVADA, 320, 320, [17])
countyfix!(multidayaverages, stateids, OREGON, 140, 145, [31])
countyfix!(multidayaverages, stateids, OREGON, 241, 247, [4])
countyfix!(multidayaverages, stateids, SOUTHCAROLINA, 238, 244, [2, 6, 19, 35])
countyfix!(multidayaverages, stateids, TENNESSEE, 87, 92, [4])
countyfix!(multidayaverages, stateids, TENNESSEE, 86, 93, [4])
countyfix!(multidayaverages, stateids, TENNESSEE, 86, 86, [4])
countyfix!(multidayaverages, stateids, TENNESSEE, 93, 93, [4])
countyfix!(multidayaverages, stateids, TENNESSEE, 379, 385, [44])
countyfix!(multidayaverages, stateids, TENNESSEE, 106, 112, [48])
countyfix!(multidayaverages, stateids, TENNESSEE, 126, 132, [48])
countyfix!(multidayaverages, stateids, TENNESSEE, 126, 126, [48])
countyfix!(multidayaverages, stateids, TENNESSEE, 135, 139, [48])
countyfix!(multidayaverages, stateids, TENNESSEE, 134, 134, [48])
countyfix!(multidayaverages, stateids, TENNESSEE, 135, 139, [48])
countyfix!(multidayaverages, stateids, TENNESSEE, 134, 134, [48])
countyfix!(multidayaverages, stateids, TENNESSEE, 133, 141, [48])
countyfix!(multidayaverages, stateids, TENNESSEE, 135, 135, [48])
statefix!(multidayaverages, stateids, TENNESSEE, 379, 385)
countyfix!(multidayaverages, stateids, TEXAS, 237, 243, [7, 10, 29, 64, 69, 82, 86, 89, 94, 120, 128, 130, 133, 136, 143, 193, 247, 254])
countyfix!(multidayaverages, stateids, TEXAS, 321, 321, [7])
countyfix!(multidayaverages, stateids, TEXAS, 328, 328, [7])
countyfix!(multidayaverages, stateids, TEXAS, 415, 420, [9])
countyfix!(multidayaverages, stateids, TEXAS, 415, 421, [17])
countyfix!(multidayaverages, stateids, TEXAS, 407, 407, [24])
countyfix!(multidayaverages, stateids, TEXAS, 414, 414, [24])
countyfix!(multidayaverages, stateids, TEXAS, 415, 421, [41])
countyfix!(multidayaverages, stateids, TEXAS, 411, 417, [48])
countyfix!(multidayaverages, stateids, TEXAS, 407, 413, [49])
countyfix!(multidayaverages, stateids, TEXAS, 429, 429, [138])
countyfix!(multidayaverages, stateids, TEXAS, 436, 436, [138])
countyfix!(multidayaverages, stateids, TEXAS, 436, 443, [138])
countyfix!(multidayaverages, stateids, TEXAS, 436, 436, [135, 138]) # 138 must be done twice
countyfix!(multidayaverages, stateids, TEXAS, 431, 431, [122])
countyfix!(multidayaverages, stateids, TEXAS, 438, 438, [122])
countyfix!(multidayaverages, stateids, TEXAS, 327, 327, [41, 48])
countyfix!(multidayaverages, stateids, TEXAS, 234, 236, [1])
countyfix!(multidayaverages, stateids, TEXAS, 241, 243, [1])
countyfix!(multidayaverages, stateids, TEXAS, 278, 284, [1,3,5,7,8,9,10,11,12,16,17,18,19,23,24,25,26,28,30,32,33,34,35,37,41,42,45,46,47,48,49,51,52,53,54,60,61,63,65,67,72,73,74,77,79,80,81:82...,84:90...,92,93,94,96,97,98:100...,102,104,107,109,110:114...,117:119...,121,125:130...,132:134...,140:142...,144:149...,151,154,155:158...,160,163,166,169,171:187...,190,192,194,195,197:204...,207,209:215...,217:219...,221,224,225,228:232...,234,236:238...,241,244,246:250...,252,254])
countyfix!(multidayaverages, stateids, TEXAS, 277, 283, [206])
countyfix!(multidayaverages, stateids, TEXAS, 284, 290, [38])
countyfix!(multidayaverages, stateids, TEXAS, 370, 376, [11,16,18,26,27,28,73,75,81,93,97,109,142,144,145,147,150,154,167,198,206,239])
countyfix!(multidayaverages, stateids, TEXAS, 369, 375, [206])
countyfix!(multidayaverages, stateids, TEXAS, 141, 147, [1])
countyfix!(multidayaverages, stateids, TEXAS, 498, 504, [14])
countyfix!(multidayaverages, stateids, TEXAS, 114, 119, [113])
countyfix!(multidayaverages, stateids, TEXAS, 121, 126, [4,113,125,137,140,189,196,214,245])
countyfix!(multidayaverages, stateids, WASHINGTON, 532, 538, [13])
countyfix!(multidayaverages, stateids, WASHINGTON, 340, 340, [6])
countyfix!(multidayaverages, stateids, WASHINGTON, 347, 347, [6])
countyfix!(multidayaverages, stateids, WISCONSIN, 232, 232, [57:60...])
countyfix!(multidayaverages, stateids, WISCONSIN, 239, 239, [57:60...])
statefix!(multidayaverages, stateids, WISCONSIN, 265, 271)
countyfix!(multidayaverages, stateids, WYOMING, 395, 399, [10])
countyfix!(multidayaverages, stateids, WYOMING, 394, 400, [10])


alaskageoms = geoms[stateids .== ALASKA]
hawaiigeoms = geoms[stateids .== HAWAII]
#puertoricogeoms = geoms[stateids .== PUERTORICO]
lower48geoms = geoms[stateids .∉ Ref([ALASKA, HAWAII, PUERTORICO])]

grad = cgrad(:thermal)
colors = map(x -> grad[x], multidayaverages)
alaskacolors = colors[stateids .== ALASKA, :]
hawaiicolors = colors[stateids .== HAWAII, :]
lower48colors = colors[stateids .∉ Ref([ALASKA, HAWAII, PUERTORICO]), :]

# plotting speed improvement
# remember to also have RecipesPipeline errors fixed
@eval Base begin
    @inline function __unsafe_string!(out, s::Symbol, offs::Integer)
        n = sizeof(s)
        GC.@preserve s out unsafe_copyto!(pointer(out, offs), unsafe_convert(Ptr{UInt8},s), n)
        return n
    end

    function string(a::Union{Char, String, SubString{String}, Symbol}...)
        n = 0
        for v in a
            if v isa Char
                n += ncodeunits(v)
            else
                n += sizeof(v)
            end
        end
        out = _string_n(n)
        offs = 1
        for v in a
            offs += __unsafe_string!(out, v, offs)
        end
        return out
    end
end


anim = Plots.Animation()
date = Date("1/28/2020", dateformat"mm/dd/yyyy")
for i ∈ 1:length(eachcol(lower48colors))
    println("Day $i")
    lower48plot = plot(lower48geoms, fillcolor=permutedims(lower48colors[:, i]), size=(2048, 1280),
        grid=false, showaxis=false, ticks=false, aspect_ratio=1.2, title="United States COVID-19 Hot Spots\nNicholas C Bauer PhD | Twitter: @bioturbonick",
        titlefontcolor=:white, background_color=:black, linecolor=grad[0.0])
    annotate!([(-75,30.75, ("$date", 36, :white))])
    plot!(lower48plot, alaskageoms, fillcolor=permutedims(alaskacolors[:, i]),
        grid=false, showaxis=false, ticks=false, xlims=(-180,-130), ylims=(51, 78), aspect_ratio=2,
        linecolor=grad[0.0],
        inset=(1, bbox(0.0, 0.0, 0.3, 0.3, :bottom, :left)), subplot=2)
    plot!(lower48plot, hawaiigeoms, fillcolor=permutedims(hawaiicolors[:, i]),
        grid=false, showaxis=false, ticks=false, xlims=(-160, -154), ylims=(18, 23),
        linecolor=grad[0.0],
        inset=(1, bbox(0.25, 0.0, 0.2, 0.2, :bottom, :left)), subplot=3)
    Plots.frame(anim)
    date += Day(1)
end
for i = 1:20 # insert 20 more of the same frame at end
    Plots.frame(anim)
end
mp4(anim, joinpath("output", "us_animation_map.mp4"), fps = 7)
#mp4(anim, joinpath("output", "us_animation_map_absolute.mp4"), fps = 7)
