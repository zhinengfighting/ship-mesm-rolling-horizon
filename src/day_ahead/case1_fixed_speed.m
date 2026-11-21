%% Case 1: fixed voyage speed - day-ahead scheduling of the multi-energy ship microgrid (MESM)
% The ship sails at the nominal speed; WHRS and the EEOI constraint are kept.
% Load shedding and curtailment are allowed in the day-ahead model at a penalty.
%
% Day-ahead MILP over 27 half-hour periods (sailing - berthing - sailing):
% DG unit commitment with piecewise-linear fuel cost, fuel cells, PtC, desalination (WDU),
% battery / thermal / hydrogen / water storage, shore power and hydrogen/water purchase at berth,
% and voyage speed with weather-induced added resistance (data/added_resistance.xlsx).
% Output: results/day_ahead_caseN.mat (commitment, speed, propulsion load and storage plan),
% which is passed to src/real_time/rolling_horizon.m.
%
% Author: Zhineng Fei, Aalto University. Requires YALMIP and Gurobi.

clear all
clc;
clear;
yalmip;


Ndg = 4; % the number of Diesel generator	
T = 27;
% ------------------------- Decision variables -------------------------%
% Onboard loads
Psl=sdpvar(2,T,'full');
Tsl=sdpvar(1,T,'full');
Hsl=sdpvar(1,T,'full');
Wsl=sdpvar(1,T,'full');

% PV
Ppv=sdpvar(1,T,'full');
Tpv=sdpvar(1,T,'full');

% electricity price
CPbuy = sdpvar(1,T,'full');

%First-stage 

% Voyage scheduling
PPL=sdpvar(1,T,'full');%propulsion load
Nspeed = sdpvar(1,T,'full'); % nominal speed (knots)
Aspeed = sdpvar(1,T,'full'); % actual speed (knots)
s_1 = 0.00235;
s_2 = 3;

V_n = [];
Nspeed = [12.7 17 19 21 21 21 21 21 19 17 14.7 0 0 0 0 0 14.7 19 21 21 21 21 21 21 19 17 14.7]; 
Index = find(Nspeed==0);
B_1=Index(1,1)-1;
R_speed = 20;

point_1 = [];
point_1 = [0 (min(Nspeed(1,1:T)):(max(Nspeed(1,1:T))/60-min(Nspeed(1,1:T))/60):max(Nspeed(1,1:T)))];
for i = 2:length(point_1)
    V_n(1,i) = s_1*point_1(1,i)^s_2;
end
V_n(1,1)=0;
z_v=binvar(length(point_1)-1,T);
w_v=sdpvar(length(point_1),T);


%START/DOWN OF DGs
Temp_Pcg=binvar(Ndg,27,'full'); % 1 = on, 0 = off
Temp_Pcg0 = [0;0;0;0]; %initial state 
initial_on = [0;0;0;0]; % periods already on at t = 0
UTcg = [5;4;2;2];
DTcg = [5;4;2;2];

%START/DOWN OF FCs
Temp_H2P=binvar(2,T,'full'); % 1 = on, 0 = off

% Storage mode binaries (charge / discharge / idle)
Temp_Pch=binvar(1,T,'full'); Temp_Pdch=binvar(1,T,'full'); Temp_Pstatic=binvar(1,T,'full'); 
Temp_Hch=binvar(1,T,'full'); Temp_Hdch=binvar(1,T,'full'); Temp_Hstatic=binvar(1,T,'full'); 
Temp_Tch=binvar(1,T,'full'); Temp_Tdch=binvar(1,T,'full'); Temp_Tstatic=binvar(1,T,'full'); 
Temp_Wch=binvar(1,T,'full'); Temp_Wdch=binvar(1,T,'full'); Temp_Wstatic=binvar(1,T,'full'); 

% Storage power variables
Pch=sdpvar(1,T,'full'); Pdch=sdpvar(1,T,'full'); PEnet=sdpvar(1,T,'full');
Hch=sdpvar(1,T,'full'); Hdch=sdpvar(1,T,'full'); HEnet=sdpvar(1,T,'full');
Tch=sdpvar(1,T,'full'); Tdch=sdpvar(1,T,'full'); TEnet=sdpvar(1,T,'full');
Wch=sdpvar(1,T,'full'); Wdch=sdpvar(1,T,'full'); WEnet=sdpvar(1,T,'full');

