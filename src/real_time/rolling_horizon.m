%% Real-time operation of the MESM with a rolling horizon (RH)
% Loads the day-ahead plan of one case, then re-optimises the fast units (DGs within their
% committed status, FCs, PtC, WDU, shore power, ESS/TSS deviation band) period by period as
% electrical and thermal load forecast errors are revealed (AR(1) errors, data/forecast_errors.mat).
% Each window covers Tp periods; only the first period is implemented.
%   case_id : day-ahead case to load (1-4), default 4
%   Tp      : look-ahead window, default 4 (Tp = 1 gives the myopic policy, Method 2 in the paper)
%   shed_cap, whrs_on : per-case settings that reproduce the paper (defaults set below)
% Output: real-time cost settlement a_RT = [F1 F2 F21 F3 F4 F5 F6 FS], saved to
% results/rolling_case<case_id>_Tp<Tp>.mat. Plots: src/plots/plot_rolling_results.m.
%
% Author: Zhineng Fei, Aalto University. Requires YALMIP and Gurobi.

yalmip;
if ~exist('case_id','var'), case_id = 4; end   % day-ahead case to load (1-4)
if ~exist('Tp','var'),      Tp = 4;      end   % look-ahead window (Tp = 1 gives the myopic policy)
% Settings used in the paper: Cases 1-2 allow shedding up to the full load, Cases 3-4 up to 50%;
% Case 2 has no waste heat recovery in real time either.
if ~exist('shed_cap','var'), shed_cap = 0.5 + 0.5*(case_id <= 2); end   % max load shedding share
if ~exist('whrs_on','var'),  whrs_on  = (case_id ~= 2);           end   % WHRS available
load(fullfile('results', sprintf('day_ahead_case%d.mat', case_id)));
Ndg = 4; % the number of Diesel generator	
T = 27;

Pslt = [11.85215591 11.15528784 11.59678649 9.853234474 11.15590756 10.58318647 11.39864919 13.59993783 16.3493441 15.41264832 18.11754212 16.60401196 14.558626 12.46778381 11.67022563 11.8730974 9.537735061 9.769408322 10.35601844 13.75774315 15.05774315 15.95229379 16.53838229 17.12997976 18.54852914 19.82852914 18.63364333  
]*0.12;
Tsl = [1.469210175 1.463902755 1.579853361 1.615255603 1.768027544 1.789892552 1.891717933 1.935626216 2.283887416 2.100134909 2.276713185 2.158696426 2.029496918 1.861635173 1.85066003 1.829410127 1.709007485 1.648530968 1.552572224 1.591955146 1.401651477 1.393687064 1.384548591 1.33430889 1.337182364 1.193968276 1.157404035 
];
Hsl = [13.5 15 19.5 25.5 26.835 28.5 28.395 27 26.475 24 23.19 18 18.3 15 14.4 13.5 19.5 22.2 25.05 27 27.6 28.5 28.8 25.5 24.6 22.5 18 
];
Wsl = [17.856 26.224 28.8464 34.8576 35.206176 36.0896 35.367808 36.208 34.3976 35.9808 34.541568 26.8576 21.48608 20.4 16 18.416 34.416 28.5888 28 27.376 24 22.672 21.99184 21.328 21.44 21.5328 19.9232 
];
Ppv = [103.2 162.1333333 179.2 252.736 273.7973333 296.044 314.356 324.02 311.3133333 249.7393333 244.794 247.1863333 239.8803333 200.736 192.864 192.3583333 182.975 148.7893333 137.344 97.16666667 79.5 58.4 19.46666667 0.733333333 0.2 0 0 
]*0.001; 
CPbuy = [118.26 118.24 117.69 108.3 107.75 104.95 104.33 104.33 105.36 107.67 108.74 117.66 112.65 108.73 111.26 117.67 119.22 119.76 119.85 129.83 131.74 131.79 133.37 136.21 136.22 136.22 132.31 
];

% Unit capacities and efficiencies
Maxcg = [10;7.5;6.5;3]; Mincg = [3;1.5;1;0.5];
Maxfc = [1.5;1];        Minfc = [0.1;0.1];
Rampcg = [2;1.5;1;0.7]; RampH2P = [0.5;0.25];
adg = [1.095024876;1.667164179;1.827164179;1.527164179];
bdg = [114.7064677;123.119403;126.29403;120.29403];
cdg = [1.94278607;0.946268657;1.276268657;1.176268657];
EH2P = 0.57; TTH2P = 0.38; LHV = 39.72/1000;

