using Dates
using Shapefile
using Plots
using XLSX
using CSV
using Missings
using Statistics
using InvertedIndices

function downloadcountycasedata()
    path = joinpath("input", "time_series_covid19_confirmed_US.csv")
    download("https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_US.csv", path)
end

ALABAMA = 1
ALASKA = 2
ARIZONA = 4
ARKANSAS = 5
CALIFORNIA = 6
COLORADO = 8
CONNECTICUT = 9
DELAWARE = 10
DC = 11
FLORIDA = 12
GEORGIA = 13
HAWAII = 15
IDAHO = 16
ILLINOIS = 17
INDIANA = 18
IOWA = 19
KANSAS = 20
KENTUCKY = 21
LOUISIANA = 22
MAINE = 23
MARYLAND = 24
MASSACHUSETTS = 25
MICHIGAN = 26
MINNESOTA = 27
MISSISSIPPI = 28
MISSOURI = 29
MONTANA = 30
NEBRASKA = 31
NEVADA = 32
NEWHAMPSHIRE = 33
NEWJERSEY = 34
NEWMEXICO = 35
NEWYORK = 36
NORTHCAROLINA = 37
NORTHDAKOTA = 38
OHIO = 39
OKLAHOMA = 40
OREGON = 41
PENNSYLVANIA = 42
RHODEISLAND = 44
SOUTHCAROLINA = 45
SOUTHDAKOTA = 46
TENNESSEE = 47
TEXAS = 48
UTAH = 49
VERMONT = 50
VIRGINIA = 51
WASHINGTON = 53
WESTVIRGINIA = 54
WISCONSIN = 55
WYOMING = 56
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
    pop_county_sorted_order = sortperm(popfile.CTYNAME[notstateline])
    pop_state_county_sorted_order = sortperm(popfile.STNAME[notstateline][pop_county_sorted_order])

    selectedgeoms[county_sorted_order][state_county_sorted_order],
        selectedstates[county_sorted_order][state_county_sorted_order],
        popfile.POPESTIMATE2019[notstateline][pop_county_sorted_order][pop_state_county_sorted_order]
end

geoms, stateids, pop2019 = loadcountydata()

jhudata = CSV.File(downloadcountycasedata())

outofrows = startswith.(Missings.replace(jhudata.Admin2, ""), "Out of")

territoryrows = ismissing.(jhudata.Admin2)
prrows = jhudata.Province_State .== "Puerto Rico"
correctionsrows = contains.(Missings.replace(jhudata.Admin2, ""), "Correct")

countyrows = .!(outofrows .| territoryrows .| correctionsrows .| prrows)

# Also check for anomalious maximums and remove them.

admin2 = Missings.replace(jhudata.Admin2[countyrows], "")
unassignedrows = findall(==("Unassigned"), admin2)
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
clayrows = findall(==("Clay"), admin2)
moclayrow = clayrows[findfirst(==("Missouri"), stname[clayrows])]
cassrows = findall(==("Cass"), admin2)
mocassrow = cassrows[findfirst(==("Missouri"), stname[cassrows])]
platterows = findall(==("Platte"), admin2)
moplatterow = platterows[findfirst(==("Missouri"), stname[platterows])]

averagelength = 7

countydata = jhudata[countyrows]
multidaysago = [r[][12] for r ∈ eachrow(countydata)]

multidayaverages = fill(0, length(geoms), 0)