% Diesel generators (DGs) and piecewise linearisation
% DG units
Pcg=sdpvar(Ndg,T,'full');
cost_cg_square=sdpvar(Ndg,T,'full');

Maxcg = [10;7.5;6.5;3];
Mincg = [3;1.5;1;0.5];

% Piecewise linearisation of the quadratic DG fuel cost
point_cg1 = [];
CG_1 = [];
t = [];
for i =1:Ndg
    point_cg1(i,:) = [0 (Mincg(i,1):(Maxcg(i,1)/20-Mincg(i,1)/20):Maxcg(i,1))];
    CG_1(i,:) = [0 (Mincg(i,1):(Maxcg(i,1)/20-Mincg(i,1)/20):Maxcg(i,1)).^2]; % quadratic term
    t(i,1) = length(point_cg1(i,:));
end
z_cg1=binvar(t(1,1)-1,T,Ndg);
w_cg1=sdpvar(t(1,1),T,Ndg);


Rampcg = [2;1.5;1;0.7];
Cmaintcg = [3.2;2.4;2.0;1.5];
Cstartcg = [400;350;200;100];
adg = [1.095024876;1.667164179;1.827164179;1.527164179];
bdg = [114.7064677;123.119403;126.29403;120.29403];
cdg = [1.94278607;0.946268657;1.276268657;1.176268657];

% Emission cost
Ccp = [0.0312];
adge = [2.026666667;14.63;11.93;10.93];
bdge = [-85;-43.33333333;-55.43333333;-53.43333333];
cdge = [4191.5;950;850;800];
TCem = sdpvar(Ndg,T,'full');

% Variables for the EEOI constraint
Total_CO2_Emission = sdpvar(1,1,'full'); % total CO2 emission M_CO2
Total_Work = sdpvar(1,1,'full'); % total transport work W_work

% Exchange with the port and conversion units
PCI=sdpvar(1,T,'full');
Hnet=sdpvar(1,T,'full');

% Fuel cells (two units)
HH2P=sdpvar(2,T,'full');
PH2P=sdpvar(2,T,'full');
TH2P=sdpvar(2,27,'full');
Maxfc = [1.5;1];
Minfc = [0.1;0.1];
RampH2P = [0.5;0.25];

% Power-to-heat (PtC) variables
PP2C=sdpvar(1,T,'full');
TP2C=sdpvar(1,T,'full');

% water desalination unit
Pwd=sdpvar(1,T,'full');
Wwd=sdpvar(1,T,'full');
% water purchasing from port (only during berthing)
Wbuy=sdpvar(1,T,'full');
CWbuy = [4.85 4.84 4.78 4.50 4.32 4.12 4.00 4.00 4.05 4.20 4.30 4.62 4.50 4.30 4.42 4.75 4.90 4.98 5.00 5.32 5.62 5.68 5.80 5.95 5.98 5.98 5.78];
MaxWbuy = 100;  % m^3 per period max
MinWbuy = 0;    % m^3 per period min


% DG waste heat recovery
Thr_dg = sdpvar(1,T,'full');
% Load shedding and curtailment slacks ---
Pls = sdpvar(1,T,'full'); % electrical load shedding
Pec = sdpvar(1,T,'full'); % electrical curtailment
Tls = sdpvar(1,T,'full'); % thermal load shedding
Tec = sdpvar(1,T,'full'); % thermal curtailment

%------------------------- Parameters ----------------------%

%Onboard service load
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

Tpv = [72.37587614 110.8742894 155.7184751 172.4747951 202.3715648 259.9120275 259.498254 245.7018838 209.9209436 168.0665052 210.4767666 166.0933807 161.7679597 155.110273 135.8089887 166.2914019 144.2219194 101.4730416 96.93390817 65.48514965 58.35734942 52.41030546 13.52178889 0.497648397 0.14582637 0 0 
]*0.001; 

