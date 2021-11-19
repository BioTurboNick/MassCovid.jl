using CodecZlib
using DataFrames
using Dates
using Downloads
using Shapefile
using Plots
using PolygonOps
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

function loadcountyweatherdata(data)
    pathstations = joinpath("input", "weatherstations.txt")
    stations = nothing
    if !isfile(pathstations)
        Downloads.download("ftp://ftp.ncdc.noaa.gov/pub/data/ghcn/daily/ghcnd-stations.txt", pathstations)
        stations = CSV.read(pathstations, DataFrame, delim = " ", ignorerepeated = true, select = 1:4, header = false, silencewarnings = true)
        rename!(stations, 1 => "ID", 2 => "LATITUDE", 3 => "LONGITUDE", 4 => "ELEVATION")
        minlong, maxlong, minlat, maxlat = let
            minlong = minlat = Inf
            maxlong = maxlat = -Inf
            for g ∈ data.geometry
                for p ∈ g.points
                    p.x < 0 || continue # ignore the Alaska islands over the date line
                    p.x < minlong && (minlong = p.x)
                    p.x > maxlong && (maxlong = p.x)
                    p.y < minlat && (minlat = p.y)
                    p.y > maxlat && (maxlat = p.y)
                end
            end
            minlong, maxlong, minlat, maxlat
        end
        alaskaminlong, alaskamaxlong, alaskaminlat, alaskamaxlat = let 
            minlong = minlat = Inf
            maxlong = maxlat = -Inf
            g = data[data.Admin2 .== "Aleutians West", :geometry][1]
            for p ∈ g.points
                p.x > 0 || continue # consider only points to the west of the dateline
                p.x < minlong && (minlong = p.x)
                p.x > maxlong && (maxlong = p.x)
                p.y < minlat && (minlat = p.y)
                p.y > maxlat && (maxlat = p.y)
            end
            minlong, maxlong, minlat, maxlat
        end

        filter!(stations) do s
            minlong ≤ s.LONGITUDE ≤ maxlong && minlat ≤ s.LATITUDE ≤ maxlat ||
                alaskaminlong ≤ s.LONGITUDE ≤ alaskamaxlong && alaskaminlat ≤ s.LATITUDE ≤ alaskamaxlat
        end

        key = Vector{Union{Missing, String}}(undef, length(stations.ID))
        key .= missing
        for (j, g) ∈ enumerate(data.geometry)
            if data[j, :Admin2] == "Aleutians West"
                pointswest = [(p.x, p.y) for p ∈ filter(x -> x.x > 0, g.points)]
                push!(pointswest, pointswest[1])
                points =  [(p.x, p.y) for p ∈ filter(x -> x.x < 0, g.points)]
                push!(points, points[1])
            else
                pointswest = []
                points = [(p.x, p.y) for p ∈ g.points]
                push!(points, points[1])
            end

            for (i, s) ∈ enumerate(eachrow(stations))
                ismissing(key[i]) || continue
                
                if data[j, :Admin2] == "Aleutians West"
                    if inpolygon((s.LONGITUDE, s.LATITUDE), pointswest) != 0
                        key[i] = data[j, :Combined_Key]
                    elseif inpolygon((s.LONGITUDE, s.LATITUDE), points) != 0
                        key[i] = data[j, :Combined_Key]
                    end
                else
                    if inpolygon((s.LONGITUDE, s.LATITUDE), points) != 0
                        key[i] = data[j, :Combined_Key]
                    end
                end
            end
        end
        stations[!, :Combined_Key] = key
        filter!(:Combined_Key => !ismissing, stations)

        CSV.write(pathstations, stations)
    else
        stations = CSV.read(pathstations, DataFrame)
    end

    weatherpath = joinpath("input", "weather.csv")
    weatherdata = nothing
    if !isfile(weatherpath)
        path2020 = joinpath("input", "weather_2020.csv.gz")
        if !isfile(path2020)
            Downloads.download("ftp://ftp.ncdc.noaa.gov/pub/data/ghcn/daily/by_year/2020.csv.gz", path2020)
        end
        path2021 = joinpath("input", "weather_2021.csv.gz")
        Downloads.download("ftp://ftp.ncdc.noaa.gov/pub/data/ghcn/daily/by_year/2021.csv.gz", path2021)

        header = ["ID", "DATE", "ELEMENT", "VALUE", "MFLAG", "QFLAG", "SFLAG", "TIME"]
        weatherdata = nothing
        open(path2020) do f
            stream = GzipDecompressorStream(f)
            global weatherdata = CSV.read(stream, DataFrame; header)
            close(stream)
        end
        open(path2021) do f
            stream = GzipDecompressorStream(f)
            append!(weatherdata, CSV.read(stream, DataFrame; header))
            close(stream)
        end

        filter!(:ELEMENT => x -> x ∈ ("TMIN", "TAVG", "TMAX"), weatherdata) # retain temperature records
        filter!(:QFLAG => ismissing, weatherdata) # retain temperature records without quality flags

        tmindata = filter(:ELEMENT => ==("TMIN"), weatherdata)
        rename!(tmindata, :VALUE => :TMIN)
        tavgdata = filter(:ELEMENT => ==("TAVG"), weatherdata)
        rename!(tavgdata, :VALUE => :TAVG)
        tmaxdata = filter(:ELEMENT => ==("TMAX"), weatherdata)
        rename!(tmaxdata, :VALUE => :TMAX)
        weatherdata = tmindata
        weatherdata = outerjoin(weatherdata, tavgdata[!, [:ID, :DATE, :TAVG]], on = [:ID, :DATE])
        weatherdata = outerjoin(weatherdata, tmaxdata[!, [:ID, :DATE, :TMAX]], on = [:ID, :DATE])
        filter!(x -> !ismissing(x.TMIN) && !ismissing(x.TAVG) && !ismissing(x.TMAX), weatherdata) # retain complete temperature records
        filter!(:ID => x -> x ∈ stations.ID, weatherdata) # retain US temperature records

        # combine counties
        weatherdata = innerjoin(weatherdata, stations[!, [:ID, :Combined_Key, :ELEVATION]], on = [:ID])
        groupedweatherdata = groupby(weatherdata, [:Combined_Key, :DATE])
        # should select stations with the lowest elevation in a county
        weatherdata = combine(groupedweatherdata, :TMIN => mean => :TMIN, :TAVG => mean => :TAVG, :TMAX => mean => :TMAX, :ELEVATION => mean => :ELEVATION)
        transform!(weatherdata, :DATE => (x -> Date.(string.(x), dateformat"yyyymmdd")) => :DATE)
        transform!(weatherdata, :TMIN => (x -> x / 10) => :TMIN)
        transform!(weatherdata, :TMAX => (x -> x / 10) => :TMAX)
        transform!(weatherdata, :TAVG => (x -> x / 10) => :TAVG)

        # insert missing days
        groupedweatherdata = groupby(copy(weatherdata), [:Combined_Key])
        for g ∈ groupedweatherdata
            missingdates = setdiff(Date("20200101", dateformat"yyyymmdd"):Day(1):today(), sort(g.DATE))
            for d ∈ missingdates
                push!(weatherdata, (g.Combined_Key[1], d, NaN, NaN, NaN, NaN))
            end
        end

        CSV.write(weatherpath, weatherdata)
    else
        weatherdata = CSV.read(weatherpath, DataFrame)
    end
    
    return weatherdata
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
    # distribute spikes preceded by 1-6 zero-days evenly across the period
    # here, "zero" is < 0.02 * the spike value
    for row ∈ eachrow(series)
        for i ∈ reverse(axes(series, 2))
            threshold = 0.02 * row[i]
            row[i] > 0 && i > 1 && row[i - 1] < threshold || continue
            # count adjacent ~0-days
            count = 0
            for j ∈ i - 1:-1:i - 6
                j > 0 && row[j] < threshold || break
                count += 1
            end
            count == 6 && i > 7 && row[i - 7] < threshold && continue # more than a week of zeros, different type of spike
            spreadvalue = row[i] / (count + 1)
            row[i - count:i - 1] .+= spreadvalue
            row[i] = spreadvalue
        end
    end
