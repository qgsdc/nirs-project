%% qc_detect_outliers.m
% HOT-2000 QC統合データから外れ値セッションを抽出（列名ゆらぎ対応）
% 2025-10-19

clear; clc;

% === 入力 ===
qcfile = '/Users/keisaruwatari/Documents/nirs-project/data/group_d/QC_hot2000_metrics.csv';
T = readtable(qcfile);

% 変数名一覧を string 配列で
names = string(T.Properties.VariableNames);

% 小道具: 指定トークンすべてを「含む」列名を拾う
pick = @(tokens) local_pick_var(names, tokens);

% 主要メトリクスを列名自動検出
metricVars = strings(0,1);

% そのままの基本列
if any(names=="BandPowerSum"), metricVars(end+1) = "BandPowerSum"; end
if any(names=="AccelRMS"),     metricVars(end+1) = "AccelRMS";     end

% HbT 1cm（左/右）の Std をパターンで拾う（Fun_ の有無や _ の数違いに対応）
leftStd  = pick(["HbTChange","left","SD1cm","Std"]);
rightStd = pick(["HbTChange","right","SD1cm","Std"]);

if leftStd ~= "",  metricVars(end+1) = leftStd;  end
if rightStd ~= "", metricVars(end+1) = rightStd; end

% 一つも見つからなかったら、テーブル表示して終了
if isempty(metricVars)
    error('外れ値判定に使う指標が見つかりませんでした。利用可能な列は:\n%s', strjoin(names, ', '));
end

fprintf('[INFO] 外れ値判定に用いる列: %s\n', strjoin(metricVars, ', '));

% === Zスコア算出 & 外れ値判定 ===
thr = 3;  % ±3SD 基準
for i = 1:numel(metricVars)
    v = T.(metricVars(i));
    z = (v - mean(v,'omitnan')) ./ std(v,'omitnan');
    T.("Z_"+metricVars(i)) = z;
end

Zcols = startsWith(string(T.Properties.VariableNames),"Z_");
T.IsOutlier = any(abs(T{:,Zcols}) > thr, 2);

% === 外れ値一覧 ===
out = T(T.IsOutlier,:);
fprintf('[INFO] 外れ値候補セッション: %d件\n', height(out));

showCols = ["File","AccelRMS","BandPowerSum",leftStd,rightStd, ...
            "IsOutlier", "Subject","Task","Cond"];
showCols = intersect(showCols, string(T.Properties.VariableNames), 'stable');

disp(out(:, cellstr(showCols)));

% 指標別件数
fprintf('\n--- 外れ値の指標別件数 (|Z|>%g) ---\n', thr);
for i = 1:numel(metricVars)
    f = abs(T.("Z_"+metricVars(i))) > thr;
    fprintf('%-30s : %2d 件\n', metricVars(i), sum(f));
end

% === 保存 ===
outcsv = fullfile(fileparts(qcfile), 'QC_outliers_detected.csv');
writetable(out, outcsv);
fprintf('[QC] 外れ値リストを書き出しました: %s\n', outcsv);

%% ===== local functions =====
function varname = local_pick_var(names, tokens)
% names: string array of variable names
% tokens: string array, ALL must be contained (case-insensitive)
m = true(size(names));
for t = tokens(:)'
    m = m & contains(lower(names), lower(t));
end
if any(m)
    % 最長一致（より具体的な列名を優先）
    cand = names(m);
    [~,ix] = max(strlength(cand));
    varname = cand(ix);
else
    varname = "";
end
end