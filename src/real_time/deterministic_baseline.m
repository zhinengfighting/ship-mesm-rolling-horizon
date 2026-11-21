%% Method 1: deterministic dispatch (benchmark for the rolling horizon)
% The day-ahead plan is executed as is; forecast errors are absorbed only by load shedding / curtailment.
% Used to quantify the benefit of the rolling horizon.
% =====================================================================
yalmip;

load(fullfile('results','day_ahead_case4.mat'));
T = 27;
Ndg = 4;

%% 1. Loads and prices (same as rolling_horizon.m)
Pslt = [11.85215591 11.15528784 11.59678649 9.853234474 11.15590756 10.58318647 11.39864919 13.59993783 16.3493441 15.41264832 18.11754212 16.60401196 14.558626 12.46778381 11.67022563 11.8730974 9.537735061 9.769408322 10.35601844 13.75774315 15.05774315 15.95229379 16.53838229 17.12997976 18.54852914 19.82852914 18.63364333]*0.12;
Tsl = [1.469210175 1.463902755 1.579853361 1.615255603 1.768027544 1.789892552 1.891717933 1.935626216 2.283887416 2.100134909 2.276713185 2.158696426 2.029496918 1.861635173 1.85066003 1.829410127 1.709007485 1.648530968 1.552572224 1.591955146 1.401651477 1.393687064 1.384548591 1.33430889 1.337182364 1.193968276 1.157404035];
Hsl = [13.5 15 19.5 25.5 26.835 28.5 28.395 27 26.475 24 23.19 18 18.3 15 14.4 13.5 19.5 22.2 25.05 27 27.6 28.5 28.8 25.5 24.6 22.5 18];
Wsl = [17.856 26.224 28.8464 34.8576 35.206176 36.0896 35.367808 36.208 34.3976 35.9808 34.541568 26.8576 21.48608 20.4 16 18.416 34.416 28.5888 28 27.376 24 22.672 21.99184 21.328 21.44 21.5328 19.9232];
Ppv = [103.2 162.1333333 179.2 252.736 273.7973333 296.044 314.356 324.02 311.3133333 249.7393333 244.794 247.1863333 239.8803333 200.736 192.864 192.3583333 182.975 148.7893333 137.344 97.16666667 79.5 58.4 19.46666667 0.733333333 0.2 0 0]*0.001;
CPbuy = [118.26 118.24 117.69 108.3 107.75 104.95 104.33 104.33 105.36 107.67 108.74 117.66 112.65 108.73 111.26 117.67 119.22 119.76 119.85 129.83 131.74 131.79 133.37 136.21 136.22 136.22 132.31];
CWbuy = [4.85 4.84 4.78 4.50 4.32 4.12 4.00 4.00 4.05 4.20 4.30 4.62 4.50 4.30 4.42 4.75 4.90 4.98 5.00 5.32 5.62 5.68 5.80 5.95 5.98 5.98 5.78];

% Unit parameters
adg = [1.095024876;1.667164179;1.827164179;1.527164179];
bdg = [114.7064677;123.119403;126.29403;120.29403];
cdg = [1.94278607;0.946268657;1.276268657;1.176268657];
adge = [0.007093564;0.009439189;0.010009189;0.009439189];
bdge = [0.688516584;0.733820896;0.743420896;0.733820896];
cdge = [0.126865672;0.096268657;0.106268657;0.096268657];
EH2P = 0.57; LHV = 39.72/1000;

%% 2. Same AR(1) forecast errors as the rolling horizon
rho = 0.7;
Tp = 4;
load(fullfile('data','forecast_errors.mat')) % loads e_P, e_T

%% 3. Period-by-period settlement (no re-optimisation)
% all unit outputs fixed at day-ahead values; only the imbalance is computed

Actual_Pcg  = DA_Pcg; % DG fixed
Actual_PH2P = DA_PH2P; % FC fixed
Actual_PP2C = DA_PP2C; % PtC fixed
Actual_Pwd  = DA_Pwd; % WDU fixed
Actual_PCI  = DA_PCI; % shore power fixed
Actual_Wbuy = DA_Wbuy; % water purchase fixed

% penalty records
Actual_Pec = zeros(1, T); Actual_Pls = zeros(1, T);
Actual_Tec = zeros(1, T); Actual_Tls = zeros(1, T);
Actual_Hec = zeros(1, T); Actual_Hls = zeros(1, T);
Actual_Wec = zeros(1, T); Actual_Wls = zeros(1, T);