end

function dampenspikes!(series)
    # eliminate spikes by Windsorizing
    for row ∈ eachrow(series)
        sortedvals = row |> vec |> sort
        maxdiffi = sortedvals |> diff |> argmax
        if length(row) - maxdiffi > length(row) / 50
            # no more than 2 spikes dampened per 100 days
            maxdiffi = length(row) ÷ 50
        end
        thresholdval = sortedvals[maxdiffi + 1]
        replacementval = sortedvals[maxdiffi]
        for i ∈ reverse(axes(series, 2))
            row[i] < thresholdval && continue
            row[i] = replacementval
        end
    end
end

    # consider:
    # - add flickering
    # - algorithm to dampen huge peaks based on how flat surrounding is

data = loadcountydata()
colnames = propertynames(data)
datarange = findfirst(==(Symbol("1/22/20")), colnames):findfirst(==(:SUMLEV), colnames) - 1
preparedata!(data, datarange)

# load weather data here
weatherdata = loadweatherdata(data)
sort!(weatherdata, [:Combined_Key, :DATE])

# change out NaN for an average of nearby values, if not at the end of the series
groupedweatherdata = groupby(weatherdata, [:Combined_Key])
for g ∈ groupedweatherdata
    for (i, rec) ∈ enumerate(eachrow(g))
        1 < i < length(g.TMIN) || continue
        if isnan(rec.TMIN)
            prevtmin = NaN
            for j ∈ (i - 1):-1:1
                if !isnan(g[j, :TMIN])
                    prevtmin = g[j, :TMIN]
                    break
                end
            end
            nexttmin = NaN
            for j ∈ (i - 1):length(g.TMIN)
                if !isnan(g[j, :TMIN])
                    nexttmin = g[j, :TMIN]
                    break
                end
            end
            if !isnan(prevtmin) && !isnan(nexttmin)
                rec.TMIN = mean([prevtmin, nexttmin])
            end
        end
        if isnan(rec.TAVG)
            prevtavg = NaN
            for j ∈ (i - 1):-1:1
                if !isnan(g[j, :TAVG])
                    prevtavg = g[j, :TAVG]
                    break
                end
            end
            nexttavg = NaN
            for j ∈ (i - 1):length(g.TAVG)
                if !isnan(g[j, :TAVG])
                    nexttavg = g[j, :TAVG]
                    break
                end
            end
            if !isnan(prevtavg) && !isnan(nexttavg)
                rec.TAVG = mean([prevtavg, nexttavg])
            end
        end
        if isnan(rec.TMAX)
            prevtmax = NaN
            for j ∈ (i - 1):-1:1
                if !isnan(g[j, :TMAX])
                    prevtmax = g[j, :TMAX]
                    break
                end
            end
            nexttmax = NaN
            for j ∈ (i - 1):length(g.TMAX)
                if !isnan(g[j, :TMAX])
                    nexttmax = g[j, :TMAX]
                    break
                end
            end
            if !isnan(prevtmax) && !isnan(nexttmax)
                rec.TMAX = mean([prevtmax, nexttmax])
            end
        end
    end