PPL=sdpvar(1,T,'full');%propulsion load

% Variables

% DG units
Pcg=sdpvar(Ndg,27,'full');
Qcg=sdpvar(Ndg,27,'full');
cost_cg_square=sdpvar(Ndg,27,'full');
Temp_Pcg=binvar(Ndg,27,'full'); % 1 = on, 0 = off
Temp_Pcg0 = [0;0;0;0]; %initial state 
initial_on = [0;0;0;0]; % periods already on at t = 0
initial_off = [6;4;2;2]; % periods already off at t = 0

%this is the period that 0.5 hour is an interval
UTcg = [5;4;2;2];
DTcg = [5;4;2;2];

Cmaintcg = [3.2;2.4;2.0;1.5];
Cstartcg = [400;350;200;100];


% Emission cost
Ccp = [0.0312];
adge = [2.026666667;14.63;11.93;10.93];
bdge = [-85;-43.33333333;-55.43333333;-53.43333333];
cdge = [4191.5;950;850;800];

TCem = sdpvar(Ndg,27,'full');
%cold ironing
PCI=sdpvar(1,27,'full');
QCI=sdpvar(1,27,'full');

% hydrogen purchase
Hnet=sdpvar(1,27,'full');


% Fuel cells (two units)
HH2P=sdpvar(2,27,'full');
PH2P=sdpvar(2,27,'full');
TH2P=sdpvar(2,27,'full');
Temp_H2P=binvar(2,27,'full'); % 1 = on, 0 = off

 
% curtailment
Pec=sdpvar(1,27,'full');
Tec=sdpvar(1,27,'full');
Wec= sdpvar(1,27,'full');
Hec=sdpvar(1,27,'full');
Temp_P=binvar(1,27,'full'); % 1 = curtailment, 0 = load shedding
Temp_T=binvar(1,27,'full'); % 1 = curtailment, 0 = load shedding
Temp_W=binvar(1,27,'full'); % 1 = curtailment, 0 = load shedding
Temp_H=binvar(1,27,'full'); % 1 = curtailment, 0 = load shedding

% load shedding
Pls=sdpvar(1,27,'full');
Tls=sdpvar(1,27,'full');
Wls= sdpvar(1,27,'full');
Hls= sdpvar(1,27,'full');


% Power-to-heat (PtC) variables
PP2C=sdpvar(1,27,'full');
TP2C=sdpvar(1,27,'full');

% water desalination unit
Pwd=sdpvar(1,27,'full');
Wwd=sdpvar(1,27,'full');

% battery
PEnet=sdpvar(1,27,'full');

% hydrogen tank
HEnet=sdpvar(1,27,'full');

% thermal storage
TEnet=sdpvar(1,27,'full');

% water tank
WEnet=sdpvar(1,27,'full');

%------------------------- Parameters ----------------------%

%Onboard service load

% ==============================================================
% AR(1) forecast errors (rho = 0.7)
% e(t) = ρ*e(t-1) + σ*sqrt(1-ρ²)*ξ(t), ξ~N(0,1)
% Error matrix: EPsl_RT(w, k) = error at position k of the window solved at step w
%   k = 1: realised (observed) error of the current period
%   k > 1: AR(1) conditional mean rho^(k-1)*e(w)
% The look-ahead thus uses the error autocorrelation; the myopic policy (Tp = 1) only uses k = 1
% ==============================================================
rho = 0.7; % AR(1) coefficient
% sigma_P = 0.05;     % std of electrical load error
% sigma_T = 0.05;     % std of thermal load error
% rng(2024);          % fixed seed
% 
% % realised error path
% e_P = zeros(1, T); e_T = zeros(1, T);
% e_P(1) = sigma_P * randn;
% e_T(1) = sigma_T * randn;
% for t = 2:T
%     e_P(t) = rho * e_P(t-1) + sigma_P * sqrt(1-rho^2) * randn;
%     e_T(t) = rho * e_T(t-1) + sigma_T * sqrt(1-rho^2) * randn;
% end
% 
% % sustained load increase in periods 17-24
% e_P(17:24) = e_P(17:24) + 0.10;
% e_T(17:24) = e_T(17:24) + 0.10;
load(fullfile('data','forecast_errors.mat'))
% Build the error matrix: rows = rolling steps, columns = position in the window
EPsl_RT = zeros(T, Tp);
ETsl_RT = zeros(T, Tp);
for w_gen = 1:T
    for k_gen = 1:Tp
        if k_gen == 1
            EPsl_RT(w_gen, k_gen) = e_P(w_gen); % realised error
            ETsl_RT(w_gen, k_gen) = e_T(w_gen);
        else
            EPsl_RT(w_gen, k_gen) = rho^(k_gen-1) * e_P(w_gen); % conditional mean forecast
            ETsl_RT(w_gen, k_gen) = rho^(k_gen-1) * e_T(w_gen);
        end
    end