CPbuy = [118.26 118.24 117.69 108.3 107.75 104.95 104.33 104.33 105.36 107.67 108.74 117.66 112.65 108.73 111.26 117.67 119.22 119.76 119.85 129.83 131.74 131.79 133.37 136.21 136.22 136.22 132.31 
];
X_1 = sdpvar(10,T,'full');
X_1 = xlsread(fullfile('data','added_resistance.xlsx'),'A1:AA10');
%Ar = X_1(1,:).*ones(1,T);
Ar = X_1(4,:).*ones(1,T);
%Ar = X_1(7,:).*ones(1,T);

% Efficiency setting
ETP2C = [3.3];
MaxP2C  = [0.5];
%initial capacity of storage devices
Einitial = [4;0.6];
CHbuy= [3.3];%$/kg repmat(3.3,[4 24])
EP2H=[0.7]; % P2H electrical efficiency
TTP2H=[0.15]; % P2H thermal efficiency
EH2P=[0.57]; % H2P (fuel cell) electrical efficiency
TTH2P=[0.38]; % H2P (fuel cell) thermal efficiency

Cgas= [0.48]; % natural gas price ($)
Echpe=[0.35]; % CHP electrical efficiency
Echph=[0.45]; % CHP thermal efficiency
Eb= [0.8]; % boiler efficiency
LHVG=[9.7]/1000; % lower heating value of gas (MWh/kg)
LHV=[39.72]/1000; %MWh/kg

% EEOI parameters
Ship_GT = 40000; % gross tonnage (assumed)
EEOI_Limit = 14; % EEOI limit (gCO2/t/nm)
Delta_t = 0.5; % time step: each period is 0.5 h

%-------------------------- MESM energy management + voyage scheduling ---------------------------
FS =0;
F1 = 0; % fuel cost
F2 = 0; % maintenance cost
F21 = 0; % storage maintenance cost (first stage)
F3 = sdpvar(Ndg,27,'full');; % start-up cost
F4 = 0; % emission cost
F5 = 0; % purchase cost at berth (cold ironing, hydrogen, water)
F6 = 0; % load shedding and curtailment cost

Constraints = [];
% These constraints have to be adjusted if the time slot is changed
tic
%Second STAGE CONSTRAINTS

for k = 1:11 
    Constraints = [Constraints, PCI(1,k)==0, Hnet(1,k)==0, Wbuy(1,k)==0];
end

for k = 12:16
    Constraints = [Constraints, 0<=PCI(1,k)<=100, 0<=Hnet(1,k)<=150];    
    for i =1:Ndg
        Constraints = [Constraints,Pcg(i,k)==0];
    end
    Constraints = [Constraints, PH2P(1,k)==0, PH2P(2,k)==0];
    % WDU shut down during berthing (port water quality)
    Constraints = [Constraints, Wwd(1,k)==0, Pwd(1,k)==0];
    % Allow freshwater purchasing from port
    Constraints = [Constraints, MinWbuy<=Wbuy(1,k)<=MaxWbuy];
end

for k = 17:27
    Constraints = [Constraints, PCI(1,k)==0, Hnet(1,k)==0, Wbuy(1,k)==0];
end

% Ramping limits of DGs and fuel cells
for k = 2:27
for i = 1:Ndg
Constraints = [Constraints, implies(Temp_Pcg(i,k)-Temp_Pcg(i,k-1)==0,[-Rampcg(i,1)<=Pcg(i,k)-Pcg(i,k-1)<=Rampcg(i,1)])];
end

for i = 1:2
Constraints = [Constraints, implies(Temp_H2P(i,k)-Temp_H2P(i,k-1)==0,[-RampH2P(i,1)<=PH2P(i,k)-PH2P(i,k-1)<=RampH2P(i,1)])];
end
end

for k = 1:T

% DG operating limits
for i = 1:Ndg 
Constraints = [Constraints, implies(Temp_Pcg(i,k),[Mincg(i,1)<=Pcg(i,k)<=Maxcg(i,1)])];
Constraints = [Constraints, implies(1-Temp_Pcg(i,k),[Pcg(i,k)==0])];
end