% realised loads
Actual_Psl_Total = zeros(1, T);
Actual_Tsl_Total = zeros(1, T);

disp('===================================================');
disp('Running deterministic baseline (no rolling horizon)');
disp('===================================================');

total_tic = tic;
for w = 1:T
    % ---- realised load = forecast x (1 + AR(1) error) ----
    RealTime_Psl = Pslt(w) * (1 + e_P(w));
    RealTime_Tsl = Tsl(w)  * (1 + e_T(w));
    RealTime_Hsl = Hsl(w); % hydrogen load deterministic
    RealTime_Wsl = Wsl(w); % water load deterministic
    
    Actual_Psl_Total(w) = RealTime_Psl + DA_PPL(w);
    Actual_Tsl_Total(w) = RealTime_Tsl;
    
    % ---- electrical balance ----
    % supply (day-ahead values)
    P_supply = sum(DA_Pcg(:,w)) + DA_PCI(w) + Ppv(w) + sum(DA_PH2P(:,w));
    % demand (realised load + day-ahead flexible loads and storage)
    P_demand = RealTime_Psl + DA_PPL(w) + DA_Pwd(w) + DA_PP2C(w) + DA_Storage_Net(1,w);
    
    P_gap = P_supply - P_demand; % positive = surplus, negative = deficit
    if P_gap >= 0
        Actual_Pec(w) = P_gap; % curtailment
        Actual_Pls(w) = 0;
    else
        Actual_Pls(w) = -P_gap; % load shedding
        Actual_Pec(w) = 0;
    end
    
    % ---- thermal balance ----
    % waste heat follows the (fixed) DG output
    Thr_dg_w = sum(DA_Pcg(:,w)) * 0.05; % WHRS = 0.05 x total DG output
    T_supply = Thr_dg_w + DA_TP2C(w);
    T_demand = RealTime_Tsl + DA_Storage_Net(2,w);
    
    T_gap = T_supply - T_demand;
    if T_gap >= 0
        Actual_Tec(w) = T_gap;
        Actual_Tls(w) = 0;
    else
        Actual_Tls(w) = -T_gap;
        Actual_Tec(w) = 0;
    end
    
    % ---- hydrogen balance (no uncertainty) ----
    H_supply = DA_Hnet(w);
    H_demand = DA_Storage_Net(3,w) + sum(DA_PH2P(:,w)) / (EH2P * LHV) * LHV + RealTime_Hsl;
    % day-ahead hydrogen use
    H_demand_simple = DA_Storage_Net(3,w) + RealTime_Hsl;
    for f = 1:2
        H_demand_simple = H_demand_simple + DA_PH2P(f,w) / (EH2P * LHV);
    end
    H_gap = H_supply - H_demand_simple;
    if H_gap >= 0
        Actual_Hec(w) = H_gap;
    else
        Actual_Hls(w) = -H_gap;
    end
    
    % ---- freshwater balance (no uncertainty) ----
    W_supply = DA_Wwd(w) + DA_Wbuy(w);
    W_demand = RealTime_Wsl + DA_Storage_Net(4,w);
    W_gap = W_supply - W_demand;
    if W_gap >= 0
        Actual_Wec(w) = W_gap;
    else
        Actual_Wls(w) = -W_gap;
    end
    
    if mod(w, 5) == 0 || w == T
        fprintf('Baseline step %d/%d | P_gap=%.3f | T_gap=%.3f\n', w, T, P_gap, T_gap);
    end
end
total_time = toc(total_tic);

disp('===================================================');
disp('Baseline finished.');
disp(['Total run time: ', num2str(total_time, '%.4f'), ' s']);
disp('===================================================');
% All unit outputs equal the day-ahead plan, so fuel, maintenance and emission costs equal the day-ahead costs
% only the penalty cost F6 changes

BL_F1 = DA_Costs(1); % fuel
BL_F2 = DA_Costs(2); % maintenance
BL_F21 = DA_Costs(3); % storage maintenance
BL_F3 = DA_Costs(4); % start-up
BL_F4 = DA_Costs(5); % emissions
BL_F5 = DA_Costs(6); % purchases

