using XLSX


function loadweekdata(datestring, towns)
    path = download("https://www.mass.gov/doc/weekly-public-health-report-raw-data-$(datestring)-2020/download")
    data = XLSX.readxlsx(path)
    sheet = XLSX.hassheet(data, "City_town") ? data["City_town"] : data["City_Town_Data"]
    # sheet["C1"] == "Two Week Case Count" && sheet["D1"] == "Average Daily Incidence Rate per 100000"
    
    countsraw = sheet["C2:C352"]
    counts = [c == "<5" ? 2 : c for c ∈ countsraw] # replace "<5" with a number in range
    rates = sheet["D2:D352"]
    state_rate = sheet["D354"]
    return counts, rates, state_rate
end

files = ["august-12",
         "august-19",
         "august-26",
         "september-2",
         "september-9",
         "september-16",
         "september-23",
         "september-30",
         "october-7",
         "october-14",
         "october-22",
         "october-29",
         "november-5"]

mwra_towns = ["WILMINGTON",
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
              "HINGHAM"]

   