end

% ==============================================================

% Efficiency setting
ETP2C = [3.3];
MaxP2C  = [0.5];
%initial capacity of storage devices
Einitial = [4;0.6];

CHbuy= [3.3];%$/kg repmat(3.3,[4 24])
EP2H=[0.7]; % P2H electrical efficiency
TTP2H=[0.15]; % P2H thermal efficiency

% water price (same as day-ahead)
CWbuy = [4.85 4.84 4.78 4.50 4.32 4.12 4.00 4.00 4.05 4.20 4.30 4.62 4.50 4.30 4.42 4.75 4.90 4.98 5.00 5.32 5.62 5.68 5.80 5.95 5.98 5.98 5.78];


Cgas= [0.48]; % natural gas price ($)
Echpe=[0.35]; % CHP electrical efficiency
Echph=[0.45]; % CHP thermal efficiency
Eb= [0.8]; % boiler efficiency
LHVG=[9.7]/1000; % lower heating value of gas (MWh/kg)
%-------------------------- MESM energy management + voyage scheduling ---------------------------
% Arrays for the real-time records
VPsl =[]; VTsl =[]; VHsl =[]; VWsl =[]; VPv =[];
VPcg =[]; Vcost_cg_square=[]; VHnet =[];
VPH2P =[]; VPP2H =[]; VPP2C =[]; VWwd =[];
VPCI =[]; VPec =[]; VTec =[]; VPls =[]; VTls =[];
VTH2P = []; VCS = []; Vvoltage = [];

%% 3. Initialise real-time records
Actual_Pcg  = zeros(Ndg, T);
Actual_PH2P = zeros(2, T);
Actual_Pwd  = zeros(1, T);
Actual_PP2C = zeros(1, T);
Actual_HH2P = zeros(2, T);

% corrective actions (penalised)
Actual_Pec = zeros(1, T); Actual_Pls = zeros(1, T);
Actual_Tec = zeros(1, T); Actual_Tls = zeros(1, T);
Actual_Hec = zeros(1, T); Actual_Hls = zeros(1, T);
Actual_Wec = zeros(1, T); Actual_Wls = zeros(1, T);

% water purchase (from day-ahead)
Actual_Wbuy = zeros(1, T);

% shore power (re-optimised)
Actual_PCI = zeros(1, T);

% squared DG output for the fuel cost
Actual_cost_cg_square = zeros(Ndg, T);

% solve time and status per step
RH_solve_time = zeros(1, T); % solve time per step (s)
RH_feasibility = zeros(1, T);   % 0=feasible, 1=infeasible/other
RH_solver_info = cell(1, T); % solver info

% ==============================================================
% Real-time deviation band for ESS and TSS (electrical and thermal uncertainty)
% SOC may deviate from the day-ahead trajectory within the band; terminal SOC returns to the plan
% ==============================================================
Band_E = 0.03 * (18 - 4); % ESS band (usable capacity 14 MWh)
Band_T = 0.03 * 3; % TSS band (capacity 3 MWh)
Actual_dPEnet = zeros(1, T); % implemented ESS deviation
Actual_dTEnet = zeros(1, T); % implemented TSS deviation
Cum_dP = 0; % cumulative ESS SOC deviation
Cum_dT = 0; % cumulative TSS SOC deviation