% Fuel cell constraints
for i=1:2
Constraints = [Constraints,PH2P(i,k)== HH2P(i,k)*EH2P*LHV];
Constraints = [Constraints, TH2P(i,k)== 0];
Constraints = [Constraints, implies(Temp_H2P(i,k),[Minfc(i,1)<=PH2P(i,k)<=Maxfc(i,1)])];
Constraints = [Constraints, implies(1-Temp_H2P(i,k),[PH2P(i,k)==0])];
end

% Desalination (WDU) and PtC constraints
Constraints = [Constraints, Pwd(1,k) == Wwd(1,k)*4/1000, 0<=Wwd(1,k)<=150];
Constraints = [Constraints, TP2C(1,k) == PP2C(1,k)*3.3, 0<=PP2C(1,k)<=0.6];

% DG waste heat recovery (WHRS)
Constraints = [Constraints, Thr_dg(1,k) <= (Pcg(1,k)+Pcg(2,k)+Pcg(3,k)+Pcg(4,k)) * 0.05];

% Electrical power balance
Constraints = [Constraints, Pslt(1,k)+PPL(1,k) + Pwd(1,k) + PP2C(1,k)+ PEnet(1,k)- Pls(1,k) + Pec(1,k)== Pcg(1,k)+Pcg(2,k)+Pcg(3,k)+Pcg(4,k) + PCI(1,k) + Ppv(1,k) + PH2P(1,k)+PH2P(2,k)];

% Thermal power balance
Constraints = [Constraints,Thr_dg(1,k) + TP2C(1,k) + Tls(1,k) - Tec(1,k)== Tsl(1,k)+TEnet(1,k)]; 

Constraints = [Constraints, 0<= Pls(1,k) <= Pslt(1,k), Pec(1,k) >= 0, 0<= Tls(1,k) <= Tsl(1,k), Tec(1,k) >= 0];

% Hydrogen balance
Constraints = [Constraints, Hnet(1,k)==HEnet(1,k)+HH2P(1,k)+HH2P(2,k)+Hsl(1,k)];

% Freshwater balance
Constraints = [Constraints, Wwd(1,k)+Wbuy(1,k)==Wsl(1,k)+WEnet(1,k)];	
end



%FIRST STAGE CONSTRAINTS
% Minimum up time
for i = 1:Ndg

k=1;
Constraints = [Constraints, UTcg(i,1)*(Temp_Pcg(i,k)-Temp_Pcg0(i,1))<=sum(Temp_Pcg(i,k:k+UTcg(i,1)-1))];

for k = 2:27-UTcg(i,1)+1
Constraints = [Constraints, UTcg(i,1)*(Temp_Pcg(i,k)-Temp_Pcg(i,k-1))<=sum(Temp_Pcg(i,k:k+UTcg(i,1)-1))];
end

for k = 27-UTcg(i,1)+2:27
Constraints = [Constraints, 0<=sum(Temp_Pcg(i,k:27))-(27+1-k)*(Temp_Pcg(i,k)-Temp_Pcg(i,k-1))];
end

% Minimum down time
k=1;
Constraints = [Constraints, DTcg(i,1)*(-Temp_Pcg(i,k)+Temp_Pcg0(i,1))<=DTcg(i,1)-sum(Temp_Pcg(i,k:k+DTcg(i,1)-1))];

for k = 2: 27-DTcg(i,1)+1
Constraints = [Constraints, DTcg(i,1)*(Temp_Pcg(i,k-1)-Temp_Pcg(i,k))<=DTcg(i,1)-sum(Temp_Pcg(i,k:k+DTcg(i,1)-1))];
end

for k = 27-DTcg(i,1)+2:27
Constraints = [Constraints, 0<=(27+1-k)-sum(Temp_Pcg(i,k:27))-(27+1-k)*(Temp_Pcg(i,k-1)-Temp_Pcg(i,k))];
end

end

