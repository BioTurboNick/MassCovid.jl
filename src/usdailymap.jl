using DataFrames
using Dates
using Downloads
using Shapefile
using Plots
using XLSX
using CSV
using Missings
using Smoothers
using Statistics
using ImageFiltering
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
    Downloads.download("https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_US.csv", path)
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
    shpdata[!, :STNAME] .= [haskey(statefp_name_dict, x) ? statefp_name_dict[x] : missing for x ∈ parse.(Int, shpdata.STATEFP)]

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
        data[sourceselector, datarange] .* getcountypop(data, statename, destcountyname) ./ statepop

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

    # switch to FP
    cols = propertynames(data)[datarange]
    transform!(data, cols .=> ByRow(Float64) .=> cols)
    data[!, datarange] .= Float64.(data[!, datarange])

    # Alaska
    akpop = getstatepop(data, "Alaska")
    data[selectcounty(data, "Alaska", "Valdez-Cordova"), datarange] .+=
        data[selectcounty(data, "Alaska", "Chugach"), datarange] .+
        data[selectcounty(data, "Alaska", "Copper River"), datarange]
    akbblprow = selectcounty(data, "Alaska", "Bristol Bay plus Lake and Peninsula") # Bristol Bay, Lake and Peninsula
    addcountycases!(data, "Alaska", "Bristol Bay", akbblprow, akpop, datarange)
    addcountycases!(data, "Alaska", "Lake and Peninsula", akbblprow, akpop, datarange)
    data.Combined_Key[data.Admin2 .== "Lake and Peninsula"] .= "Lake and Peninsula, Alaska, US"
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

function fixnegatives!(series)
    # distribute negatives by canceling out recent positives
    for row ∈ eachrow(series)
        for i ∈ reverse(axes(series, 2))
            row[i] < 0 || continue
            for j ∈ i - 1:-1:1
                row[j] > 0 || continue
                if row[j] ≥ row[i]
                    row[j] += row[i]
                    row[i] = 0
                else
                    row[i] += row[j]
                    row[j] = 0
                end
                row[i] < 0 || break
            end
            row[i] = 0 # couldn't find any earlier positives
        end
    end
end

function fixweekendspikes!(series)
    # distribute spikes preceded by 1-13 zero-days evenly across the period
    # here, "zero" is < 0.02 * the spike value
    for row ∈ eachrow(series)
        for i ∈ reverse(axes(series, 2))
            threshold = 0.02 * row[i]
            row[i] > 0 && i > 1 && row[i - 1] < threshold || continue
            # count adjacent ~0-days
            count = 0
            for j ∈ i - 1:-1:i - 13
                j > 0 && row[j] < threshold || break
                count += 1
            end
            count == 13 && i > 14 && row[i - 14] < threshold && continue # more than 2 weeks of zeros, different type of spike
            spreadvalue = row[i] / (count + 1)
            row[i - count:i - 1] .+= spreadvalue
            row[i] = spreadvalue
        end
    end
end