%% 4. Rolling horizon main loop
total_tic = tic;
for w = 1:T
    % A. Window length (shorter near the end of the voyage)
    Len = min(Tp, T - w + 1); 
    window_range = w : (w + Len - 1);
    % B. Variables of the window
    Pcg_rt   = sdpvar(Ndg, Len, 'full');
    PH2P_rt  = sdpvar(2, Len, 'full');
    HH2P_rt  = sdpvar(2, Len, 'full');
    TH2P_rt  = sdpvar(2, Len, 'full');
    Pwd_rt   = sdpvar(1, Len, 'full');
    Wwd_rt   = sdpvar(1, Len, 'full');
    PCI_rt   = sdpvar(1, Len, 'full'); % shore power (adjustable in real time)
    PP2C_rt  = sdpvar(1, Len, 'full');
    
    % storage deviation from the day-ahead plan
    dPEnet_rt = sdpvar(1, Len, 'full'); % ESS deviation
    dTEnet_rt = sdpvar(1, Len, 'full'); % TSS deviation
    abs_dP_rt = sdpvar(1, Len, 'full'); % |dPEnet| auxiliary
    abs_dT_rt = sdpvar(1, Len, 'full'); % |dTEnet| auxiliary
    TP2C_rt  = sdpvar(1, Len, 'full');
    Thr_dg_rt= sdpvar(1, Len, 'full');

    % slack variables for the four carriers
    Pec_rt = sdpvar(1, Len, 'full'); Pls_rt = sdpvar(1, Len, 'full');
    Tec_rt = sdpvar(1, Len, 'full'); Tls_rt = sdpvar(1, Len, 'full');
    Hec_rt = sdpvar(1, Len, 'full'); Hls_rt = sdpvar(1, Len, 'full');
    Wec_rt = sdpvar(1, Len, 'full'); Wls_rt = sdpvar(1, Len, 'full');
    
    Constraints_RT = [];
    F_RT = 0;
    for k = 1:Len
        tau = window_range(k); % absolute period index
        w_idx = min(w, size(EPsl_RT, 1));
        RealTime_Psl = Pslt(tau) * (1 + EPsl_RT(w_idx, k));
        RealTime_Tsl = Tsl(tau)  * (1 + ETsl_RT(w_idx, k));
        RealTime_Hsl = Hsl(tau); 
        RealTime_Wsl = Wsl(tau);

        for i = 1:Ndg
            Constraints_RT = [Constraints_RT, Mincg(i)*DA_DG_status(i,tau) <= Pcg_rt(i,k) <= Maxcg(i)*DA_DG_status(i,tau)];
			cost_cg_square_val = Pcg_rt(i,k)^2;
            
            F_RT = F_RT + cost_cg_square_val*adg(i) + Pcg_rt(i,k)*bdg(i) + DA_DG_status(i,tau)*cdg(i); 
            TCem_rt = cost_cg_square_val*adge(i) + Pcg_rt(i,k)*bdge(i) + DA_DG_status(i,tau)*cdge(i);
            F_RT = F_RT + TCem_rt * 0.0312 * 2;
            F_RT = F_RT + 0.01 * (Pcg_rt(i,k) - DA_Pcg(i,tau))^2;
        end
        for i = 1:2
            Constraints_RT = [Constraints_RT, Minfc(i)*DA_FC_status(i,tau) <= PH2P_rt(i,k) <= Maxfc(i)*DA_FC_status(i,tau)];
            Constraints_RT = [Constraints_RT, PH2P_rt(i,k) == HH2P_rt(i,k) * EH2P * LHV];
            Constraints_RT = [Constraints_RT, TH2P_rt(i,k) == 0];
        end
        % ramping (linked to the previous step)
        if k > 1
            for i = 1:Ndg
                if DA_DG_status(i,tau) == DA_DG_status(i,tau-1) % ramp limit only if the on/off status is unchanged
                    Constraints_RT = [Constraints_RT, -Rampcg(i) <= Pcg_rt(i,k) - Pcg_rt(i,k-1) <= Rampcg(i)];
                end
            end
        elseif w > 1
            for i = 1:Ndg
                if DA_DG_status(i,tau) == DA_DG_status(i,tau-1)
                    Constraints_RT = [Constraints_RT, -Rampcg(i) <= Pcg_rt(i,1) - Actual_Pcg(i,w-1) <= Rampcg(i)];
                end
            end
        end
        % ----------------------------------------------------
        % Constraints 2: flexible loads and waste heat
        % ----------------------------------------------------
        
        % limits
        % at berth: WDU off, shore power available; at sea: WDU on, no shore power
        if tau >= 12 && tau <= 16
            Constraints_RT = [Constraints_RT, Wwd_rt(k) == 0, Pwd_rt(k) == 0];
            Constraints_RT = [Constraints_RT, 0 <= PCI_rt(k) <= 100]; % shore power at berth
        else
            Constraints_RT = [Constraints_RT, Pwd_rt(k) == Wwd_rt(k)*4/1000, 0 <= Wwd_rt(k) <= 150];
            Constraints_RT = [Constraints_RT, PCI_rt(k) == 0]; % no shore power at sea
        end
        Constraints_RT = [Constraints_RT, TP2C_rt(k) == PP2C_rt(k)*3.3,  0 <= PP2C_rt(k) <= 0.6];
        Constraints_RT = [Constraints_RT, Thr_dg_rt(k) <= whrs_on * sum(Pcg_rt(:,k)) * 0.05];
        
        Constraints_RT = [Constraints_RT, 0 <= Pec_rt(k) ,  0 <= Pls_rt(k) <= shed_cap * RealTime_Psl];
        Constraints_RT = [Constraints_RT, 0 <= Tec_rt(k) ,  0 <= Tls_rt(k) <= shed_cap * RealTime_Tsl];
        Constraints_RT = [Constraints_RT, 0 <= Hec_rt(k) , 0 <= Hls_rt(k) <=  RealTime_Hsl];
        Constraints_RT = [Constraints_RT, 0 <= Wec_rt(k) , 0 <= Wls_rt(k) <=  RealTime_Wsl];

        % ----------------------------------------------------
        % Constraints 3: multi-energy balances
        % ----------------------------------------------------
        Fixed_PEnet = DA_Storage_Net(1, tau);
        Fixed_TEnet = DA_Storage_Net(2, tau);
        Fixed_HEnet = DA_Storage_Net(3, tau);
        Fixed_WEnet = DA_Storage_Net(4, tau);
        Fixed_Hnet  = DA_Hnet(tau);
        Fixed_Wbuy  = DA_Wbuy(tau); % water purchase (fixed day-ahead)

        % --- storage deviation (ESS and TSS only) ---
        % linearised absolute value
        Constraints_RT = [Constraints_RT, abs_dP_rt(k) >= dPEnet_rt(k), abs_dP_rt(k) >= -dPEnet_rt(k)];
        Constraints_RT = [Constraints_RT, abs_dT_rt(k) >= dTEnet_rt(k), abs_dT_rt(k) >= -dTEnet_rt(k)];
        % plan + deviation must stay within power limits
        Constraints_RT = [Constraints_RT, -5 <= Fixed_PEnet + dPEnet_rt(k) <= 5];
        Constraints_RT = [Constraints_RT, -2 <= Fixed_TEnet + dTEnet_rt(k) <= 2];
        % SOC band: implemented + in-window deviation within +/- Band
        Constraints_RT = [Constraints_RT, -Band_E <= Cum_dP + sum(dPEnet_rt(1:k)) <= Band_E];
        Constraints_RT = [Constraints_RT, -Band_T <= Cum_dT + sum(dTEnet_rt(1:k)) <= Band_T];
        % terminal SOC returns to the day-ahead trajectory
        if tau == T
            Constraints_RT = [Constraints_RT, Cum_dP + sum(dPEnet_rt(1:k)) == 0];
            Constraints_RT = [Constraints_RT, Cum_dT + sum(dTEnet_rt(1:k)) == 0];
        end

        Constraints_RT = [Constraints_RT, sum(Pcg_rt(:,k)) + PCI_rt(k) + Ppv(tau) + sum(PH2P_rt(:,k)) - Pec_rt(k) == RealTime_Psl + DA_PPL(tau) + Pwd_rt(k) + PP2C_rt(k) - Pls_rt(k) + Fixed_PEnet + dPEnet_rt(k)];
        Constraints_RT = [Constraints_RT, Thr_dg_rt(k) + TP2C_rt(k) - Tec_rt(k) == RealTime_Tsl - Tls_rt(k) + Fixed_TEnet + dTEnet_rt(k)]; 
        Constraints_RT = [Constraints_RT, Fixed_Hnet - Hec_rt(k) == Fixed_HEnet + sum(HH2P_rt(:,k)) + RealTime_Hsl - Hls_rt(k)];
        Constraints_RT = [Constraints_RT, Wwd_rt(k) + Fixed_Wbuy - Wec_rt(k) == RealTime_Wsl + Fixed_WEnet - Wls_rt(k)];
		
        % flexible-load maintenance + shore power cost
        F_RT = F_RT + 4*PP2C_rt(k) + 0.4*Wwd_rt(k) + CPbuy(tau)*PCI_rt(k);
        % linear penalty on storage deviation (extra cycling)
        F_RT = F_RT + 0.5*(abs_dP_rt(k) + abs_dT_rt(k));
        % penalty on all slacks
        F_RT = F_RT + 300 * (Pec_rt(k) + Pls_rt(k) + Tec_rt(k) + Tls_rt(k) + Hec_rt(k) + Hls_rt(k) + Wec_rt(k) + Wls_rt(k));
    end
    ops = sdpsettings('solver','Gurobi', 'verbose', 0);
    step_tic = tic;
    sol = optimize(Constraints_RT, F_RT, ops);
    RH_solve_time(w) = toc(step_tic);
    
    % solver status: 0 = feasible
    RH_feasibility(w) = sol.problem;
    RH_solver_info{w} = sol.info;
    
    if sol.problem ~= 0
        warning('RH step %d INFEASIBLE (code=%d): %s', w, sol.problem, sol.info);
    end
    
    % E. Implement the first period of the window
    Actual_Pcg(:, w)  = value(Pcg_rt(:, 1));
    Actual_Pwd(w)     = value(Pwd_rt(1));
    Actual_PP2C(w)    = value(PP2C_rt(1));
    Actual_PH2P(:, w) = value(PH2P_rt(:, 1));
    Actual_PCI(w)     = value(PCI_rt(1)); % shore power
    
    % implemented storage deviation
    Actual_dPEnet(w) = value(dPEnet_rt(1));
    Actual_dTEnet(w) = value(dTEnet_rt(1));
    Cum_dP = Cum_dP + Actual_dPEnet(w);
    Cum_dT = Cum_dT + Actual_dTEnet(w);
    
    Actual_Pec(w) = value(Pec_rt(1)); Actual_Pls(w) = value(Pls_rt(1));
    Actual_Tec(w) = value(Tec_rt(1)); Actual_Tls(w) = value(Tls_rt(1));
    Actual_Hec(w) = value(Hec_rt(1)); Actual_Hls(w) = value(Hls_rt(1));
    Actual_Wec(w) = value(Wec_rt(1)); Actual_Wls(w) = value(Wls_rt(1));
    Actual_Wbuy(w) = DA_Wbuy(w); % water purchase from day-ahead

    % squared DG output for cost settlement
    Actual_cost_cg_square(:, w) = value(Pcg_rt(:, 1)).^2;
    if mod(w, 5) == 0 || w == T
        disp(['Rolling horizon step ', num2str(w), '/', num2str(T), ...
              ' | solve time: ', num2str(RH_solve_time(w), '%.3f'), 's', ...
              ' | status: ', num2str(RH_feasibility(w))]);
    end