%STORAGE & VOYAGE CONSTRAINT
for k = 1:T
% Battery (ESS)
Constraints = [Constraints,-5<=PEnet(1,k)<=5]; % charge/discharge power limit
Constraints = [Constraints, implies(Temp_Pch(1,k),[PEnet(1,k)>=0,Pch(1,k)==0.95*PEnet(1,k),Pdch(1,k)==0])]; % charging
Constraints = [Constraints, implies(Temp_Pdch(1,k),[PEnet(1,k)<=0,Pdch(1,k)==PEnet(1,k)*1.05,Pch(1,k)==0])]; % discharging
Constraints = [Constraints, implies(Temp_Pstatic(1,k),[PEnet(1,k)==0,Pdch(1,k)==0,Pch(1,k)==0])]; % idle
Constraints = [Constraints,Temp_Pch(1,k)+Temp_Pdch(1,k)+Temp_Pstatic(1,k)==1];
Constraints = [Constraints,4-Einitial(1,1)<=sum(Pch(1,1:k)+Pdch(1,1:k))<=18-Einitial(1,1)]; % energy range 4-18 MWh

% Thermal storage (TSS)
Constraints = [Constraints,-2<=TEnet(1,k)<=2]; % charge/discharge power limit
Constraints = [Constraints, implies(Temp_Tch(1,k),[TEnet(1,k)>=0,Tch(1,k)==0.9*TEnet(1,k),Tdch(1,k)==0])]; % charging
Constraints = [Constraints, implies(Temp_Tdch(1,k),[TEnet(1,k)<=0,Tdch(1,k)==TEnet(1,k)*1.11,Tch(1,k)==0])]; % discharging
Constraints = [Constraints, implies(Temp_Tstatic(1,k),[TEnet(1,k)==0,Tdch(1,k)==0,Tch(1,k)==0])]; % idle
Constraints = [Constraints,Temp_Tch(1,k)+Temp_Tdch(1,k)+Temp_Tstatic(1,k)==1];	
Constraints = [Constraints,-Einitial(2,1)<=sum(Tch(1,1:k)+Tdch(1,1:k))<=3-Einitial(2,1)]; % energy range 0-3 MWh

% Hydrogen storage
Constraints = [Constraints,-90<=HEnet(1,k)<=90]; % charge/discharge limit
Constraints = [Constraints, implies(Temp_Hch(1,k),[HEnet(1,k)>=0,Hch(1,k)==HEnet(1,k),Hdch(1,k)==0])]; % charging
Constraints = [Constraints, implies(Temp_Hdch(1,k),[HEnet(1,k)<=0,Hdch(1,k)==HEnet(1,k),Hch(1,k)==0])]; % discharging
Constraints = [Constraints, implies(Temp_Hstatic(1,k),[HEnet(1,k)==0,Hdch(1,k)==0,Hch(1,k)==0])]; % idle
Constraints = [Constraints,Temp_Hch(1,k)+Temp_Hdch(1,k)+Temp_Hstatic(1,k)==1];	
Constraints = [Constraints,-800<=sum(Hch(1,1:k)+Hdch(1,1:k))<=0]; % initial content 1000 kg, keep at least 20% for unexpected events

% Freshwater tank
Constraints = [Constraints,-100<=WEnet(1,k)<=100]; % charge/discharge limit
Constraints = [Constraints, implies(Temp_Wch(1,k),[WEnet(1,k)>=0,Wch(1,k)==WEnet(1,k),Wdch(1,k)==0])]; % charging
Constraints = [Constraints, implies(Temp_Wdch(1,k),[WEnet(1,k)<=0,Wdch(1,k)==WEnet(1,k),Wch(1,k)==0])]; % discharging
Constraints = [Constraints, implies(Temp_Wstatic(1,k),[WEnet(1,k)==0,Wdch(1,k)==0,Wch(1,k)==0])]; % idle
Constraints = [Constraints,Temp_Wch(1,k)+Temp_Wdch(1,k)+Temp_Wstatic(1,k)==1];	
Constraints = [Constraints,-100<=sum(Wch(1,1:k)+Wdch(1,1:k))<=300-150]; % initial content 400 m^3, capacity 500 m^3

% Voyage constraints
%Constraints = [Constraints, -0.8*Nspeed(1,k)<=Aspeed(1,k)<=1.2*Nspeed(1,k)];% speed may deviate by up to 20%
Constraints = [Constraints, Aspeed(1,k) == Nspeed(1,k)]; % Case 1: actual speed fixed to nominal speed
Constraints=[Constraints,
	sum(z_v(:,k))==1,
    sum(w_v(:,k))==1,
    Aspeed(1,k)==point_1(1,:)*w_v(:,k),   
    w_v(1,k)<=z_v(1,k),
	w_v(length(point_1),k)<=z_v(length(point_1)-1,k)];
