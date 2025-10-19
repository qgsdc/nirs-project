%% run_filter_and_merge_qc.m
% - 外れ値セッション除外
% - Fileパスから Subject/Date/Task/Cond/Run を自動生成
% - Task x Cond の要約を出力
%
% 使い方:
%   rehash; clear functions
%   run_filter_and_merge_qc

%% 設定
qcPath = "/Users/keisaruwatari/Documents/nirs-project/data/group_a/QC_hot2000_metrics.csv";
% 除外リスト（1列のCSVまたはTXT, ヘッダ不要）
%   例: /absolute/path/to/session1.csv
%       /absolute/path/to/session2.csv
excludeListPath = "";  % 空なら除外なし
outFilteredCSV  = strrep(qcPath, "QC_hot2000_metrics.csv", "QC_hot2000_metrics_filtered.csv");

% 要約に使う数値列
vars = ["BandPowerSum","AccelRMS"];

%% 読み込み
assert(isfile(qcPath), "QCファイルが見つかりません: %s", qcPath);
T = readtable(qcPath, 'TextType','string');

% File 列の正規化（stringに）
if ~ismember("File", string(T.Properties.VariableNames))
    error("QCに File 列がありません。");
end
T.File = string(T.File);

%% Fileからメタ列を付与（Subject/Date/Task/Cond/Run）
T = ensureParsedColumns(T);

%% 除外リストの適用（任意）
if strlength(excludeListPath) > 0
    assert(isfile(excludeListPath), "除外リストが見つかりません: %s", excludeListPath);
    ex = readlines(excludeListPath);
    ex = string(ex);
    ex = ex(strlength(ex)>0);
    keep = ~ismember(T.File, ex);
else
    keep = true(height(T),1);
end

T_f = T(keep, :);
writetable(T_f, outFilteredCSV);
fprintf("[SAVE] %s (rows=%d)\n", outFilteredCSV, height(T_f));

%% groupsummary 用に Task/Cond を categorical に
T_f.Task = categorical(T_f.Task);
T_f.Cond = categorical(T_f.Cond);

%% 要約（Task x Cond）
varsExist = vars(ismember(vars, string(T_f.Properties.VariableNames)));
if isempty(varsExist)
    warning("要約用の数値列が見つかりません。スキップ: %s", strjoin(vars, ", "));
else
    gmean = groupsummary(T_f, ["Task","Cond"], "mean", varsExist);
    gstd  = groupsummary(T_f, ["Task","Cond"], "std",  varsExist);

    disp("=== Mean by Task x Cond (filtered) ===");
    disp(gmean(:, ["Task","Cond", strcat("mean_", varsExist)]));

    disp("=== Std by Task x Cond (filtered) ===");
    disp(gstd(:, ["Task","Cond", strcat("std_", varsExist)]));
end

%% 追加: 全体の基本統計（おまけ）
if ~isempty(varsExist)
    stat = @(x)[mean(x,'omitnan') std(x,'omitnan') min(x) max(x)];
    S = array2table( ...
        cell2mat(arrayfun(@(v) stat(T_f.(v)), varsExist, "UniformOutput", false)') );
    S.Properties.RowNames = cellstr(varsExist);
    S.Properties.VariableNames = {'Mean','Std','Min','Max'};
    disp("=== Overall summary (filtered) ===");
    disp(S);
end

%% ローカル関数: File からメタ列を作る
function T = ensureParsedColumns(T)
    % 既に列があればスキップ
    need = ["Subject","Date","Task","Cond","Run"];
    have = ismember(need, string(T.Properties.VariableNames));
    if all(have), return; end

    n = height(T);
    Subject = strings(n,1);
    Date    = strings(n,1);
    Task    = strings(n,1);
    Cond    = strings(n,1);
    Run     = nan(n,1);

    % 例パス:
    % .../20250728_iwanaga/20250728_145937_ct_control1_iwanaga/20250728_145937_ct_control1_iwanaga.csv
    % .../YYYYMMDD_name/HHMMSS_task_condX_name/HHMMSS_task_condX_name.csv
    pat_date_subject = "/(\d{8})_([A-Za-z0-9_]+)/";
    % 末端ファイル名から task/cond/run を取る
    pat_tail = "_(ct|dt)_(control|test)(\d)_";

    for i = 1:n
        fp = T.File(i);

        % Date/Subject
        tkn = regexp(fp, pat_date_subject, 'tokens', 'once');
        if ~isempty(tkn)
            Date(i)    = tkn(1);
            Subject(i) = tkn(2);
        end

        % Task/Cond/Run（ファイル名を対象）
        [~, base, ~] = fileparts(fp);
        tkn2 = regexp(base, pat_tail, 'tokens', 'once', 'ignorecase');
        if ~isempty(tkn2)
            Task(i) = string(lower(tkn2{1}));
            Cond(i) = string(lower(tkn2{2}));
            Run(i)  = str2double(tkn2{3});
        else
            % 中間ディレクトリ名からも試す
            d = fileparts(fp);
            [~, mid] = fileparts(d);
            tkn3 = regexp(mid, pat_tail, 'tokens', 'once', 'ignorecase');
            if ~isempty(tkn3)
                Task(i) = string(lower(tkn3{1}));
                Cond(i) = string(lower(tkn3{2}));
                Run(i)  = str2double(tkn3{3});
            end
        end
    end

    % 足りない値がある場合の保険（空のときは欠損文字列/NaNのまま）
    if ~ismember("Subject", string(T.Properties.VariableNames)), T.Subject = Subject; end
    if ~ismember("Date",    string(T.Properties.VariableNames)), T.Date    = Date;    end
    if ~ismember("Task",    string(T.Properties.VariableNames)), T.Task    = Task;    end
    if ~ismember("Cond",    string(T.Properties.VariableNames)), T.Cond    = Cond;    end
    if ~ismember("Run",     string(T.Properties.VariableNames)), T.Run     = Run;     end
end