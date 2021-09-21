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
    admin2 = Missings.replace(jhudata.Admin2, "")

    poppath = joinpath("input", "co-est2019-alldata.csv")
    popdata = CSV.read(poppath, DataFrame)
    popdata[popdata.CTYNAME .== "Do\xf1a Ana County", :CTYNAME] .= "Dona Ana County"
    popdata.CTYNAME = replace.(popdata.CTYNAME, " County" => "") # trim suffixes
    popdata.CTYNAME = replace.(popdata.CTYNAME, " Census Area" => "")
    popdata.CTYNAME = replace.(popdata.CTYNAME, " Borough" => "")
    popdata.CTYNAME = replace.(popdata.CTYNAME, " Parish" => "")
    popdata.CTYNAME = replace.(popdata.CTYNAME, " City and" => "")
    popdata.CTYNAME = replace.(popdata.CTYNAME, " Municipality" => "")
    popdata.CTYNAME = replace.(popdata.CTYNAME, " city" => " City")
    # deal with "City" suffix
    cityrows = findall(endswith.(popdata.CTYNAME, " City"))
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
    cityrows = findall(parse.(Int, shpdata.COUNTYFP) .>= 500)
    citynames = shpdata[cityrows, :NAME]
    citynamesappend = deepcopy(citynames)
    citynames[endswith.(citynames, " City")] .= replace.(citynames[endswith.(citynames, " City")], " City" => "")
    citynamesappend[.!endswith.(citynamesappend, " City")] = citynamesappend[.!endswith.(citynamesappend, " City")] .* " City"
    shpdata[cityrows[citynamesappend .∈ Ref(admin2)], :NAME] .= citynamesappend[citynamesappend .∈ Ref(admin2)]
    shpdata[cityrows[citynamesappend .∉ Ref(admin2)], :NAME] .= citynames[citynamesappend .∉ Ref(admin2)]
    shpdata.STNAME .= [haskey(statefp_name_dict, x) ? statefp_name_dict[x] : missing for x ∈ parse.(Int, shpdata.STATEFP)]

    data = outerjoin(data, shpdata, on = [:Province_State => :STNAME, :Admin2 => :NAME], matchmissing = :equal)
    return data
end

selectcounty(data, statename, countyname) =
    findall((data.Province_State .== statename) .& (Missings.replace(data.COUNTY, -1) .!= 0) .& (data.Admin2 .== countyname))

selectcounties(data, statename, countynames) =
    findall((data.Province_State .== statename) .& (Missings.replace(data.COUNTY, -1) .!= 0) .& (data.Admin2 .∈ Ref(countynames)))

selectstate(data, statename) =
    findall((data.Province_State .== statename) .& (Missings.replace(data.COUNTY, -1) .== 0) .& (data.Admin2 .== statename))