for n =1:length(point_1)
Constraints=[Constraints,0<=w_v(n,k)];
end

for n = 1:length(point_1)-2
Constraints=[Constraints,w_v(n+1,k)<=z_v(n,k)+z_v(n+1,k)];
end
Constraints = [Constraints, PPL(1,k) == (1+Ar(1,k))*V_n(1,:)*w_v(:,k)];
%Constraints = [Constraints, Anoise(1,k) == Noise(1,:)*w_v(:,k)];% URN Constraints
end

% Storage cycles end where they start
Constraints=[Constraints,sum(Pch(1,:)+Pdch(1,:))==0];
%Constraints=[Constraints,sum(Hch(1,:)+Hdch(1,:))==0];
Constraints=[Constraints,sum(Tch(1,:)+Tdch(1,:))==0];
Constraints=[Constraints,sum(Wch(1,:)+Wdch(1,:))==0];

% Distance constraints (mid-voyage and terminal)
% Constraints = [Constraints, sum(Nspeed(1,1:B_1))*0.99<=sum(Aspeed(1,1:B_1))<=sum(Nspeed(1,1:B_1))*1.01];% middle
% Constraints = [Constraints, sum(Nspeed(1,:))<=sum(Aspeed(1,:))<=sum(Nspeed(1,:))*1.01];% terminal


%--------------- Objective -----------------------
%FRISRT stage

%START/DOWN COST
for  i =1:Ndg
Constraints = [Constraints,[Cstartcg(i,1)*(Temp_Pcg(i,1)-Temp_Pcg0(i,1))<=F3(i,1),0<=F3(i,1)]];
for k = 2:T
Constraints = [Constraints,[Cstartcg(i,1)*(Temp_Pcg(i,k)-Temp_Pcg(i,k-1))<=F3(i,k),0<=F3(i,k)]];
end
end

for k = 1:T
%MAINTENACE COST OF storage
F21 = F21+abs(Pch(1,k)+Pdch(1,k))*2.7+abs(Tch(1,k)+Tdch(1,k))*1+abs(Hch(1,k)+Hdch(1,k))*0.082;

%Second stage

%Fuel COST

F2 = F2+3*(Pcg(1,k)*3.2+Pcg(2,k)*2.4+Pcg(3,k)*2+Pcg(4,k)*1.5);
F2 = F2+(PH2P(1,k)*4+PH2P(2,k)*3);
F2 = F2+(PP2C(1,k)*4+Wwd(1,k)*0.4); % maintenance cost
F5 = F5+CPbuy(1,k)*PCI(1,k)+4*Hnet(1,k)+CWbuy(1,k)*Wbuy(1,k); % electricity + hydrogen + water purchase
Penalty_Price = 200; 
F6 = F6 + Penalty_Price * (Pls(1,k) + Pec(1,k) + Tls(1,k) + Tec(1,k));
for i =1:Ndg
	Constraints=[Constraints,
	sum(z_cg1(:,k,i))==1,
    sum(w_cg1(:,k,i))==1,
    Pcg(i,k)==point_cg1(i,:)*w_cg1(:,k,i),   
    w_cg1(1,k,i)<=z_cg1(1,k,i),
	w_cg1(t(1,1),k,i)<=z_cg1(t(1,1)-1,k,i)];
for n =1:t(1,1)
Constraints=[Constraints,0<=w_cg1(n,k,i)];
end

for n = 1:t(1,1)-2
Constraints=[Constraints,w_cg1(n+1,k,i)<=z_cg1(n,k,i)+z_cg1(n+1,k,i)];
end
Constraints = [Constraints, cost_cg_square(i,k) == CG_1(i,:)*w_cg1(:,k,i)];
F1 = F1+(cost_cg_square(i,k)*adg(i,1)+Pcg(i,k)*bdg(i,1)+Temp_Pcg(i,k)*cdg(i,1));
TCem(i,k)=(cost_cg_square(i,k)*adge(i,1)+Pcg(i,k)*bdge(i,1)+Temp_Pcg(i,k)*cdge(i,1));
F4 = F4+TCem(i,k)*0.0312*2;
end	
end

