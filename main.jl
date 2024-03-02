### Model Development Programming Exercise
### William Bennett
### 03/01/2024

### Written with Julia v1.10.1

## Instructions for running

# Change "directory path" to where this file and required .csv files are
# Needed packages automatically installed when code is run

## Preliminaries

# Set directory
directory_path = "C:\\Users\\William Bennett\\Documents\\GitHub\\cQuant.io";
cd(directory_path);

# Install packages (if not installed)
using Pkg;
package_list = ["CSV", "DataFrames", "Dates", "JLD2", "Plots", "Random", "ShiftedArrays","Statistics"];
Pkg.add(package_list);

# Load packages
using CSV, DataFrames, Dates, JLD2, Plots, Random, Statistics

### Task 1: Import data.

contracts = DataFrame(CSV.File("contracts.csv"));
ERCOT_DA_Prices_2016 = DataFrame(CSV.File("ERCOT_DA_Prices_2016.csv"));
ERCOT_DA_Prices_2017 = DataFrame(CSV.File("ERCOT_DA_Prices_2017.csv"));
ERCOT_DA_Prices_2018 = DataFrame(CSV.File("ERCOT_DA_Prices_2018.csv"));
ERCOT_DA_Prices_2019 = DataFrame(CSV.File("ERCOT_DA_Prices_2019.csv"));
GDA_TETSTX = DataFrame(CSV.File("GDA_TETSTX.csv"));
HENRY_HUB = DataFrame(CSV.File("HENRY HUB.csv"));
Plant_Parameters = DataFrame(CSV.File("Plant_Parameters.csv"));
rename!(Plant_Parameters, :FuelPriceName => "PriceName");

ERCOT_DA_Prices = vcat(ERCOT_DA_Prices_2016, 
                       ERCOT_DA_Prices_2017,
                       ERCOT_DA_Prices_2018,
                       ERCOT_DA_Prices_2019);

Fuel_Prices = vcat(GDA_TETSTX,
                   HENRY_HUB);
rename!(Fuel_Prices, :Variable => "PriceName")

### Task 2 and 3: Calculate basic descriptive statistics; Calculate volatility

# Initialize table we desire to insert statistics into
year_month_string = getindex.(ERCOT_DA_Prices[:,:Date], Ref(1:7));
ERCOT_DA_Prices = hcat(ERCOT_DA_Prices, year_month_string);
rename!(ERCOT_DA_Prices, :x1 => "year_month");

year_month = unique(select(ERCOT_DA_Prices, :year_month));
settlement_points = unique(select(ERCOT_DA_Prices, :SettlementPoint));
sp_repeat = repeat(settlement_points, inner = size(year_month,1));
ym_repeat = repeat(year_month, outer = size(settlement_points,1));

year = getindex.(ym_repeat, Ref(1:4));
rename!(year, :year_month => "Year");
month = getindex.(ym_repeat, Ref(6:7));
rename!(month, :year_month => "Month");

num_pairs = size(sp_repeat,1);

stats = DataFrame("Mean" => zeros(num_pairs), "Min" => zeros(num_pairs), "Max" => zeros(num_pairs), "SD" => zeros(num_pairs), "Volatility" => zeros(num_pairs));
price_statistics = hcat(sp_repeat, ym_repeat, year, month, stats);

# Cacluate statistics for 48 year-month-settlement point combinations
for i in 1:num_pairs
    temp_data = subset(ERCOT_DA_Prices, :SettlementPoint => a -> a .== price_statistics[i,:SettlementPoint], :year_month => b -> b .== price_statistics[i,:year_month]);
    # Some year-month-settlement point combinations have no data. If so, NaN
    if size(temp_data,1) != 0
        price_statistics[i,:Mean] = mean(temp_data[:, :Price]);
        price_statistics[i,:Min] = minimum(temp_data[:, :Price]);
        price_statistics[i,:Max] = maximum(temp_data[:, :Price]);
        price_statistics[i,:SD] = std(temp_data[:, :Price]);
        # Some prices are below zero, preventing log. If so, NaN
        if price_statistics[i,:Min] > 0
            price_statistics[i,:Volatility] = std(log.(temp_data[:, :Price]));
        else
            price_statistics[i,:Volatility] = NaN;
        end
    else
        price_statistics[i,:Mean] = NaN;
        price_statistics[i,:Min] = NaN;
        price_statistics[i,:Max] = NaN;
        price_statistics[i,:SD] = NaN;
        price_statistics[i,:Volatility] = NaN;
    end
end

### Task 4: Write the results to a file

# Remove year-month variable
select!(price_statistics, Not(:year_month));

# Export data to CSV file
CSV.write("MonthlyPowerPriceStatistics.csv", price_statistics);

### Task 5:

hourly_contracts = subset(contracts, :Granularity => a -> a .== "Hourly");
daily_contracts = subset(contracts, :Granularity => a -> a .== "Daily");

## With more time, I could clean the following task: I could make a loop over all 
## possible contract names, instead of doing the 4 separately, to allow for an
## arbitrary number of contracts. I could also make conditional statements so that
## if the current contract in the loop is daily (hourly) I apply the correct
## dating technique.

