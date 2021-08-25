using Dates
using Shapefile
using Plots
using XLSX
using CSV
using Missings
using Statistics

function downloadcountycasedata()
    path = joinpath("input", "time_series_covid19_confirmed_US.csv")
    download("https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_US.csv", path)
end


ALASKA = 2
HAWAII = 15
PUERTORICO = 72

function loadcountydata()
    # 3, 14, 43, 52, 57 are nothing
    # States between 1 and 56
    shapepath = joinpath("usgeodata", "cb_2018_us_county_5m.shp")
    table = Shapefile.Table(shapepath)
    geoms = Shapefile.shapes(table)
    stateids = parse.(Int, table.STATEFP)
    states = (stateids .< 57) #.| (stateids .== PUERTORICO)
    selectedstates = stateids[states]
    selectedgeoms = geoms[states]

    county_sorted_order = sortperm(table.NAME[states])
    state_county_sorted_order = sortperm(selectedstates[county_sorted_order])
    
    poppath = joinpath("input", "co-est2019-alldata.csv")
    popfile = CSV.File(poppath)
    notstateline = popfile.COUNTY .!= 0

    selectedgeoms[county_sorted_order][state_county_sorted_order],
        selectedstates[county_sorted_order][state_county_sorted_order],
        popfile.POPESTIMATE2019[notstateline]
end

geoms, stateids, pop2019 = loadcountydata()

jhudata = CSV.File(downloadcountycasedata())

outofrows = startswith.(Missings.replace(jhudata.Admin2, ""), "Out of")
unassignedrows = startswith.(Missings.replace(jhudata.Admin2, ""), "Unassigned")
territoryrows = ismissing.(jhudata.Admin2)
prrows = jhudata.Province_State .== "Puerto Rico"
correctionsrows = contains.(Missings.replace(jhudata.Admin2, ""), "Correct")

countyrows = .!(outofrows .| territoryrows .| unassignedrows .| correctionsrows .| prrows)


# Should assign Unassigned to all Nebraska counties ***************************************
# Also check for anomalious maximums and remove them.

admin2 = Missings.replace(jhudata.Admin2[countyrows], "")
stname = Missings.replace(jhudata.Province_State[countyrows], "")
# Massachusetts remapping
madnrow = findfirst(==("Dukes and Nantucket"), admin2) # two counties
madrow = findfirst(==("Dukes"), admin2) # unused
manrow = findfirst(==("Nantucket"), admin2) #unused

# Alaska remapping
akblprow = findfirst(==("Bristol Bay plus Lake and Peninsula"), admin2) # two counties
akbrow = findfirst(==("Bristol Bay"), admin2) # unused
akcrow = findfirst(==("Chugach"), admin2) # part of Valez-Cordova
akcrrow = findfirst(==("Copper River"), admin2) # part of Valez-Cordova
akvcrow = findfirst(==("Valdez-Cordova"), admin2) # unused

# Utah remapping
utbrrow = findfirst(==("Bear River"), admin2) # Rich, Cache, Box Elder
utrichrow = findfirst(==("Rich"), admin2)
utcacherow = findfirst(==("Cache"), admin2)
utberow = findfirst(==("Box Elder"), admin2)
utcurow = findfirst(==("Central Utah"), admin2) # Piute, Wayne, Millard, Sevier, Sanpete, Juab
utpirow = findfirst(==("Piute"), admin2)
waynerows = findall(==("Wayne"), admin2)
utwaynerow = waynerows[findfirst(==("Utah"), stname[waynerows])]
utmilrow = findfirst(==("Millard"), admin2)
sevrows = findall(==("Sevier"), admin2)
utsevrow = sevrows[findfirst(==("Utah"), stname[sevrows])]
utsanpeterow = findfirst(==("Sanpete"), admin2)
utjuabrow = findfirst(==("Juab"), admin2)
utseurow = findfirst(==("Southeast Utah"), admin2) # Emery, Grand, Carbon
utemeryrow = findfirst(==("Emery"), admin2)
grandrows = findall(==("Grand"), admin2)
utgrandrow = grandrows[findfirst(==("Utah"), stname[grandrows])]
carbonrows = findall(==("Carbon"), admin2)
utcarbonrow = carbonrows[findfirst(==("Utah"), stname[carbonrows])]
utswurow = findfirst(==("Southwest Utah"), admin2) # Iron, Beaver, Garfield, Washington, Kane
ironrows = findall(==("Iron"), admin2)
utironrow = ironrows[findfirst(==("Utah"), stname[ironrows])] # multiple counties with the same name
beaverrows = findall(==("Beaver"), admin2)
utbeaverrow = beaverrows[findfirst(==("Utah"), stname[beaverrows])]
garfieldrows = findall(==("Garfield"), admin2)
utgarfieldrow = garfieldrows[findfirst(==("Utah"), stname[garfieldrows])]
washrows = findall(==("Washington"), admin2)
utwashrow = washrows[findfirst(==("Utah"), stname[washrows])]
kanerows = findall(==("Kane"), admin2)
utkanerow = kanerows[findfirst(==("Utah"), stname[kanerows])]
uttcrow = findfirst(==("TriCounty"), admin2) # Uintah, Daggett, Duchesne
utuintahrow = findfirst(==("Uintah"), admin2)
utdaggrow = findfirst(==("Daggett"), admin2)
utduchrow = findfirst(==("Duchesne"), admin2)
utwmrow = findfirst(==("Weber-Morgan"), admin2) # Weber, Morgan
utweberrow = findfirst(==("Weber"), admin2)
morganrows = findall(==("Morgan"), admin2)
utmorganrow = morganrows[findfirst(==("Utah"), stname[morganrows])]