end

# filter for only counties for which we also have temperature data
sort!(data, :Combined_Key)
filter!(:Combined_Key => x -> x ∈ weatherdata.Combined_Key, data)

# extract temperature series
ncounties = length(unique(weatherdata.Combined_Key))
nobservations = length(weatherdata[!, :TMIN]) ÷ ncounties
tminseries = permutedims(reshape(weatherdata[!, :TMIN], nobservations, ncounties))
tmaxseries = permutedims(reshape(weatherdata[!, :TMAX], nobservations, ncounties))
tavgseries = permutedims(reshape(weatherdata[!, :TAVG], nobservations, ncounties))

# extract cases series
series = Array{Float64, 2}(data[!, datarange])
series = diff(series, dims = 2)
series ./= data.POPESTIMATE2019
fixnegatives!(series)
fixweekendspikes!(series)
dampenspikes!(series)
seriesavg = reduce(hcat, sma.(eachrow(series), 7))
seriesavg ./= maximum(seriesavg, dims = 1)
seriesavg[isnan.(seriesavg)] .= 0

seriesavgdiff = diff(seriesavg, dims = 1) ./ seriesavg[1:end - 1, :]
seriesavgdiff[isnan.(seriesavgdiff)] .= 0

tminseriesavg = reduce(hcat, sma.(eachrow(tminseries), 14))
tavgseriesavg = reduce(hcat, sma.(eachrow(tavgseries), 14))
tmaxseriesavg = reduce(hcat, sma.(eachrow(tmaxseries), 14))


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
    empty!(Plots.sp_clims)
    empty!(Plots.series_clims)
end
for i = 1:20 # insert 20 more of the same frame at end
    Plots.frame(anim)
end
mp4(anim, joinpath("output", "us_animation_map.mp4"), fps = 7)