selectstatecounties(data, statename) =
    findall((data.Province_State .== statename) .& (Missings.replace(data.COUNTY, -1) .!= 0))

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
    for statename ∈ unique(data.Province_State)
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

    statefix!(data, series, "California", 66, 67)
    countyfix!(data, series, "California", 107, [42])
    countyfix!(data, series, "California", 262, [53])
    countyfix!(data, series, "California", 266, [45])
    countyfix!(data, series, "California", 276, [53])
    statefix!(data, series, "California", 307)
    countyfix!(data, series, "California", 315, [28])
    countyfix!(data, series, "California", 324, 324, [46])
    countyfix!(data, series, "California", 336, 337, [39])
    statefix!(data, series, "California", 343, 344)
    countyfix!(data, series, "California", 360, [34])
    countyfix!(data, series, "California", 380, 381, [2])
    statefix!(data, series, "California", 524)
    statefix!(data, series, "California", 536)
    countyfix!(data, series, "California", 554, [32])

    countyfix!(data, series, "Florida", 146, [20])
    countyfix!(data, series, "Florida", 153, [29])
    countyfix!(data, series, "Florida", 272, [20])
    countyfix!(data, series, "Florida", 153, 154, [7])
    countyfix!(data, series, "Florida", 156, 157, [7])
    countyfix!(data, series, "Florida", 189, [4, 31, 63])
    countyfix!(data, series, "Florida", 190, [20])
    countyfix!(data, series, "Florida", 196, 197, [38])
    countyfix!(data, series, "Florida", 290, [66])
    countyfix!(data, series, "Florida", 321, [48])
    countyfix!(data, series, "Florida", 334, [4])
    statefix!(data, series, "Florida", 345)
    countyfix!(data, series, "Florida", 392, [20])

    countyfix!(data, series, "Georgia", 174, [131])
    statefix!(data, series, "Georgia", 175)
    countyfix!(data, series, "Georgia", 176, [131])
    statefix!(data, series, "Georgia", 181)
    statefix!(data, series, "Georgia", 286)
    countyfix!(data, series, "Georgia", 290, [19])
    countyfix!(data, series, "Georgia", 290, 291, [44])
    countyfix!(data, series, "Georgia", 291, 292, [144])
    countyfix!(data, series, "Georgia", 300, [19])
    countyfix!(data, series, "Georgia", 302, 303, [19])
    countyfix!(data, series, "Georgia", 307, [4])
    countyfix!(data, series, "Georgia", 306, 307, [19])

    countyfix!(data, series, "Hawaii", 233, [5])
    countyfix!(data, series, "Hawaii", 282, [3])
    countyfix!(data, series, "Hawaii", 293, [3])

    countyfix!(data, series, "Idaho", 65, 66, [38])
    statefix!(data, series, "Idaho", 231)
    countyfix!(data, series, "Idaho", 275, [22])
    countyfix!(data, series, "Idaho", 374, [17])
    countyfix!(data, series, "Idaho", 376, [17])
    countyfix!(data, series, "Idaho", 398, 399, [19])
    countyfix!(data, series, "Idaho", 331, 332, [12])
    statefix!(data, series, "Idaho", 332)
    countyfix!(data, series, "Idaho", 517, 519, [5])
    countyfix!(data, series, "Idaho", 243, [25])

    statefix!(data, series, "Iowa", 210)
    statefix!(data, series, "Iowa", 218)
    statefix!(data, series, "Iowa", 220, 221)
    countyfix!(data, series, "Iowa", 413, [36])
    statefix!(data, series, "Iowa", 532, 533)

    statefix!(data, series, "Kansas", 121)
    statefix!(data, series, "Kansas", 206, 208)
    countyfix!(data, series, "Kansas", 259, [73])
    countyfix!(data, series, "Kansas", 313, [47])
    countyfix!(data, series, "Kansas", 320, [83])
    statefix!(data, series, "Kansas", 349)
    countyfix!(data, series, "Kansas", 357, [91])
    countyfix!(data, series, "Kansas", 366, [40])
    countyfix!(data, series, "Kansas", 516, [3, 5])
    countyfix!(data, series, "Kansas", 518, [3, 5])
    countyfix!(data, series, "Kansas", 520, [3, 5])

    countyfix!(data, series, "Louisiana", 123, [20])
    countyfix!(data, series, "Louisiana", 125, [20])
    statefix!(data, series, "Louisiana", 149)
    countyfix!(data, series, "Louisiana", 256, 261, [12])
    countyfix!(data, series, "Louisiana", 531, [13, 21, 42, 46, 62])
    countyfix!(data, series, "Louisiana", 538, 539, [13])
    countyfix!(data, series, "Louisiana", 572, [63])

    statefix!(data, series, "Missouri", 254)
    countyfix!(data, series, "Missouri", 256, [50])
    countyfix!(data, series, "Missouri", 256, 257, [10])
    countyfix!(data, series, "Missouri", 258, [50])
    statefix!(data, series, "Missouri", 414)
    countyfix!(data, series, "Missouri", 428, 429, [23, 52, 56, 63, 82, 87, 97, 106])
    statefix!(data, series, "Missouri", 451)
    statefix!(data, series, "Missouri", 501)

    countyfix!(data, series, "Montana", 278, [23])
    countyfix!(data, series, "Montana", 280, [17])
    countyfix!(data, series, "Montana", 297, [44])
    countyfix!(data, series, "Montana", 532, [38])
    countyfix!(data, series, "Montana", 572, 573, [35])

    countyfix!(data, series, "New Hampshire", 83, 85, [6])
    countyfix!(data, series, "New Hampshire", 456, [4])

    countyfix!(data, series, "Nebraska", 162, [87])
    countyfix!(data, series, "Nebraska", 105, 106, [60])
    countyfix!(data, series, "Nebraska", 119, 121, [52])

    countyfix!(data, series, "Nevada", 304, 306, [17])
    countyfix!(data, series, "Nevada", 311, [17])
    countyfix!(data, series, "Nevada", 312, [7])
    countyfix!(data, series, "Nevada", 319, 320, [17])
    countyfix!(data, series, "Nevada", 323, [17])
    statefix!(data, series, "Nevada", 600)

    countyfix!(data, series, "Oregon", 145, 146, [31])
    countyfix!(data, series, "Oregon", 247, [4])

    countyfix!(data, series, "South Carolina", 232, 233, [31])
    countyfix!(data, series, "South Carolina", 244, [2, 6, 19, 35])
    countyfix!(data, series, "South Carolina", 293, 294, [31])

    countyfix!(data, series, "Tennessee", 92, 93, [4, 48])
    countyfix!(data, series, "Tennessee", 111, 113, [48])
    countyfix!(data, series, "Tennessee", 132, 133, [48])
    countyfix!(data, series, "Tennessee", 139, 141, [48])
    countyfix!(data, series, "Tennessee", 385, [44])
    statefix!(data, series, "Tennessee", 385)
    
    countyfix!(data, series, "Texas", 240, [1])
    countyfix!(data, series, "Texas", 243, [1, 7, 10, 29, 64, 69, 82, 86, 89, 94, 120, 128, 130, 133, 136, 143, 193, 247, 254])
    statefix!(data, series, "Texas", 282)
    countyfix!(data, series, "Texas", 282, 284, [206])
    statefix!(data, series, "Texas", 284)
    countyfix!(data, series, "Texas", 326, 327, [41, 48])
    countyfix!(data, series, "Texas", 327, 328, [7])
    countyfix!(data, series, "Texas", 371, 373, [22])
    statefix!(data, series, "Texas", 376)
    statefix!(data, series, "Texas", 378)
    countyfix!(data, series, "Texas", 384, 387, [206])
    countyfix!(data, series, "Texas", 413, [49])
    countyfix!(data, series, "Texas", 413, 414, [24])
    countyfix!(data, series, "Texas", 421, [17, 41])
    countyfix!(data, series, "Texas", 428, [41])
    countyfix!(data, series, "Texas", 408, [122])
    countyfix!(data, series, "Texas", 410, 450, [122])
    countyfix!(data, series, "Texas", 435, 436, [135, 138])
    countyfix!(data, series, "Texas", 443, [138])
