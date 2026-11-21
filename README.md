# Rolling-horizon energy management of a multi-energy ship microgrid

MATLAB/YALMIP code for

> Z. Fei, K. Tammi, I. Harjunkoski, A. Karhinen, R. Dickson, Z. Li, "Rolling Horizon Energy Management of a Green Multi-Energy Ship Microgrid with Voyage Routing and Waste Heat Recovery," *Journal of Marine Engineering & Technology*, 2026. DOI: [10.1080/20464177.2026.2728778](https://doi.org/10.1080/20464177.2026.2728778)

## What the model does

A ship carries several energy carriers (electricity, heat, hydrogen and freshwater) that are produced, stored and consumed by coupled units. The code schedules these units together with the voyage speed over a 13.5-hour voyage (27 half-hour periods: sailing, berthing, sailing). It works in two stages:

1. **Day-ahead scheduling** (`src/day_ahead/`). One MILP decides:
   - unit commitment of four diesel generators, with a piecewise-linear fuel cost and DG waste heat recovery (WHRS);
   - two fuel cells, power-to-heat units and seawater desalination;
   - four storage units (battery, thermal, hydrogen, water);
   - shore power, hydrogen and water purchase at berth;
   - the ship speed in each period, with weather-induced added resistance on the selected route and an EEOI (carbon intensity) limit.
2. **Real-time operation** (`src/real_time/rolling_horizon.m`). Electrical and thermal loads deviate from the forecast (AR(1) errors). At each period, a window of `Tp` periods is re-optimised and only the first period is implemented:
   - DG on/off status and the voyage plan are kept from stage 1;
   - unit outputs, shore power and a bounded storage deviation are re-dispatched;
   - load shedding or curtailment is used only as a penalised last resort.

The two stages exchange data through a small set of signals saved in `results/day_ahead_caseN.mat`:
- commitment status, speed and propulsion load;
- storage net-exchange plan;
- purchase plan and day-ahead costs.

## Repository layout

```
run_all.m                         reproduces all cases and methods, writes results/summary.csv
data/added_resistance.xlsx        added-resistance profiles of the candidate routes
data/forecast_errors.mat          AR(1) electrical/thermal load forecast errors (e_P, e_T)
src/day_ahead/case1_fixed_speed.m Case 1: nominal speed (no voyage flexibility)
src/day_ahead/case2_no_whrs.m     Case 2: no waste heat recovery
src/day_ahead/case3_no_eeoi.m     Case 3: no EEOI constraint
src/day_ahead/case4_proposed.m    Case 4: proposed model
src/real_time/rolling_horizon.m   rolling-horizon real-time layer (case_id, Tp)
src/real_time/deterministic_baseline.m  Method 1: day-ahead plan executed without re-optimisation
src/plots/plot_rolling_results.m  energy-balance and corrective-action figures
```

## Requirements and use

- MATLAB (tested with R2025b), [YALMIP](https://yalmip.github.io) and Gurobi (academic licence).
- From the repository root, run `run_all` in MATLAB. A single case can be run with, for example:

```matlab
addpath(genpath('src'));
case4_proposed;                          % day-ahead plan -> results/day_ahead_case4.mat
case_id = 4; Tp = 4; rolling_horizon;    % real-time layer -> results/rolling_case4_Tp4.mat
plot_rolling_results;
```

Setting `Tp = 1` gives the myopic policy (Method 2 in the paper).

## Results

`run_all` takes a few minutes on a laptop and writes `results/summary.csv`. Total real-time cost ($), reproduced with MATLAB R2025b, YALMIP 20250626 and Gurobi, compared with Tables 3 and 4 of the paper:

| Setting | This repository | Paper |
|---|---:|---:|
| Case 1: nominal speed | 80,163.07 | 80,144.55 |
| Case 2: no WHRS | 75,086.58 | 75,057.27 |
| Case 3: no EEOI | 72,391.52 | 72,396.79 |
| Case 4 / proposed (RH, Tp = 4) | 73,383.09 | 73,376.84 |
| Method 1: deterministic | 74,754.28 | 74,754.29 |
| Method 2: myopic (Tp = 1) | 73,541.82 | 73,542.26 |

The small differences (below 0.05%) come from the MILP optimality gap and the solver version. The mean solve time of one rolling-horizon window is about 0.1-0.3 s.

Two settings in `rolling_horizon.m` follow the paper and depend on the case:
- Cases 1 and 2 allow load shedding up to the full load (`shed_cap = 1`); the other runs allow up to 50%.
- Case 2 also has no waste heat recovery in the real-time layer (`whrs_on = 0`).

## Licence

MIT. Contact: Zhineng Fei, Aalto University (zhineng.fei@aalto.fi).