end
total_time = toc(total_tic);

disp('===================================================');
disp('Rolling horizon finished.');
disp(['Total run time: ', num2str(total_time, '%.2f'), ' s']);
disp(['Mean solve time per step: ', num2str(mean(RH_solve_time), '%.3f'), ' s']);
disp(['Max solve time per step: ', num2str(max(RH_solve_time), '%.3f'), ' s (step ', num2str(find(RH_solve_time==max(RH_solve_time),1)), ')']);

n_infeasible = sum(RH_feasibility ~= 0);
if n_infeasible == 0
    disp('Status: all 27 steps feasible');
else
    disp(['Status: ', num2str(n_infeasible), '/', num2str(T), ' steps infeasible']);
    disp(['  infeasible steps: ', num2str(find(RH_feasibility ~= 0))]);
end

disp(['Total electrical load shedding (MW): ', num2str(sum(Actual_Pls))]);
disp(['Total water shedding (t): ', num2str(sum(Actual_Wls))]);
disp(['ESS deviation: max|dP| = ', num2str(max(abs(Actual_dPEnet)), '%.3f'), ' MW, terminal SOC offset = ', num2str(sum(Actual_dPEnet), '%.3f'), ' MWh']);
disp(['TSS deviation: max|dT| = ', num2str(max(abs(Actual_dTEnet)), '%.3f'), ' MW, terminal SOC offset = ', num2str(sum(Actual_dTEnet), '%.3f'), ' MWh']);
disp('===================================================');