for col ∈ (12 + averagelength):length(countydata[1])
    today = [r[][col] for r ∈ eachrow(countydata)]
    weektotal = today .- multidaysago
    multidaysago = [r[][col - averagelength + 1] for r ∈ eachrow(countydata)]
    multidayaverage = weektotal ./ averagelength

    #distribute Unassigned
    for st ∈ unique(stname)
        antiindexes = union(findall(==("Unassigned"), admin2), [madnrow, akcrrow, akcrow, utbrrow, utcurow, utseurow, utswurow, uttcrow, utwmrow, mokcrow])
        stnamereduced = stname[Not(antiindexes)]
        admin2reduced = admin2[Not(antiindexes)]
        countypops = pop2019[stnamereduced .== st]
        countynames = admin2reduced[stnamereduced .== st]
        statepop = sum(countypops)
        countypopfrac = countypops ./ statepop
        multidayaverage[Not(union(findall(!=(st), stname), antiindexes))] .+= multidayaverage[(stname .== st) .& (admin2 .== "Unassigned")] .* countypopfrac
        if st == "Utah"
            multidayaverage[utrichrow] = multidayaverage[utbrrow] * countypopfrac[findfirst(==("Rich"), countynames)]
            multidayaverage[utcacherow] = multidayaverage[utbrrow] * countypopfrac[findfirst(==("Cache"), countynames)]
            multidayaverage[utberow] = multidayaverage[utbrrow] * countypopfrac[findfirst(==("Box Elder"), countynames)]
            multidayaverage[utpirow] = multidayaverage[utcurow] * countypopfrac[findfirst(==("Piute"), countynames)]
            multidayaverage[utwaynerow] = multidayaverage[utcurow] * countypopfrac[findfirst(==("Wayne"), countynames)]
            multidayaverage[utmilrow] = multidayaverage[utcurow] * countypopfrac[findfirst(==("Millard"), countynames)]
            multidayaverage[utsevrow] = multidayaverage[utcurow] * countypopfrac[findfirst(==("Sevier"), countynames)]
            multidayaverage[utsanpeterow] = multidayaverage[utcurow] * countypopfrac[findfirst(==("Box Elder"), countynames)]
            multidayaverage[utjuabrow] = multidayaverage[utcurow] * countypopfrac[findfirst(==("Sanpete"), countynames)]
            multidayaverage[utemeryrow] = multidayaverage[utseurow] * countypopfrac[findfirst(==("Emery"), countynames)]
            multidayaverage[utgrandrow] = multidayaverage[utseurow] * countypopfrac[findfirst(==("Grand"), countynames)]
            multidayaverage[utcarbonrow] = multidayaverage[utseurow] * countypopfrac[findfirst(==("Carbon"), countynames)]
            multidayaverage[utironrow] = multidayaverage[utswurow] * countypopfrac[findfirst(==("Iron"), countynames)]
            multidayaverage[utbeaverrow] = multidayaverage[utswurow] * countypopfrac[findfirst(==("Beaver"), countynames)]
            multidayaverage[utgarfieldrow] = multidayaverage[utswurow] * countypopfrac[findfirst(==("Garfield"), countynames)]
            multidayaverage[utwashrow] = multidayaverage[utswurow] * countypopfrac[findfirst(==("Washington"), countynames)]
            multidayaverage[utkanerow] = multidayaverage[utswurow] * countypopfrac[findfirst(==("Kane"), countynames)]
            multidayaverage[utuintahrow] = multidayaverage[uttcrow] * countypopfrac[findfirst(==("Uintah"), countynames)]
            multidayaverage[utdaggrow] = multidayaverage[uttcrow] * countypopfrac[findfirst(==("Daggett"), countynames)]
            multidayaverage[utduchrow] = multidayaverage[uttcrow] * countypopfrac[findfirst(==("Duchesne"), countynames)]
            multidayaverage[utweberrow] = multidayaverage[utwmrow] * countypopfrac[findfirst(==("Weber"), countynames)]
            multidayaverage[utmorganrow] = multidayaverage[utwmrow] * countypopfrac[findfirst(==("Morgan"), countynames)]
        elseif st == "Alaska"
            countynames[findfirst(==("Bristol Bay plus Lake and Peninsula"), countynames)] = "Lake and Peninsula"
            sortorder = sortperm(countynames)
            sort!(countynames)
            multidayaverage[akbrow] = multidayaverage[akblprow] * countypopfrac[findfirst(==("Bristol Bay"), countynames)]
            multidayaverage[akblprow] *= countypopfrac[findfirst(==("Lake and Peninsula"), countynames)]
            multidayaverage[akvcrow] += multidayaverage[akcrow] + multidayaverage[akcrrow]
            # reorder to account for Lake and Peninsula
            multidayaverage[Not(union(findall(!=(st), stname), antiindexes))] = multidayaverage[Not(union(findall(!=(st), stname), antiindexes))][sortorder]
        elseif st == "Massachusetts"
            multidayaverage[madrow] = multidayaverage[madnrow] * countypopfrac[findfirst(==("Dukes"), countynames)]
            multidayaverage[manrow] = multidayaverage[madnrow] * countypopfrac[findfirst(==("Nantucket"), countynames)]
        elseif st == "Missouri"
            multidayaverage[mojackrow] += multidayaverage[mokcrow] * countypopfrac[findfirst(==("Jackson"), countynames)]
            multidayaverage[moclayrow] += multidayaverage[mokcrow] * countypopfrac[findfirst(==("Clay"), countynames)]
            multidayaverage[mocassrow] += multidayaverage[mokcrow] * countypopfrac[findfirst(==("Cass"), countynames)]
            multidayaverage[moplatterow] += multidayaverage[mokcrow] * countypopfrac[findfirst(==("Platte"), countynames)]
        end
    end
    
    deleteat!(multidayaverage, sort!([madnrow, akcrrow, akcrow, utbrrow, utcurow, utseurow, utswurow, uttcrow, utwmrow, mokcrow, unassignedrows...]))

    multidayaverages = hcat(multidayaverages, multidayaverage)
