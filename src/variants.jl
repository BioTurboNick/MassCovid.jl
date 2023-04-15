using CSV
using DataFrames
using Dates
using Downloads
using Plots
using Smoothers

function downloadvariantreport()
    path = joinpath("input", "variantreport.csv")
    Downloads.download("https://data.cdc.gov/api/views/jr58-6ysp/rows.csv?accessType=DOWNLOAD", path)
end

function downloadstatecasedata()
    path = joinpath("input", "us-states.csv")
    Downloads.download("https://api.covidactnow.org/v2/states.timeseries.csv?apiKey=11682d9832ff4a4caabc54c0451b8e76", path)
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

mindatedate = minimum(mostrecentdata.week_ending_date) - Day(3)
maxdatedate = maximum(mostrecentdata.week_ending_date) - Day(3)
mindate = Dates.format(mindatedate, dateformat"m/d/yy")
maxdate = Dates.format(maxdatedate, dateformat"m/d/yy")

candata = CSV.read(downloadstatecasedata(), DataFrame)
filter!(:date => x -> maxdatedate ≥ x ≥ mindatedate, candata)

nweeks = (maxdatedate - mindatedate) ÷ Day(7)

bystate = groupby(candata, :state)
statecases = map(enumerate(bystate)) do (i, s)
    weeklycases = s[8:7:end, Symbol("actuals.cases")] .- s[1:7:end-7, Symbol("actuals.cases")]
    weeklycases[ismissing.(weeklycases)] .= 0
    weeklycases[weeklycases .< 0] .= 0

    if length(weeklycases) < nweeks
        append!(weeklycases, fill(0, nweeks - length(weeklycases)))
    end
    weeklycases = ([0.0; 0.0; sma(Int64[weeklycases...], 3)] .+ weeklycases) / 2
    (s[1, :state], weeklycases)
end

regionstates = Dict(
    1 => ["CT", "ME", "MA", "NH", "RI", "VT"],
    2 => ["NJ", "NY", "VI", "PR"],
    3 => ["DE", "DC", "MD", "PA", "VA", "WV"],
    4 => ["AL", "FL", "GA", "KY", "MS", "NC", "SC", "TN"],
    5 => ["IL", "IN", "MI", "MN", "OH", "WI"],
    6 => ["AR", "LA", "NM", "OK", "TX"],
    7 => ["IA", "KS", "MO", "NE"],
    8 => ["CO", "MT", "ND", "SD", "UT", "WY"],
    9 => ["AZ", "CA", "HI", "NV", "AS", "GU", "NMI"],
    10 => ["AK", "ID", "OR", "WA"],
)

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

#  TODO: remove low variants

byregion = groupby(mostrecentdata, :usa_or_hhsregion)

regionplots = map(enumerate(byregion)) do (i, br)
    p1 = plot(legend = :outerright, size = (768, 384))
    p2 = plot(legend = :outerright, size = (768, 384))
    p3 = plot(legend = :outerright, size = (768, 384))
    byvariant = groupby(br, :variant)
    maxcases = 0
    foreach(byvariant) do v
        rvcases = regioncases[v[1, :usa_or_hhsregion]]
        replace!(x -> x === missing ? 0.0 : x, rvcases)
        vshare = v.share[2:end]
        vshare_lo = v.share_lo[2:end]
        vshare_hi = v.share_hi[2:end]
        vweekending = v.week_ending_date[2:end]
        println(nrow(v))
        if nrow(v) < nweeks + 1
            nweekspad = fill(0.0, nweeks - nrow(v) + 1)
            vshare = vcat(vshare, nweekspad)
            vshare_lo = vcat(vshare_lo, nweekspad)
            vshare_hi = vcat(vshare_hi, nweekspad)
            vweekending = vcat(vweekending, fill(vweekending[end], nweeks + 1 - nrow(v)) .+ [Day(7) * i for i ∈ 1:nweeks + 1 - nrow(v)])
        end

        variantcases = vshare .* rvcases
        v.variant[1] == "XBB.1.5" && println(variantcases)
        replace!(x -> x === missing ? 0.0 : x, variantcases)
        variantsharelo = map(vshare_lo) do x
            (ismissing(x) || x == "NULL") ? 0.0 :
                x isa Float64 ? x :
                parse(Float64, x)
        end
        variantsharehi = map(vshare_hi) do x
            (ismissing(x) || x == "NULL") ? 0.0 :
                x isa Float64 ? x :
                parse(Float64, x)
        end
        variantcaseslow = variantsharelo .* rvcases
        variantcaseshigh = variantsharehi .* rvcases
        if v.variant[1] ∉ ("B.1.1.529", "BA.1.1")
            maxcases = max(maximum(variantcases), maxcases)
        end
        plot!(p1, vweekending, variantcases, label = v.variant[1],
            ribbon = (abs.(variantcaseslow .- variantcases), abs.(variantcaseshigh .- variantcases)), linewidth = 3)
        lowribbonlog = abs.(log10.(variantcaseslow) .- log10.(variantcases))
        lowribbonlog[isinf.(lowribbonlog)] .= 10.0
        highribbonlog = abs.(log10.(variantcaseshigh) .- log10.(variantcases))
        highribbonlog[isinf.(lowribbonlog)] .= 10.0
        plot!(p2, vweekending, log10.(variantcases), label = v.variant[1],
            ribbon = (lowribbonlog, highribbonlog), linewidth = 3)
    end
    plot!(p1, ylims = (0, maxcases * 1.1))
    mkpath("output")
    savefig(p1, joinpath("output", "variantcases $i.png"))
    plot!(p2, ylims = (1, log10(maxcases) * 1.1))
    savefig(p2, joinpath("output", "variantcases log10 $i.png"))

    # vshares = map(enumerate(byvariant)) do (i, v)
    #     vshare = v.share[2:end]
    #     if nrow(v) < nweeks
    #         nweekspad = fill(0.0, nweeks - nrow(v))
    #         vshare = vcat(vshare, nweekspad)
    #     end
    #     println(length(vshare))
    # end

    # areaplot!(p3, byvariant[1].week_ending_date[2:end], reduce(hcat, vshares), label = reduce(hcat, [v.variant[1] for v ∈ byvariant]))
    # plot!(p3, ylims = (1, maxcases * 1.2))
    # savefig(p3, joinpath("output", "variantcases area $i.png"))
    return p1, p2#, p3
end