%% =====================================================================
% 6. Real-time cost settlement
% =====================================================================
RT_F1 = 0; RT_F2 = 0; RT_F4 = 0; RT_F5 = 0; RT_F6 = 0;

for w = 1:T
    % F1: fuel cost (DGs)
    for i = 1:Ndg
        RT_F1 = RT_F1 + Actual_cost_cg_square(i,w)*adg(i) + Actual_Pcg(i,w)*bdg(i) + DA_DG_status(i,w)*cdg(i);
        
        % F4: emission cost
        TCem_rt_val = Actual_cost_cg_square(i,w)*adge(i) + Actual_Pcg(i,w)*bdge(i) + DA_DG_status(i,w)*cdge(i);
        RT_F4 = RT_F4 + TCem_rt_val * 0.0312 * 2;
    end
    
    % F2: maintenance cost
    RT_F2 = RT_F2 + 3*(Actual_Pcg(1,w)*3.2 + Actual_Pcg(2,w)*2.4 + Actual_Pcg(3,w)*2.0 + Actual_Pcg(4,w)*1.5);
    RT_F2 = RT_F2 + (Actual_PH2P(1,w)*4 + Actual_PH2P(2,w)*3);
    RT_F2 = RT_F2 + (Actual_PP2C(w)*4 + Actual_Pwd(w)*0.4);
    
    % F5: shore power (real-time) + hydrogen and water (day-ahead)
    RT_F5 = RT_F5 + CPbuy(w)*Actual_PCI(w) + 4*DA_Hnet(w) + CWbuy(w)*Actual_Wbuy(w);
    
    % F6: penalty cost of corrective actions
    RT_F6 = RT_F6 + 300 * (Actual_Pec(w) + Actual_Pls(w) + Actual_Tec(w) + Actual_Tls(w) + Actual_Hec(w) + Actual_Hls(w) + Actual_Wec(w) + Actual_Wls(w));