## Daily contracts

# Contract 1; S1
times = [daily_contracts[:,:StartDate][1]];
while times[end] != daily_contracts[:,:EndDate][1]
    print(times[end])
    push!(times, times[end] + Dates.Day(1));
end
num_times = size(times, 1);

S1_contracts = subset(daily_contracts, :ContractName => a -> a .== "S1");
repeat!(S1_contracts, num_times);
S1_contracts = hcat(S1_contracts, times);
rename!(S1_contracts, :x1 => "Date");

# Contract 2; 01
times = [daily_contracts[:,:StartDate][2]];
while times[end] != daily_contracts[:,:EndDate][2]
    print(times[end])
    push!(times, times[end] + Dates.Day(1));
end
num_times = size(times, 1);

O1_contracts = subset(daily_contracts, :ContractName => a -> a .== "O1");
repeat!(O1_contracts, num_times);
O1_contracts = hcat(O1_contracts, times)
rename!(O1_contracts, :x1 => "Date");

# Combine daily contracts
daily_contracts_dates = vcat(S1_contracts, O1_contracts);

## Hourly

## I wasn't able to find how to make Julia have hours added to dates in such a way
## that matches what is in the power price data. I could do an inefficient way with
## convoluted string manipulation, but I'd rather complete the rest of the
## tasks.

### Task 6: Join relevant prices

contracts_payoffs = innerjoin(daily_contracts_dates, Fuel_Prices, on = [:Date, :PriceName]);

### Task 7: Calculate payoffs

# Swap payoff function
function swap_fun(asset_price, strike_price, volume)
    output = (asset_price - strike_price) * volume;
    return(output);
end

# Options payoff function
function options_fun(asset_price, strike_price, volume, premium)
    output = (max(asset_price - strike_price, 0.0) - premium) * volume;
    return(output);
end

swap_payoff = swap_fun.(contracts_payoffs[:,:Price], contracts_payoffs[:,:StrikePrice], contracts_payoffs[:,:Volume]);
options_payoff = options_fun.(contracts_payoffs[:,:Price], contracts_payoffs[:,:StrikePrice], contracts_payoffs[:,:Volume], contracts_payoffs[:,:Premium]);

contracts_payoffs = hcat(contracts_payoffs, swap_payoff, options_payoff, makeunique=true);
rename!(contracts_payoffs, :x1 => "SwapPayoff", :x1_1 => "OptionsPayoff");

### Task 8: Calculate aggregate payoffs
year_month_string = getindex.(string.(contracts_payoffs[:,:Date]), Ref(1:7));
contracts_payoffs = hcat(contracts_payoffs, year_month_string);
rename!(contracts_payoffs, :x1 => "year_month");

year_month = unique(select(contracts_payoffs, :year_month));
contract_names = unique(select(contracts_payoffs, :ContractName));
cn_repeat = repeat(contract_names, inner = size(year_month,1));
ym_repeat = repeat(year_month, outer = size(contract_names,1));

year = getindex.(ym_repeat, Ref(1:4));
rename!(year, :year_month => "Year");
month = getindex.(ym_repeat, Ref(6:7));
rename!(month, :year_month => "Month");

num_pairs = size(cn_repeat,1);

stats = DataFrame("TotalPayoff" => zeros(num_pairs));
contracts_statistics = hcat(cn_repeat, ym_repeat, year, month, stats);

# Change 'missing' to 0 for certain options values
contracts_payoffs.OptionsPayoff = replace(contracts_payoffs.OptionsPayoff, missing => 0);

# Cacluate statistics for contract-year-month combinations
for i in 1:num_pairs
    temp_data = subset(contracts_payoffs, :ContractName => a -> a .== contracts_statistics[i,:ContractName], :year_month => b -> b .== contracts_statistics[i,:year_month]);
    contracts_statistics[i,:TotalPayoff] = sum(temp_data[:,:SwapPayoff] .+ temp_data[:,:OptionsPayoff]);
end

# Remove 0 Payoffs (was missing before)
subset!(contracts_statistics, :TotalPayoff .=> ByRow(!=(0)));

# Remove year-month variable
select!(contracts_statistics, Not(:year_month));

CSV.write("MonthlyContractPayoffs.csv", contracts_statistics);

### Task 10

# Running cost function
function running_cost_fun(fuel_price, fuel_transportation_cost, hear_rate, vom)
    output = ((fuel_price + fuel_transportation_cost) * hear_rate) + vom;
    return(output);
end

## I don't have time for the Plant Dispath Modeling question.
## I can briefly describe what I would do with more time.

## For Task 10, I would join the fuel price dataset with the plant parameters, so
## that for each combination of price name, year, and month in the fuel price data,
## I merge the relevent variables from the row in the plant parameters data that
## matches that combination. I could then map my running cost function to that new
## joined dataset.

## For Task 11, I would simply 'hcat' what the dataset and the function values I
## made in Task 10.

## For Task 12, I can easily check which rows of the previous dataset have market
## power price greater than running cost. 

## For Task 13, I can make a for-loop so that for each index of the loop, I
## I calculate the sum of the running margin for that section of time, and do the
## same comparison I did in Task 12.