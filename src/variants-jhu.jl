using CSV
using DataFrames
using Dates
using Downloads
using Plots

function downloadvariantreport()
    path = joinpath("input", "variantreport.csv")
    Downloads.download("https://data.cdc.gov/api/views/jr58-6ysp/rows.csv?accessType=DOWNLOAD", path)
end

function downloadcountycasedata()
    path = joinpath("input", "time_series_covid19_confirmed_US.csv")
    Downloads.download("https://github.com/CSSEGISandData/COVID-19/raw/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_US.csv", path)
end

variantdata = CSV.read(downloadvariantreport(), DataFrame)
transform!(variantdata,
    :week_ending => (x -> DateTime.(x, dateformat"m/d/Y H:M:S p")) => :week_ending_date,
    :published_date => (x -> DateTime.(x, dateformat"m/d/Y H:M:S p")) => :published_date_date)
sort!(variantdata, :published_date_date)

filter!(:week_ending_date => (x -> x ≥ Date(2021, 12, 1)), variantdata)

bypublishing = groupby(variantdata, :published_date_date)

mostrecentdata = bypublishing[end]
sort!(mostrecentdata, :week_ending_date)

# when the report comes out, the date is two days ahead of the case data, so we shift one less
mindate = Dates.format(minimum(mostrecentdata.week_ending_date) - Day(2), dateformat"m/d/yy")
maxdate = Dates.format(maximum(mostrecentdata.week_ending_date) - Day(2), dateformat"m/d/yy")

jhudata = CSV.read(downloadcountycasedata(), DataFrame)
colnames = propertynames(jhudata)
datarange = (findfirst(==(Symbol(mindate)), colnames) - 6 - 7):findlast(==(Symbol(maxdate)), colnames)
bystate = groupby(jhudata, :Province_State)

statecases = map(enumerate(bystate)) do (i, s)
    dailycases = sum(Array{Float64, 2}(s[!, datarange]), dims = 1) |> vec
    weeklycases = dailycases[8:7:end] .- dailycases[1:7:end-7]
    (s[1, :Province_State], weeklycases)
end

regionstates = Dict(
    1 => ["Connecticut", "Maine", "Massachusetts", "New Hampshire", "Rhode Island", "Vermont"],
    2 => ["New Jersey", "New York", "Virgin Islands", "Puerto Rico"],
    3 => ["Delaware", "District of Columbia", "Maryland", "Pennsylvania", "Virginia", "West Virginia"],
    4 => ["Alabama", "Florida", "Georgia", "Kentucky", "Mississippi", "North Carolina", "South Carolina", "Tennessee"],
    5 => ["Illinois", "Indiana", "Michigan", "Minnesota", "Ohio", "Wisconsin"],
    6 => ["Arkansas", "Louisiana", "New Mexico", "Oklahoma", "Texas"],
    7 => ["Iowa", "Kansas", "Missouri", "Nebraska"],
    8 => ["Colorado", "Montana", "North Dakota", "South Dakota", "Utah", "Wyoming"],
    9 => ["Arizona", "California", "Hawaii", "Nevada", "American Samoa", "Guam", "Northern Mariana Islands"],
    10 => ["Alaska", "Idaho", "Oregon", "Washington"],
)

nweeks = length(statecases[1][2])

regioncases = map(1:length(unique(mostrecentdata.usa_or_hhsregion)) - 1) do i
    region = regionstates[i]
    regioncases = reduce(filter(s -> s[1] ∈ region, statecases), init = zeros(nweeks)) do a, (state, cases)
        a .+ cases
    end
    (string(i) => max.(0, regioncases))
end

pushfirst!(regioncases, "USA" => reduce(statecases, init = zeros(nweeks)) do a, (state, cases)
    a .+ cases
end)

regioncases = Dict(regioncases...)

byregion = groupby(mostrecentdata, :usa_or_hhsregion)

regionplots = map(enumerate(byregion)) do (i, br)
    p1 = plot(legend = :outerright, size = (768, 384))
    p2 = plot(legend = :outerright, size = (768, 384))
    p3 = plot(legend = :outerright, size = (768, 384))
    byvariant = groupby(br, :variant)
    maxcases = 0
    foreach(byvariant) do v
        variantcases = v.share .* regioncases[v[1, :usa_or_hhsregion]]
        variantsharelo = map(v.share_lo) do x
            (ismissing(x) || x == "NULL") ? 0.0 :
                x isa Float64 ? x :
                parse(Float64, x)
        end
        variantsharehi = map(v.share_hi) do x
            (ismissing(x) || x == "NULL") ? 0.0 :
                x isa Float64 ? x :
                parse(Float64, x)
        end
        variantcaseslow = variantsharelo .* regioncases[v[1, :usa_or_hhsregion]]
        variantcaseshigh = variantsharehi .* regioncases[v[1, :usa_or_hhsregion]]
        if v.variant[1] ∉ ("B.1.1.529", "BA.1.1")
            maxcases = max(maximum(variantcases), maxcases)
        end
        plot!(p1, v.week_ending_date, variantcases, label = v.variant[1],
            ribbon = (abs.(variantcaseslow .- variantcases), abs.(variantcaseshigh .- variantcases)), linewidth = 3)
        lowribbonlog = abs.(log10.(variantcaseslow) .- log10.(variantcases))
        lowribbonlog[isinf.(lowribbonlog)] .= 10.0
        highribbonlog = abs.(log10.(variantcaseshigh) .- log10.(variantcases))
        highribbonlog[isinf.(lowribbonlog)] .= 10.0
        plot!(p2, v.week_ending_date, log10.(variantcases), label = v.variant[1],
            ribbon = (lowribbonlog, highribbonlog), linewidth = 3)
    end
    plot!(p1, ylims = (0, maxcases * 1.1))
    savefig(p1, joinpath("output", "variantcases $i.png"))
    plot!(p2, ylims = (1, log10(maxcases) * 1.1))
    savefig(p2, joinpath("output", "variantcases log10 $i.png"))
    areaplot!(p3, byvariant[1].week_ending_date, reduce(hcat, [v.share .* regioncases[v[1, :usa_or_hhsregion]] for v ∈ byvariant]), label = reduce(hcat, [v.variant[1] for v ∈ byvariant]))
    plot!(p3, ylims = (1, maxcases * 1.2))
    savefig(p3, joinpath("output", "variantcases area $i.png"))
    return p1, p2, p3
end