end

% costs fixed at the day-ahead stage
RT_F21 = DA_Costs(3); % storage maintenance (F21)
RT_F3  = DA_Costs(4); % DG start-up (F3)

% total cost
RT_FS = RT_F1 + RT_F2 + RT_F21 + RT_F3 + RT_F4 + RT_F5 + RT_F6;

% cost vector
a_RT = [RT_F1, RT_F2, RT_F21, RT_F3, RT_F4, RT_F5, RT_F6, RT_FS];

disp('===================================================');
disp('          Day-ahead plan vs real-time settlement');
disp('===================================================');
fprintf('F1 (Fuel Cost):   DA= %10.2f  |  RT= %10.2f\n', DA_Costs(1), a_RT(1));
fprintf('F2 (Maint Cost):  DA= %10.2f  |  RT= %10.2f\n', DA_Costs(2), a_RT(2));
fprintf('F21(Storage):     DA= %10.2f  |  RT= %10.2f (Fixed)\n', DA_Costs(3), a_RT(3));
fprintf('F3 (Startup):     DA= %10.2f  |  RT= %10.2f (Fixed)\n', DA_Costs(4), a_RT(4));
fprintf('F4 (Emission):    DA= %10.2f  |  RT= %10.2f\n', DA_Costs(5), a_RT(5));
fprintf('F5 (Grid/PCI):    DA= %10.2f  |  RT= %10.2f \n', DA_Costs(6), a_RT(6));
fprintf('F6 (Penalty):     DA= %10.2f  |  RT= %10.2f\n', DA_Costs(7), a_RT(7));
disp('---------------------------------------------------');
fprintf('FS (TOTAL COST):  DA= %10.2f  |  RT= %10.2f\n', DA_Costs(8), a_RT(8));
disp('===================================================');

% Save the real-time results for plotting and comparison
yalmip_classes = {'sdpvar','ndsdpvar','lmi','constraint','blkvar'};
ws_info = whos;
vars_to_save = {ws_info(~ismember({ws_info.class}, yalmip_classes)).name};
save(fullfile('results', sprintf('rolling_case%d_Tp%d.mat', case_id, Tp)), vars_to_save{:});
