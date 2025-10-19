function outCsv = compute_interval_metrics(sessdir, varargin)
% 入力: セッションフォルダ（例 …/2025xx_xxxxxx_dt_test1_xxx）
% オプション: 'Fs',10, 'BL',15
p = inputParser;
addParameter(p,'Fs',10);
addParameter(p,'BL',15);
parse(p,varargin{:});
Fs = p.Results.Fs; blSec = p.Results.BL;

% 必要ファイル読込
S = load(fullfile(sessdir,'stim.mat'));      % events: table(name,onset,duration)
events = S.events; if isstruct(events), events=struct2table(events); end
events.Properties.VariableNames = lower(events.Properties.VariableNames);
w = readtable(fullfile(sessdir,'preproc_timeseries.csv')); 
% ↑ あなたの前処理出力（band-pass後の時系列）を想定
% 必須列: time, HbT_L, HbT_R （必要なら HbO/HbR も）
t = w.time; Hb = table2struct(w(:, setdiff(w.Properties.VariableNames,{'time'})));
vars = fieldnames(Hb);

% Task/Control の抽出（nameで判定）
isTask   = regexpi(string(events.name),'^\s*task1\s*$', 'once')>0 ...
         | regexpi(string(events.name),'^\s*task2\s*$', 'once')>0 ...
         | regexpi(string(events.name),'^\s*task\s*\d*$', 'once')>0;
isCtrl   = regexpi(string(events.name),'^\s*control\s*\d*$', 'once')>0 ...
         | regexpi(string(events.name),'^\s*ct(_control)?\d*$', 'once')>0;
taskTbl  = events(isTask,:);
ctrlTbl  = events(isCtrl,:);

% 各ブロックでベースライン・区間平均を計算
rows = [];
for i = 1:height(taskTbl)
    t_on = taskTbl.onset(i); t_off = t_on + taskTbl.duration(i);
    [idxBL, tBL] = get_baseline15s(t, events, t_on, Fs, blSec);
    idxTask = (t >= t_on) & (t <= t_off);

    % 同ペアのControlを「同じブロック番号」とみなして対応づけ（i番目を対応ペアに）
    if i<=height(ctrlTbl)
        c_on = ctrlTbl.onset(i); c_off = c_on + ctrlTbl.duration(i);
        idxCtrl = (t >= c_on) & (t <= c_off);
    else
        idxCtrl = false(size(t)); % 片側欠損安全策
    end

    for v = 1:numel(vars)
        x = Hb.(vars{v});
        BL    = mean(x(idxBL), 'omitnan');
        TaskM = mean(x(idxTask),'omitnan');
        CtrlM = mean(x(idxCtrl),'omitnan');

        dTask = TaskM - BL;
        dCtrl = CtrlM - BL;
        dDiff = dTask - dCtrl; % ΔΔ

        rows = [rows; {i, vars{v}, tBL(1), tBL(2), BL, TaskM, CtrlM, dTask, dCtrl, dDiff}]; %#ok<AGROW>
    end
end

T = cell2table(rows, 'VariableNames', ...
    {'block','signal','bl_t0','bl_t1','BLmean','TaskMean','CtrlMean','dTask','dCtrl','dDiff'});

outdir = fullfile(sessdir,'interval_metrics');
if ~exist(outdir,'dir'), mkdir(outdir); end
outCsv = fullfile(outdir, sprintf('interval_metrics_BL%ds.csv', blSec));
writetable(T, outCsv);
fprintf('[OK] interval metrics -> %s\n', outCsv);
end