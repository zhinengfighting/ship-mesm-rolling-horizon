%% Reproduce the case and method comparisons of the paper
% Z. Fei et al., "Rolling Horizon Energy Management of a Green Multi-Energy Ship Microgrid
% with Voyage Routing and Waste Heat Recovery", Journal of Marine Engineering & Technology, 2026.
%
% Run from the repository root. Requires MATLAB, YALMIP and Gurobi.
% Stage 1 solves the day-ahead model of each case; stage 2 runs the real-time layer.

clear; clc; close all;
assert(isfolder('src') && isfolder('data'), 'Run run_all.m from the repository root.');
if ~isfolder('results'), mkdir('results'); end
addpath(genpath('src'));

%% Stage 1: day-ahead scheduling (each script saves results/day_ahead_caseN.mat)
case1_fixed_speed;
case2_no_whrs;
case3_no_eeoi;
case4_proposed;

%% Stage 2: real-time operation
% Cases 1-4 with the rolling horizon (Tp = 4)
for case_id = 1:4
    clearvars -except case_id
    Tp = 4;
    rolling_horizon;
    close all
end

% Method 2: myopic policy on Case 4 (Tp = 1)
clearvars; case_id = 4; Tp = 1;
rolling_horizon;

% Method 1: deterministic dispatch of the Case 4 plan
clearvars;
deterministic_baseline;
close all

%% Summary table (real-time settled costs, $)
clearvars;
labels = {'Case 1 (RH)'; 'Case 2 (RH)'; 'Case 3 (RH)'; 'Case 4 (RH, proposed)'; ...
          'Method 1 (deterministic)'; 'Method 2 (myopic)'};
files  = {'rolling_case1_Tp4', 'rolling_case2_Tp4', 'rolling_case3_Tp4', 'rolling_case4_Tp4', ...
          'baseline_results', 'rolling_case4_Tp1'};
C = zeros(numel(files), 8);
for i = 1:numel(files)
    S = load(fullfile('results', [files{i} '.mat']));
    if isfield(S, 'a_RT'), C(i,:) = S.a_RT; else, C(i,:) = S.a_BL; end
end
summary = array2table(C, 'RowNames', labels, ...
    'VariableNames', {'Fuel','Maintenance','Storage','StartUp','Emission','Purchase','Penalty','Total'});
disp(summary)
writetable(summary, fullfile('results','summary.csv'), 'WriteRowNames', true);

%% Figures of the proposed method
load(fullfile('results','rolling_case4_Tp4.mat'));
plot_rolling_results;