% F6: penalty cost
BL_F6 = 0;
for w = 1:T
    BL_F6 = BL_F6 + 300 * (Actual_Pec(w) + Actual_Pls(w) + ...
                            Actual_Tec(w) + Actual_Tls(w) + ...
                            Actual_Hec(w) + Actual_Hls(w) + ...
                            Actual_Wec(w) + Actual_Wls(w));
end

BL_FS = BL_F1 + BL_F2 + BL_F21 + BL_F3 + BL_F4 + BL_F5 + BL_F6;
a_BL = [BL_F1, BL_F2, BL_F21, BL_F3, BL_F4, BL_F5, BL_F6, BL_FS];

%% 5. Output
disp('===================================================');
disp('          Deterministic baseline: cost summary');
disp('===================================================');
fprintf('F1 (Fuel Cost):   DA= %10.2f  |  BL= %10.2f (=DA)\n', DA_Costs(1), a_BL(1));
fprintf('F2 (Maint Cost):  DA= %10.2f  |  BL= %10.2f (=DA)\n', DA_Costs(2), a_BL(2));
fprintf('F21(Storage):     DA= %10.2f  |  BL= %10.2f (=DA)\n', DA_Costs(3), a_BL(3));
fprintf('F3 (Startup):     DA= %10.2f  |  BL= %10.2f (=DA)\n', DA_Costs(4), a_BL(4));
fprintf('F4 (Emission):    DA= %10.2f  |  BL= %10.2f (=DA)\n', DA_Costs(5), a_BL(5));
fprintf('F5 (Purchase):    DA= %10.2f  |  BL= %10.2f (=DA)\n', DA_Costs(6), a_BL(6));
fprintf('F6 (Penalty):     DA= %10.2f  |  BL= %10.2f\n', DA_Costs(7), a_BL(7));
disp('---------------------------------------------------');
fprintf('FS (TOTAL COST):  DA= %10.2f  |  BL= %10.2f\n', DA_Costs(8), a_BL(8));
disp('===================================================');

fprintf('\nTotal electrical curtailment: %.4f MW\n', sum(Actual_Pec));
fprintf('Total electrical load shedding: %.4f MW\n', sum(Actual_Pls));
fprintf('Total thermal curtailment: %.4f MW\n', sum(Actual_Tec));
fprintf('Total thermal load shedding: %.4f MW\n', sum(Actual_Tls));
fprintf('Total penalty cost: $%.2f\n', BL_F6);
%% 6. Electrical / thermal load shedding and curtailment per period
figure('Position', [100, 100, 950, 400], 'Color', 'w');

subplot(2,1,1); hold on;
bar(1:T, Actual_Pls, 0.6, 'FaceColor', [0.95 0.45 0.45], 'EdgeColor', 'k');
bar(1:T, -Actual_Pec, 0.6, 'FaceColor', [0.55 0.75 0.55], 'EdgeColor', 'k');
ylabel('Power (MW)');
legend('Pls (Load Shedding)', 'Pec (Curtailment)', 'Orientation', 'horizontal', 'Location', 'north');
title('(a) Electrical Imbalance - Baseline (No RH)');
xlim([0.5 T+0.5]); set(gca, 'XTick', 1:T); grid on; box on;

subplot(2,1,2); hold on;
bar(1:T, Actual_Tls, 0.6, 'FaceColor', [0.95 0.60 0.60], 'EdgeColor', 'k');
bar(1:T, -Actual_Tec, 0.6, 'FaceColor', [0.60 0.80 0.60], 'EdgeColor', 'k');
xlabel('Dispatch Period'); ylabel('Power (MW)');
legend('Tls (Load Shedding)', 'Tec (Curtailment)', 'Orientation', 'horizontal', 'Location', 'north');
title('(b) Thermal Imbalance - Baseline (No RH)');
xlim([0.5 T+0.5]); set(gca, 'XTick', 1:T); grid on; box on;

set(gcf,'unit','centimeters','position',[1 1 17 10]);

%% 7. Save results
save(fullfile('results','baseline_results.mat'), 'a_BL', ...
    'Actual_Pec', 'Actual_Pls', 'Actual_Tec', 'Actual_Tls', ...
    'Actual_Hec', 'Actual_Hls', 'Actual_Wec', 'Actual_Wls', ...
    'Actual_Psl_Total', 'Actual_Tsl_Total');