% EEOI constraint
Constraints = [Constraints, Total_CO2_Emission == sum(sum(TCem)) * Delta_t];
Total_Distance = sum(Aspeed) * Delta_t;
Constraints = [Constraints, Total_Work == Ship_GT * Total_Distance];
Constraints = [Constraints, Total_CO2_Emission <= EEOI_Limit * Total_Work*0.001*0.4];

FS = F1+F2+F21+sum(sum(F3))+F4+F5+F6;
ops = sdpsettings('solver','Gurobi');
optimize(Constraints,FS,ops);
toc % solution time


DA_DG_status = value(Temp_Pcg); % DG on/off status (4x27)
DA_FC_status = value(Temp_H2P); % FC on/off status (2x27)
DA_Aspeed    = value(Aspeed); % actual speed (1x27)
DA_PPL       = value(PPL); % propulsion load (1x27)

% 2. Day-ahead trajectories kept for comparison
% These are re-optimised in the rolling horizon; they are saved to compare day-ahead vs real-time
DA_Pcg   = value(Pcg); % planned DG output
DA_PH2P  = value(PH2P); % planned FC electrical output
DA_TH2P  = value(TH2P); % planned FC thermal output
DA_PP2C  = value(PP2C); % planned PtC power
DA_TP2C  = value(PP2C) * 3.3; % planned PtC heat
DA_Pwd   = value(Pwd); % planned WDU power
DA_Wwd   = value(Wwd); % planned WDU water output
DA_Wbuy  = value(Wbuy); % planned water purchase at port
DA_PCI   = value(PCI); % planned shore power
DA_Hnet  = value(Hnet); % planned hydrogen purchase

% planned net exchange of the four storage units
DA_PEnet = value(PEnet);
DA_TEnet = value(TEnet);
DA_HEnet = value(HEnet);
DA_WEnet = value(WEnet);
DA_Storage_Net = [DA_PEnet; DA_TEnet; DA_HEnet; DA_WEnet]; % stacked for later use

% 3. Costs and EEOI
DA_Costs = value([F1 F2 F21 sum(sum(F3)) F4 F5 F6 FS]);
DA_EEOI  = value(Total_CO2_Emission) / value(Total_Work);
save(fullfile('results','day_ahead_case1.mat'), ...
    'DA_DG_status', 'DA_FC_status', 'DA_Aspeed', 'DA_PPL', ... % fixed in the rolling horizon
    'DA_Pcg', 'DA_PH2P', 'DA_TH2P', 'DA_PP2C', 'DA_TP2C', ... % unit outputs for comparison
    'DA_Pwd', 'DA_Wwd', 'DA_Wbuy', 'DA_PCI', 'DA_Hnet', 'DA_Storage_Net', ... 
    'DA_Costs', 'DA_EEOI');

a = value([F1 F2 F21 sum(sum(F3)) F4 F5 F6 FS]);
%Noise3 = value(Anoise);

VPEnet = value(PEnet);
VPch = value(Pch);
VPdch = value(Pdch);
VTEnet = value(TEnet);
VTch = value(Tch);
VTdch = value(Tdch);
VHEnet = value(HEnet);
VHch = value(Hch);
VHdch = value(Hdch);
VWEnet = value(WEnet);
VWch = value(Wch);
VWdch = value(Wdch);

VPPL = value(PPL);
V3 = value(Aspeed);

DGsta = value(Temp_Pcg);
FCsta = value(Temp_H2P);
FRSVA = [VPEnet; VTEnet; VHEnet; VWEnet; VPPL];
ar = value([F21 sum(sum(F3)) FS]);
%save ('RDA3.mat','DGsta','FCsta','FRSVA','ar');
%save ('V3.mat','V3','Noise3');

% for deterministic results
VPcg =value(Pcg);
VPH2P =value(PH2P);
VPP2C =value(PP2C);
VWwd =value(Wwd); % generete the volume of water
VWbuy =value(Wbuy); % water purchased from port
VPCI =value(PCI);

VTH2P =value(TH2P);
TTP2C = VPP2C*3.3;

VHnet =value(Hnet);

%save ('RSPD.mat');