mokcrow = findfirst(==("Kansas City"), admin2) # split between overlapping counties Jackson, Clay, Cass, Platte
jackrows = findall(==("Jackson"), admin2)
mojackrow = jackrows[findfirst(==("Missouri"), stname[jackrows])]
moclayrow = findfirst(==("Clay"), admin2)
clayrows = findall(==("Jackson"), admin2)
moclayrow = clayrows[findfirst(==("Missouri"), stname[clayrows])]
cassrows = findall(==("Cass"), admin2)
mocassrow = cassrows[findfirst(==("Missouri"), stname[cassrows])]
platterows = findall(==("Platte"), admin2)
moplatterow = platterows[findfirst(==("Missouri"), stname[platterows])]

countydata = jhudata[countyrows]
sevendaysago = [r[][12] for r ∈ eachrow(countydata)]

sevendayaverages = zeros(length(geoms))

for col ∈ (12 + 6):length(countydata[1])
    today = [r[][col] for r ∈ eachrow(countydata)]
    weektotal = today .- sevendaysago
    sevendaysago = [r[][col - 6] for r ∈ eachrow(countydata)]
    sevendayaverage = weektotal ./ 7

    # fix rows
    sevendayaverage[madrow] = sevendayaverage[manrow] = sevendayaverage[madnrow]
    sevendayaverage[akbrow] = sevendayaverage[akblprow]
    sevendayaverage[akvcrow] += sevendayaverage[akcrow] + sevendayaverage[akcrrow]
    sevendayaverage[utrichrow] = sevendayaverage[utcacherow] = sevendayaverage[utberow] = sevendayaverage[utbrrow]
    sevendayaverage[utpirow] = sevendayaverage[utwaynerow] = sevendayaverage[utmilrow] = sevendayaverage[utsevrow] = sevendayaverage[utsevrow] =
        sevendayaverage[utsanpeterow] = sevendayaverage[utjuabrow] = sevendayaverage[utcurow]
    sevendayaverage[utemeryrow] = sevendayaverage[utgrandrow] = sevendayaverage[utcarbonrow] = sevendayaverage[utseurow]
    sevendayaverage[utironrow] = sevendayaverage[utbeaverrow] = sevendayaverage[utgarfieldrow] = sevendayaverage[utwashrow] =
        sevendayaverage[utkanerow] = sevendayaverage[utswurow]
    sevendayaverage[utuintahrow] = sevendayaverage[utdaggrow] = sevendayaverage[utduchrow] = sevendayaverage[uttcrow]
    sevendayaverage[utweberrow] = sevendayaverage[utmorganrow] = sevendayaverage[utwmrow]
    mokcsplit = sevendayaverage[mokcrow] / 4
    sevendayaverage[mojackrow] += mokcsplit
    sevendayaverage[moclayrow] += mokcsplit
    sevendayaverage[mocassrow] += mokcsplit
    sevendayaverage[moplatterow] += mokcsplit

    deleteat!(sevendayaverage, sort!([madnrow, akcrrow, akcrow, utbrrow, utcurow, utseurow, utswurow, uttcrow, utwmrow, mokcrow]))

    sevendayaverages = hcat(sevendayaverages, sevendayaverage)
end

sevendayaverages ./= pop2019
sevendayaverages ./= maximum(sevendayaverages, dims = 2)


alaskageoms = geoms[stateids .== ALASKA]
hawaiigeoms = geoms[stateids .== HAWAII]
#puertoricogeoms = geoms[stateids .== PUERTORICO]
lower48geoms = geoms[stateids .∉ Ref([ALASKA, HAWAII, PUERTORICO])]

colors = map(x -> cgrad(:thermal)[x], sevendayaverages)
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
        grid=false, showaxis=false, ticks=false, aspect_ratio=1.2, title="United States COVID-19 Hot Spots\n$(date)\nNicholas C Bauer PhD | Twitter: @bioturbonick",
        titlefontcolor=:white, background_color=:black, linecolor=cgrad(:thermal)[0.0])
    plot!(lower48plot, alaskageoms, fillcolor=permutedims(alaskacolors[:, i]),
        grid=false, showaxis=false, ticks=false, xlims=(-180,-130), ylims=(51, 78), aspect_ratio=2,
        linecolor=cgrad(:thermal)[0.0],
        inset=(1, bbox(0.0, 0.0, 0.3, 0.3, :bottom, :left)), subplot=2)
    plot!(lower48plot, hawaiigeoms, fillcolor=permutedims(hawaiicolors[:, i]),
        grid=false, showaxis=false, ticks=false, xlims=(-160, -154), ylims=(18, 23),
        linecolor=cgrad(:thermal)[0.0],
        inset=(1, bbox(0.25, 0.0, 0.2, 0.2, :bottom, :left)), subplot=3)
    Plots.frame(anim)
    date += Day(1)
end
for i = 1:20 # insert 20 more of the same frame at end
    Plots.frame(anim)
end
gif(anim, joinpath("output", "us_animation_map.gif"), fps = 7)

# try to update colors instead of redrawing whole plot?