function fixspikes!(data, series)
    statefix!(data, series, "Alabama", 325)
    statefix!(data, series, "Alabama", 386)
    countyfix!(data, series, "Alabama", 406, [5, 7, 8, 15, 22, 25, 28, 36, 43, 44, 48, 58, 59, 67])
    statefix!(data, series, "Alabama", 418)
    statefix!(data, series, "Alabama", 478)
    statefix!(data, series, "Alabama", 644, 645)

    countyfix!(data, series, "Alaska", 180, [2, 6, 11])
    statefix!(data, series, "Alaska", 346)

    statefix!(data, series, "Arizona", 216)
    statefix!(data, series, "Arizona", 421)
    statefix!(data, series, "Arizona", 423)
    statefix!(data, series, "Arizona", 434)
    
    statefix!(data, series, "Arkansas", 206)
    statefix!(data, series, "Arkansas", 403, 404)
    statefix!(data, series, "Arkansas", 428)

    statefix!(data, series, "California", 66, 67)
    statefix!(data, series, "California", 307)
    statefix!(data, series, "California", 343, 344)
    statefix!(data, series, "California", 524)
    statefix!(data, series, "California", 536)

    statefix!(data, series, "Florida", 345)

    statefix!(data, series, "Georgia", 175)
    statefix!(data, series, "Georgia", 181)
    statefix!(data, series, "Georgia", 286)

    statefix!(data, series, "Idaho", 231)
    statefix!(data, series, "Idaho", 332)

    statefix!(data, series, "Iowa", 210)
    statefix!(data, series, "Iowa", 218)
    statefix!(data, series, "Iowa", 220, 221)
    statefix!(data, series, "Iowa", 532, 533)

    statefix!(data, series, "Kansas", 121)
    statefix!(data, series, "Kansas", 206, 208)
    statefix!(data, series, "Kansas", 349)

    statefix!(data, series, "Kentucky", 292)
    statefix!(data, series, "Kentucky", 430)

    statefix!(data, series, "Louisiana", 149)
    countyfix!(data, series, "Louisiana", 531, [13, 21, 42, 46, 62])

    statefix!(data, series, "Missouri", 254)
    statefix!(data, series, "Missouri", 414)
    countyfix!(data, series, "Missouri", 427, 429, [23, 52, 56, 63, 82, 87, 97, 106])
    statefix!(data, series, "Missouri", 451)
    statefix!(data, series, "Missouri", 501)
    statefix!(data, series, "Missouri", 666)

    statefix!(data, series, "New York", 92, 94)

    statefix!(data, series, "New Hampshire", 640, 643)

    statefix!(data, series, "Nevada", 600)

    statefix!(data, series, "Pennsylvania", 430, 431)

    statefix!(data, series, "Rhode Island", 574)
    statefix!(data, series, "Rhode Island", 588)

    countyfix!(data, series, "South Carolina", 244, [2, 6, 19, 35])

    countyfix!(data, series, "Tennessee", 292, 293, [9, 20, 29, 34])
    statefix!(data, series, "Tennessee", 385)
    statefix!(data, series, "Tennessee", 506)
    statefix!(data, series, "Tennessee", 510)
    
    countyfix!(data, series, "Texas", 113, [113])
    countyfix!(data, series, "Texas", 147, [1])
    countyfix!(data, series, "Texas", 240, [1])

    statefix!(data, series, "Texas", 282)
    statefix!(data, series, "Texas", 284)
    statefix!(data, series, "Texas", 326, 327)
    countyfix!(data, series, "Texas", 327, 328, [7])
    statefix!(data, series, "Texas", 376)
    statefix!(data, series, "Texas", 378)
    statefix!(data, series, "Texas", 507)
    statefix!(data, series, "Texas", 514)
    statefix!(data, series, "Texas", 518)
    statefix!(data, series, "Texas", 521)
    statefix!(data, series, "Texas", 524)

    statefix!(data, series, "Washington", 547, 550)

    countyfix!(data, series, "Wisconsin", 238, 239, [57:60...])
    statefix!(data, series, "Wisconsin", 269, 270)
    statefix!(data, series, "Wisconsin", 271)

    statefix!(data, series, "Utah", 67, 68)
    statefix!(data, series, "Utah", 86)
    statefix!(data, series, "Utah", 88)
    statefix!(data, series, "Utah", 309, 310)
end

function fill_end!(series)
    # fill up to 14 days at the end with the most recent nonzero value
    for row ∈ eachrow(series)
        row[end] == 0 || continue
        lasti = size(series, 2)
        for i ∈ reverse(axes(series, 2))[2:14]
            if row[i] > 0
                lasti = i
                break
            end
        end
        lasti < size(series, 2) || continue
        row[(lasti + 1):end] .= row[lasti]
    end
end

    # consider:
    # - add flickering
    # - algorithm to dampen huge peaks based on how flat surrounding is

data = loadcountydata()
colnames = propertynames(data)
datarange = findfirst(==(Symbol("1/22/20")), colnames):findfirst(==(:SUMLEV), colnames) - 1
preparedata!(data, datarange)

series = Array{Float64, 2}(data[!, datarange])
series = diff(series, dims = 2)
series ./= data.POPESTIMATE2019
fixnegatives!(series)
fixspikes!(data, series)
fixweekendspikes!(series)
#dampenspikes!(series)                      FIX THIS
fill_end!(series)
seriesavg = reduce(hcat, sma.(eachrow(series), 7))
seriesavg ./= mapwindow(maximum, seriesavg, (365, 1)) # 0.0015
seriesavg[seriesavg .< 0] .= 0
seriesavg[isnan.(seriesavg)] .= 0

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
date = Date(names(data)[datarange[end]], dateformat"mm/dd/yy") + Year(2000) - Day(length(eachrow(lower48colors)) - 1)
for i ∈ 1:length(eachrow(lower48colors))
    println("Day $i")
    lower48plot = plot(lower48geoms, fillcolor=permutedims(@view lower48colors[i, :]), size=(2048, 1280),
        grid=false, showaxis=false, ticks=false, aspect_ratio=1.2, title="United States COVID-19 Hot Spots\nNicholas C Bauer PhD | Twitter: @bioturbonick",
        titlefontcolor=:white, background_color=:black, linecolor=grad[0.0])
    annotate!([(-75,30.75, ("$date", 36, :white))])
    plot!(lower48plot, alaskageoms, fillcolor=permutedims(@view alaskacolors[i, :]),
        grid=false, showaxis=false, ticks=false, xlims=(-180,-130), ylims=(51, 78), aspect_ratio=2,
        linecolor=grad[0.0],
        inset=(1, bbox(0.0, 0.0, 0.3, 0.3, :bottom, :left)), subplot=2)
    plot!(lower48plot, hawaiigeoms, fillcolor=permutedims(@view hawaiicolors[i, :]),
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