end

multidayaverages ./= pop2019

# adjust for data jumps
function countyfix!(multidayaverages, stateids, stateid, start, stop, counties)
    selector = findfirst(stateids .== stateid) .+ counties .- 1
    range = start:stop
    multidayaverages[selector, range] .-= mean(multidayaverages[selector, range], dims = 2) .- mean(multidayaverages[selector, [start - 1, stop + 1]], dims = 2)
end
function statefix!(multidayaverages, stateids, stateid, start, stop)
    selector = stateids .== stateid
    range = start:stop
    multidayaverages[selector, range] .-= mean(multidayaverages[selector, range], dims = 2) .- mean(multidayaverages[selector, [start - 1, stop + 1]], dims = 2)
end
countyfix!(multidayaverages, stateids, ALABAMA, 390, 393, [46])
countyfix!(multidayaverages, stateids, ALABAMA, 396, 400, [46])
countyfix!(multidayaverages, stateids, ALABAMA, 240, 246, [63])
countyfix!(multidayaverages, stateids, ALABAMA, 269, 275, [8, 31, 34, 35])
countyfix!(multidayaverages, stateids, ALABAMA, 268, 274, [49, 65])
countyfix!(multidayaverages, stateids, ALABAMA, 240, 246, [17, 20, 30, 39])
countyfix!(multidayaverages, stateids, ALABAMA, 277, 283, [17, 30, 39])
countyfix!(multidayaverages, stateids, ALABAMA, 112, 118, [12])
countyfix!(multidayaverages, stateids, ALABAMA, 194, 198, [13])
countyfix!(multidayaverages, stateids, ALABAMA, 192, 200, [13])
statefix!(multidayaverages, stateids, ALABAMA, 412, 418)
countyfix!(multidayaverages, stateids, ALABAMA, 400, 406, [5, 7, 8, 15, 22, 25, 28, 36, 43, 44, 48, 58, 59, 67])
statefix!(multidayaverages, stateids, ALABAMA, 473, 477)
statefix!(multidayaverages, stateids, ALABAMA, 472, 478)
statefix!(multidayaverages, stateids, ALABAMA, 471, 479)
countyfix!(multidayaverages, stateids, ALASKA, 327, 333, [10])
countyfix!(multidayaverages, stateids, ALASKA, 349, 355, [10])
countyfix!(multidayaverages, stateids, ALASKA, 456, 462, [10, 28]) # will need another for recent
countyfix!(multidayaverages, stateids, ALASKA, 507, 518, [28])
countyfix!(multidayaverages, stateids, ALASKA, 377, 383, [29])
countyfix!(multidayaverages, stateids, ARIZONA, 437, 443, [4, 5, 10])
countyfix!(multidayaverages, stateids, ARIZONA, 428, 436, [1])
countyfix!(multidayaverages, stateids, ARIZONA, 403, 408, [1, 14])
countyfix!(multidayaverages, stateids, ARIZONA, 402, 409, [1, 14])
statefix!(multidayaverages, stateids, ARKANSAS, 397, 403)
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


multidayaverages ./= maximum(multidayaverages, dims = 2)
#multidayaverages ./= mean(maximum(multidayaverages, dims = 2))


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