end

data = loadcountydata()
colnames = propertynames(data)
datarange = findfirst(==(Symbol("1/22/20")), colnames):findfirst(==(:SUMLEV), colnames) - 1
preparedata!(data, datarange)

series = Array{Float64, 2}(data[!, datarange])
series = diff(series, dims = 2)
series ./= data.POPESTIMATE2019
fixspikes!(data, series)
seriesavg = hcat(sma.(eachrow(series), 14)...)
seriesavg ./= maximum(seriesavg, dims = 1)

#=
countyfix!(multidayaverages, stateids, TEXAS, 284, 290, [38])
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
=#


alaskageoms = data.geometry[data.Province_State .== "Alaska"]
hawaiigeoms = data.geometry[data.Province_State .== "Hawaii"]
#puertoricogeoms = data.geometry[data.Province_State .== "Puerto Rico"]
lower48geoms = data.geometry[data.Province_State .∉ Ref(["Alaska", "Hawaii", "Puerto Rico"])]

grad = cgrad(:thermal)
colors = map(x -> grad[x], seriesavg)
alaskacolors = colors[:, data.Province_State .== "Alaska"]
hawaiicolors = colors[:, data.Province_State .== "Hawaii"]
lower48colors = colors[:, data.Province_State .∉ Ref(["Alaska", "Hawaii", "Puerto Rico"])]

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
date = Date("2/5/2020", dateformat"mm/dd/yyyy")
for i ∈ 1:length(eachrow(lower48colors))
    println("Day $i")
    lower48plot = plot(lower48geoms, fillcolor=permutedims(lower48colors[i, :]), size=(2048, 1280),
        grid=false, showaxis=false, ticks=false, aspect_ratio=1.2, title="United States COVID-19 Hot Spots\nNicholas C Bauer PhD | Twitter: @bioturbonick",
        titlefontcolor=:white, background_color=:black, linecolor=grad[0.0])
    annotate!([(-75,30.75, ("$date", 36, :white))])
    plot!(lower48plot, alaskageoms, fillcolor=permutedims(alaskacolors[i, :]),
        grid=false, showaxis=false, ticks=false, xlims=(-180,-130), ylims=(51, 78), aspect_ratio=2,
        linecolor=grad[0.0],
        inset=(1, bbox(0.0, 0.0, 0.3, 0.3, :bottom, :left)), subplot=2)
    plot!(lower48plot, hawaiigeoms, fillcolor=permutedims(hawaiicolors[i, :]),
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
