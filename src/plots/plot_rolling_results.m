%% Figures for the real-time results (electricity, heat, hydrogen, freshwater, corrective actions)
% Run after src/real_time/rolling_horizon.m, which leaves its results in the workspace.

%% =====================================================================
% 7. Real-time electrical power balance
% =====================================================================

% 1. Data preparation
T_idx = 1:T;

% --- Sources (positive bars) ---
P_FCs  = sum(Actual_PH2P, 1); % total FC output
P_CI   = Actual_PCI; % shore power (real-time)
P_Pv   = Ppv; % PV
Actual_PEnet_total = DA_Storage_Net(1, :) + Actual_dPEnet; % actual ESS exchange = day-ahead + real-time deviation
P_Pdch = -min(Actual_PEnet_total, 0); % battery discharge

% --- Sinks (negative bars) ---
% plotted downwards, so negative
P_Pch = -max(Actual_PEnet_total, 0); % battery charge
P_Pwd = -Actual_Pwd; % WDU power
P_PtC = -Actual_PP2C; % PtC power

% stacked matrices
Pos_Data = [P_FCs', P_CI', P_Pv', P_Pdch'];
Neg_Data = [P_Pch', P_Pwd', P_PtC'];

% --- Realised total electrical load ---
Actual_Psl_Total = zeros(1, T);
for w = 1:T
    w_idx = min(w, size(EPsl_RT, 1));
    % service load with forecast error + propulsion load
    Actual_Psl_Total(w) = Pslt(w) * (1 + EPsl_RT(w_idx, 1)) + DA_PPL(w);
end

% line: DG output minus realised load (gap covered by the bars)
Net_DG_Load_Adj = sum(Actual_Pcg, 1) - (Actual_Psl_Total - Actual_Pls + Actual_Pec);

% 2. Plot
figure('Position', [100, 100, 950, 350], 'Color', 'w'); % wide figure, white background
hold on; 
set(gca, 'YGrid', 'on', 'XGrid', 'off', 'GridLineStyle', '-', 'GridColor', [0.85 0.85 0.85]);

% positive and negative stacked bars
b_pos = bar(T_idx, Pos_Data, 0.7, 'stacked', 'EdgeColor', 'k');
b_neg = bar(T_idx, Neg_Data, 0.7, 'stacked', 'EdgeColor', 'k');

% --- Colours ---
C_FCs  = [0.27, 0.45, 0.59];
C_Pv   = [0.98, 0.80, 0.60];
C_Pch  = [0.75, 0.70, 0.80];
C_Pwd  = [0.85, 0.90, 0.98];
C_CI   = [0.55, 0.70, 0.90];
C_Pdch = [0.60, 0.80, 0.60];
C_PtC  = [0.95, 0.60, 0.60];

% apply colours
b_pos(1).FaceColor = C_FCs;  b_pos(2).FaceColor = C_CI;
b_pos(3).FaceColor = C_Pv;   b_pos(4).FaceColor = C_Pdch;

b_neg(1).FaceColor = C_Pch;  
b_neg(2).FaceColor = C_Pwd;  b_neg(3).FaceColor = C_PtC;

% line: DGs minus loads
p_line = plot(T_idx, Net_DG_Load_Adj, '-k', 'LineWidth', 1.5, ...
    'Marker', 'o', 'MarkerSize', 4, 'MarkerFaceColor', 'w');


% 3. Axes and labels
set(gca, 'FontSize', 12, 'FontName', 'Times New Roman');
set(gca, 'XTick', 1:2:T); % tick every 2 periods

% y-limits with room for the legend
y_max = max([sum(Pos_Data, 2); Net_DG_Load_Adj']) * 1.3;
y_min = min([sum(Neg_Data, 2); Net_DG_Load_Adj']) * 1.2;
ylim([min(-8, y_min), max(10, y_max)]); 
xlim([0.5, T+0.5]);

xlabel('Dispatch Period', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', 'Times New Roman');
ylabel('Power (MW)', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', 'Times New Roman');

% horizontal legend on top
[l_h, obj_h] = legend([b_pos(1), b_pos(2), b_pos(3), b_pos(4), b_neg(1), b_neg(2), b_neg(3), p_line], ...
    {'FCs', 'CI', 'Pv', 'Pdch', 'Pch', 'Pwd', 'PtC', 'DGs - Adjusted Loads'}, ...
    'Orientation', 'horizontal', 'Location', 'north', 'NumColumns', 4, ...
    'FontSize', 11, 'Box', 'off');

% axes on top of bars
set(gca, 'Layer', 'top');
box on;
set(gcf,'unit','centimeters','position',[1 1 25 7]);
%% =====================================================================
% 8. Real-time thermal power balance
% =====================================================================

% 1. Data preparation
T_idx = 1:T;

% --- Realised thermal load ---
Actual_Tsl_Total = zeros(1, T);
for w = 1:T
    w_idx = min(w, size(ETsl_RT, 1));
    % thermal load with forecast error
    Actual_Tsl_Total(w) = Tsl(w) * (1 + ETsl_RT(w_idx, 1));
end

% --- Heat flows ---
P_PtC_heat = Actual_PP2C * 3.3; % PtC heat
Actual_TEnet_total = DA_Storage_Net(2, :) + Actual_dTEnet; % actual TSS exchange = day-ahead + real-time deviation
P_Tdch     = -min(Actual_TEnet_total, 0); % TSS discharge
P_Tch      = -max(Actual_TEnet_total, 0); % TSS charge

% recovered DG waste heat actually used (WHRS)
% from the heat balance: WHRS + PtC - Tec == Tsl - Tls + TEnet
% => WHRS = Tsl - Tls + TEnet - PtC + Tec
P_WHRS = Actual_Tsl_Total - Actual_Tls + Actual_TEnet_total - P_PtC_heat + Actual_Tec;
P_WHRS = max(P_WHRS, 0); % remove small negative round-off

% stacked matrices
Pos_Heat_Data = [P_PtC_heat', P_WHRS', P_Tdch'];
Neg_Heat_Data = [P_Tch']; % only TSS charging is negative

% line: thermal load (plotted below the axis)
Line_Thermal_Load_Adj = -(Actual_Tsl_Total - Actual_Tls + Actual_Tec);

% 2. Plot
figure('Position', [150, 150, 950, 300], 'Color', 'w'); % wide figure, white background
hold on; 
% light grid
set(gca, 'YGrid', 'on', 'XGrid', 'off', 'GridLineStyle', '-', 'GridColor', [0.9 0.9 0.9]);

% positive and negative stacked bars
b_pos_h = bar(T_idx, Pos_Heat_Data, 0.65, 'stacked', 'EdgeColor', 'k');
b_neg_h = bar(T_idx, Neg_Heat_Data, 0.65, 'stacked', 'EdgeColor', 'k');

% --- Colours ---
C_PtC   = [0.13, 0.33, 0.42];
C_WHRS  = [0.93, 0.51, 0.22];
C_Tdch  = [0.99, 0.86, 0.53];
C_Tch   = [0.80, 0.71, 0.64];
C_Load  = [0.68, 0.85, 0.90];

% apply colours
b_pos_h(1).FaceColor = C_PtC;  
b_pos_h(2).FaceColor = C_WHRS;
b_pos_h(3).FaceColor = C_Tdch;   

% b_neg_h may be empty if the TSS never charges
if ~isempty(b_neg_h)
    b_neg_h(1).FaceColor = C_Tch;  
end

% line: thermal load
p_line_h = plot(T_idx, Line_Thermal_Load_Adj, '-k', 'LineWidth', 1.5, ...
    'Marker', 'o', 'MarkerSize', 4, 'MarkerFaceColor', 'w');

% zero line
plot([0, T+1], [0, 0], '-k', 'LineWidth', 1);

% 3. Axes and labels
set(gca, 'FontSize', 12, 'FontName', 'Times New Roman');
set(gca, 'XTick', 1:2:T); % tick every 2 periods

% y-limits
ylim([-4, 4]);
xlim([0.5, T+0.5]);

xlabel('Dispatch Period', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', 'Times New Roman');
ylabel('Power (MW)', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', 'Times New Roman');

% horizontal legend on top
[l_h_h, obj_h_h] = legend([b_pos_h(1), b_pos_h(2), b_pos_h(3), b_neg_h(1), p_line_h], ...
    {'PtC', 'WHRS', 'Tdch', 'Tch', 'Adjusted Thermal Loads'}, ...
    'Orientation', 'horizontal', 'Location', 'north', 'NumColumns', 6, ...
    'FontSize', 12, 'Box', 'off');

% axes on top of bars
set(gca, 'Layer', 'top');
box on;
set(gcf,'unit','centimeters','position',[1 1 17 5]);

%% =====================================================================
% 9. Real-time hydrogen balance (both FCs combined)
% =====================================================================

% 1. Data preparation
T_idx = 1:T;

% --- Sources (positive bars) ---
% hydrogen tank discharge
P_Hdch = -min(DA_Storage_Net(3, :), 0);   
% hydrogen purchase
P_Hbuy = DA_Hnet;                         

% --- Sinks (negative bars) ---
% hydrogen tank charge
P_Hch  = -max(DA_Storage_Net(3, :), 0);   

% FC hydrogen use = FC power / (efficiency * LHV)
% FC1 and FC2 summed; plotted downwards
H_FCs  = -(sum(Actual_PH2P, 1) ./ (EH2P * LHV)); 

% stacked matrices
Pos_H2_Data = [P_Hdch', P_Hbuy'];
Neg_H2_Data = [P_Hch', H_FCs'];

% line: hydrogen load served (plotted below the axis)
Line_H2_Load = -(Hsl - Actual_Hls); 

% 2. Plot
figure('Position', [200, 200, 950, 300], 'Color', 'w'); % wide figure, white background
hold on; 
% light grid
set(gca, 'YGrid', 'on', 'XGrid', 'off', 'GridLineStyle', '-', 'GridColor', [0.9 0.9 0.9]);

% positive and negative stacked bars
b_pos_h2 = bar(T_idx, Pos_H2_Data, 0.65, 'stacked', 'EdgeColor', 'k');
b_neg_h2 = bar(T_idx, Neg_H2_Data, 0.65, 'stacked', 'EdgeColor', 'k');

% --- Colours ---
C_Hdch  = [0.60, 0.67, 0.70];
C_Hbuy  = [0.46, 0.60, 0.63];
C_Hch   = [0.53, 0.85, 0.75];
C_FCs   = [0.36, 0.72, 0.61];
C_Load  = [0.26, 0.80, 0.76];

% apply colours
b_pos_h2(1).FaceColor = C_Hdch;  
b_pos_h2(2).FaceColor = C_Hbuy;

% handle the case without tank charging
if ~isempty(b_neg_h2)
    b_neg_h2(1).FaceColor = C_Hch;  
    if length(b_neg_h2) > 1
        b_neg_h2(2).FaceColor = C_FCs;  
    end
end

% line: hydrogen load
p_line_h2 = plot(T_idx, Line_H2_Load, '-k', 'LineWidth', 1.5, ...
    'Marker', 'o', 'MarkerSize', 4, 'MarkerFaceColor', 'w');

% zero line
plot([0, T+1], [0, 0], '-k', 'LineWidth', 1);

% 3. Axes and labels
set(gca, 'FontSize', 12, 'FontName', 'Times New Roman');
set(gca, 'XTick', 1:2:T); % tick every 2 periods

ylim([-100, 150]); 
xlim([0.5, T+0.5]);

xlabel('Dispatch Period', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', 'Times New Roman');
ylabel('Hydrogen (kg)', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', 'Times New Roman');

% horizontal legend on top
% legend handles
if length(b_neg_h2) >= 2
    legend_handles = [b_pos_h2(1), b_pos_h2(2), b_neg_h2(1), b_neg_h2(2), p_line_h2];
    legend_labels = {'Hdch', 'Hbuy', 'Hch', 'FCs', 'H2 Loads'};
else
    legend_handles = [b_pos_h2(1), b_pos_h2(2), p_line_h2];
    legend_labels = {'Hdch', 'Hbuy', 'H2 Loads'};
end

[l_h2, obj_h2] = legend(legend_handles, legend_labels, ...
    'Orientation', 'horizontal', 'Location', 'north', 'NumColumns', 5, ...
    'FontSize', 12, 'Box', 'off');

% axes on top of bars
set(gca, 'Layer', 'top');
box on;
set(gcf,'unit','centimeters','position',[1 1 17 5]);

%% =====================================================================
% 10. Real-time freshwater balance
% =====================================================================

% 1. Data preparation
T_idx = 1:T;

% --- Sources (positive bars) ---
% WDU water output from its power (Wwd = Pwd * 1000 / 4)
W_Wwd = Actual_Pwd * 250; 

% water purchased at port
W_Wbuy = Actual_Wbuy;

% tank discharge
W_Wdch = -min(DA_Storage_Net(4, :), 0);   

% --- Sinks (negative bars) ---
% tank charge
W_Wch  = -max(DA_Storage_Net(4, :), 0);   

% stacked matrices
Pos_W_Data = [W_Wwd', W_Wbuy', W_Wdch'];
Neg_W_Data = [W_Wch']; % only tank charging is negative

% line: freshwater load served (plotted below the axis)
Line_W_Load = -(Wsl - Actual_Wls); 

% 2. Plot
figure('Position', [250, 250, 950, 300], 'Color', 'w'); % wide figure, white background
hold on; 
% light grid
set(gca, 'YGrid', 'on', 'XGrid', 'off', 'GridLineStyle', '-', 'GridColor', [0.9 0.9 0.9]);

% positive and negative stacked bars
b_pos_w = bar(T_idx, Pos_W_Data, 0.65, 'stacked', 'EdgeColor', 'k');
b_neg_w = bar(T_idx, Neg_W_Data, 0.65, 'stacked', 'EdgeColor', 'k');

% --- Colours ---
C_Wwd  = [0.28, 0.38, 0.50];
C_Wbuy = [80, 130, 132]/255;
C_Wdch = [0.60, 0.73, 0.89];
C_Wch  = [0.50, 0.65, 0.85];
C_Load = [0.20, 0.65, 0.85];

% apply colours
b_pos_w(1).FaceColor = C_Wwd;  
b_pos_w(2).FaceColor = C_Wbuy;
b_pos_w(3).FaceColor = C_Wdch;

if ~isempty(b_neg_w)
    b_neg_w(1).FaceColor = C_Wch;  
end

% line: freshwater load
p_line_w = plot(T_idx, Line_W_Load, '-k', 'LineWidth', 1.5, ...
    'Marker', 'o', 'MarkerSize', 4, 'MarkerFaceColor', 'w');

% zero line
plot([0, T+1], [0, 0], '-k', 'LineWidth', 1);

% 3. Axes and labels
set(gca, 'FontSize', 12, 'FontName', 'Times New Roman');
set(gca, 'XTick', 1:2:T); % tick every 2 periods

ylim([-120, 130]); 
xlim([0.5, T+0.5]);

xlabel('Dispatch Period', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', 'Times New Roman');
ylabel('Freshwater (m^3)', 'FontSize', 14, 'FontWeight', 'bold', 'FontName', 'Times New Roman');

% horizontal legend on top
if ~isempty(b_neg_w)
    legend_handles = [b_pos_w(1), b_pos_w(2), b_pos_w(3), b_neg_w(1), p_line_w];
    legend_labels = {'Wwd', 'Wbuy', 'Wdch', 'Wch', 'Water Loads'};
else
    legend_handles = [b_pos_w(1), b_pos_w(2), b_pos_w(3), p_line_w];
    legend_labels = {'Wwd', 'Wbuy', 'Wdch', 'Water Loads'};
end

[l_w, obj_w] = legend(legend_handles, legend_labels, ...
    'Orientation', 'horizontal', 'Location', 'north', 'NumColumns', 5, ...
    'FontSize', 12, 'Box', 'off');

% axes on top of bars
set(gca, 'Layer', 'top');
box on;
set(gcf,'unit','centimeters','position',[1 1 17 5]);

%% =====================================================================
% 11. Load shedding and curtailment
% =====================================================================
figure('Position', [300, 300, 950, 450], 'Color', 'w'); 
C_Shed = [0.85, 0.25, 0.25]; % load shedding
C_Curt = [0.45, 0.45, 0.45]; % curtailment

% --- Subplot 1: electricity ---
subplot(2,1,1); hold on;
set(gca, 'YGrid', 'on', 'XGrid', 'off', 'GridLineStyle', ':', 'GridColor', [0.8 0.8 0.8]);

% shedding up, curtailment down
b_elec_shed = bar(T_idx, Actual_Pls, 0.5, 'FaceColor', C_Shed, 'EdgeColor', 'k');
b_elec_curt = bar(T_idx, -Actual_Pec, 0.5, 'FaceColor', C_Curt, 'EdgeColor', 'k');
plot([0, T+1], [0, 0], '-k', 'LineWidth', 1.2); % zero line

% y-limits scaled to the data
max_Pls = max(Actual_Pls);
max_Pec = max(Actual_Pec);
max_elec = max(max_Pls, max_Pec);

if max_elec < 1e-4
    ylim([-0.1, 0.1]); % fallback when all values are zero
else
    % headroom for the legend
    ylim([-max_Pec*1.3 - max_elec*0.05, max_Pls*1.6 + max_elec*0.05]); 
end

xlim([0.5, T+0.5]);
set(gca, 'FontSize', 12, 'FontName', 'Times New Roman', 'XTick', 1:2:T, 'XTickLabel', []);
ylabel('Power (MW)', 'FontSize', 12, 'FontWeight', 'bold', 'FontName', 'Times New Roman');

% title('(a) Electrical Load Shedding and Energy Curtailment', 'FontWeight', 'bold', 'FontSize', 13);
legend([b_elec_shed, b_elec_curt], {'Pls (Load Shedding)', 'Pec (Curtailment)'}, ...
    'Orientation', 'horizontal', 'Location', 'northeast', 'Box', 'off', 'FontSize', 11);
box on;

% --- Subplot 2: heat ---
subplot(2,1,2); hold on;
set(gca, 'YGrid', 'on', 'XGrid', 'off', 'GridLineStyle', ':', 'GridColor', [0.8 0.8 0.8]);

b_therm_shed = bar(T_idx, Actual_Tls, 0.5, 'FaceColor', C_Shed, 'EdgeColor', 'k');
b_therm_curt = bar(T_idx, -Actual_Tec, 0.5, 'FaceColor', C_Curt, 'EdgeColor', 'k');
plot([0, T+1], [0, 0], '-k', 'LineWidth', 1.2);

% y-limits scaled to the data
max_Tls = max(Actual_Tls);
max_Tec = max(Actual_Tec);
max_therm = max(max_Tls, max_Tec);

if max_therm < 1e-4
    ylim([-0.05, 0.05]);
else
    ylim([-max_Tec*1.3 - max_therm*0.05, max_Tls*1.6 + max_therm*0.05]);
end

xlim([0.5, T+0.5]);
set(gca, 'FontSize', 12, 'FontName', 'Times New Roman', 'XTick', 1:2:T);
xlabel('Dispatch Period', 'FontSize', 13, 'FontWeight', 'bold', 'FontName', 'Times New Roman');
ylabel('Power (MW)', 'FontSize', 12, 'FontWeight', 'bold', 'FontName', 'Times New Roman');

% title('(b) Thermal Load Shedding and Heat Curtailment', 'FontWeight', 'bold', 'FontSize', 13);
legend([b_therm_shed, b_therm_curt], {'Tls (Load Shedding)', 'Tec (Curtailment)'}, ...
    'Orientation', 'horizontal', 'Location', 'northeast', 'Box', 'off', 'FontSize', 11);
box on;

set(gcf,'unit','centimeters','position',[2 2 20 8]);
%% 12. Day-ahead vs real-time comparison
figure;
subplot(2,1,1);
plot(1:T, sum(DA_Pcg, 1), 'b--', 'LineWidth', 1.5); hold on;
plot(1:T, sum(Actual_Pcg, 1), 'r-', 'LineWidth', 1.5);
title('Total DG Power Output: Day-Ahead vs Real-Time');
legend('Day-Ahead Plan', 'Real-Time Actual');
xlabel('Time Step'); ylabel('Power (MW)'); grid on;

subplot(2,1,2);
plot(1:T, DA_Pwd, 'b--', 'LineWidth', 1.5); hold on;
plot(1:T, Actual_Pwd, 'r-', 'LineWidth', 1.5);
title('WDU Power Consumption (Flexibility Activated)');
legend('Day-Ahead Plan', 'Real-Time Actual');
xlabel('Time Step'); ylabel('Power (MW)'); grid on;

