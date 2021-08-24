using Dates
using Shapefile
using Plots
using XLSX
using CSV
using Missings
using Statistics

ALASKA = 2
HAWAII = 15
PUERTORICO = 72

# 3, 14, 43, 52, 57 may be nothing?

# States between 1 and 56

function loadcountydata()
    shapepath = joinpath("usgeodata", "cb_2017_us_county_500k.shp")
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

jhudata = CSV.File(joinpath("input", "time_series_covid19_confirmed_US.csv"))

outofrows = startswith.(Missings.replace(jhudata.Admin2, ""), "Out of")
unassignedrows = startswith.(Missings.replace(jhudata.Admin2, ""), "Unassigned")
territoryrows = ismissing.(jhudata.Admin2)
prrows = jhudata.Province_State .== "Puerto Rico"
correctionsrows = contains.(Missings.replace(jhudata.Admin2, ""), "Correct")

countyrows = .!(outofrows .| territoryrows .| unassignedrows .| correctionsrows .| prrows)

admin2 = Missings.replace(jhudata.Admin2[countyrows], "")
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
utwaynerow = findfirst(==("Wayne"), admin2)
utmilrow = findfirst(==("Millard"), admin2)
utsevrow = findfirst(==("Sevier"), admin2)
utsanpeterow = findfirst(==("Sanpete"), admin2)
utjuabrow = findfirst(==("Juab"), admin2)
utseurow = findfirst(==("Southeast Utah"), admin2) # Emery, Grand, Carbon
utemeryrow = findfirst(==("Emery"), admin2)
utgrandrow = findfirst(==("Grand"), admin2)
utcarbonrow = findfirst(==("Carbon"), admin2)
utswurow = findfirst(==("Southwest Utah"), admin2) # Iron, Beaver, Garfield, Washington, Kane
utironrow = findfirst(==("Iron"), admin2)
utbeaverrow = findfirst(==("Beaver"), admin2)
utgarfieldrow = findfirst(==("Garfield"), admin2)
utwashrow = findfirst(==("Washington"), admin2)
utkanerow = findfirst(==("Kane"), admin2)
uttcrow = findfirst(==("TriCounty"), admin2) # Uintah, Daggett, Duchesne
utuintahrow = findfirst(==("Uintah"), admin2)
utdaggrow = findfirst(==("Daggett"), admin2)
utduchrow = findfirst(==("Duchesne"), admin2)
utwmrow = findfirst(==("Weber-Morgan"), admin2) # Weber, Morgan
utweberrow = findfirst(==("Weber"), admin2)
utmorganrow = findfirst(==("Morgan"), admin2)
mokcrow = findfirst(==("Kansas City"), admin2) # split between overlapping counties Jackson, Clay, Cass, Platte
mojackrow = findfirst(==("Jackson"), admin2)
moclayrow = findfirst(==("Clay"), admin2)
mocassrow = findfirst(==("Cass"), admin2)
moplatterow = findfirst(==("Platte"), admin2)

countydata = jhudata[countyrows]
sevendaysago = [r[][12] for r ∈ eachrow(countydata)]

sevendayaverages = zeros(length(geoms))

for col ∈ (12 + 7):length(countydata[1])
    today = [r[][col] for r ∈ eachrow(countydata)]
    weektotal = today .- sevendaysago
    sevendaysago = [r[][col - 7] for r ∈ eachrow(countydata)]
    sevendayaverage = weektotal ./ 7

    # fix rows
    sevendayaverage[madrow] = sevendayaverage[manrow] = sevendayaverage[madnrow]
    sevendayaverage[akbrow] = sevendayaverage[akblprow]
    sevendayaverage[akvcrow] += sevendayaverage[akcrow] + sevendayaverage[akcrrow]
    sevendayaverage[utrichrow] = sevendayaverage[utcacherow] = sevendayaverage[utberow] = sevendayaverage[utbrrow]
    sevendayaverage[utpirow] = sevendayaverage[utwaynerow] = sevendayaverage[utmilrow] = sevendayaverage[utsevrow] = sevendayaverage[utsevrow] =
        sevendayaverage[utsanpeterow] = sevendayaverage[utcurow]
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

anim = Plots.Animation()
date = Date("1/22/2020", dateformat"mm/dd/yyyy")
for i ∈ 1:length(eachrow(lower48colors))
    lower48plot = plot(lower48geoms, fillcolor=permutedims(lower48colors[:, i]), size=(2048, 1280),
        grid=false, showaxis=false, ticks=false, aspect_ratio=1.2, title="United States COVID-19 Hot Spots\n$(date)\nNicholas C. Bauer | Twitter: @bioturbonick",
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
for i = 1:4 # insert 4 more of the same frame at end
    Plots.frame(anim)
end
gif(anim, joinpath("output", "us_animation_map.gif"), fps = 5)
gif(anim, joinpath("output", "us_animation_map.mp4"), fps = 5)
