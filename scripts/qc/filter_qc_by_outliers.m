function [T_f, info] = filter_qc_by_outliers(qcPath, outlierListPath, outPath, varargin)
% FILTER_QC_BY_OUTLIERS
%   QC_hot2000_metrics.csv から外れ値リストの File 行を除外して保存。
%   ついでに簡単なサマリーも表示/保存できます。
%
% 使い方:
%   [T_f,info] = filter_qc_by_outliers(qcPath, outlierListPath)
%   [T_f,info] = filter_qc_by_outliers(qcPath, outlierListPath, outPath, ...
%                     'Summarize',true, 'Vars',["BandPowerSum","AccelRMS"], ...
%                     'WriteSummaryCSV',true)
%
% 引数:
%   qcPath          : QC_hot2000_metrics.csv の絶対パス
%   outlierListPath : 外れ値CSV（最低でも 'File' 列を含む）
%   outPath         : 書き出し先（省略時は qcPath と同じフォルダに
%                     'QC_hot2000_metrics_filtered.csv'）
%
% Name-Value:
%   'Summarize'       (logical, default true)
%   'Vars'            (string array, default ["BandPowerSum","AccelRMS"])
%   'WriteSummaryCSV' (logical, default true)
%
% 戻り値:
%   T_f : 除外後テーブル
%   info: 構造体（件数やパスなど）
%
% 例:
%   qa = "/Users/.../group_a/QC_hot2000_metrics.csv";
%   la = "/Users/.../group_a/QC_outliers_detected_from_recomputedZ.csv";
%   [Ta,ia] = filter_qc_by_outliers(qa, la);
%
%   qd = "/Users/.../group_d/QC_hot2000_metrics.csv";
%   ld = "/Users/.../group_d/QC_outliers_detected_from_recomputedZ.csv";
%   [Td,id] = filter_qc_by_outliers(qd, ld);

    arguments
        qcPath (1,1) string
        outlierListPath (1,1) string
        outPath (1,1) string = ""
    end
    arguments
        varargin.Summarize (1,1) logical = true
        varargin.Vars (1,:) string = ["BandPowerSum","AccelRMS"]
        varargin.WriteSummaryCSV (1,1) logical = true
    end

    assert(isfile(qcPath),  "QCファイルが見つかりません: %s", qcPath);
    assert(isfile(outlierListPath), "外れ値リストが見つかりません: %s", outlierListPath);

    if outPath == ""
        outPath = fullfile(fileparts(qcPath), "QC_hot2000_metrics_filtered.csv");
    end

    % --- 1) 読み込み（文字列で統一）
    T = readtable(qcPath, 'TextType','string');
    O = readtable(outlierListPath, 'TextType','string');

    % 外れ値CSVの File 列を取得（なければ先頭列を File とみなす保険）
    if any(strcmpi(O.Properties.VariableNames, "File"))
        ofiles = O.File;
    else
        ofiles = O{:,1};
        warning('外れ値リストに File 列が無いので、先頭列を File として扱います。');
    end
    ofiles = string(ofiles);

    % QC側の File 列チェック
    assert(any(strcmpi(T.Properties.VariableNames,"File")), ...
        "QCテーブルに File 列がありません。");

    % --- 2) 除外マスク作成（大小文字や区切り差を吸収：小文字比較）
    tfiles = string(T.File);
    isOut = ismember(lower(tfiles), lower(ofiles));
    keep  = ~isOut;

    n0 = height(T);
    n1 = nnz(keep);
    nx = nnz(isOut);

    T_f = T(keep,:);

    % --- 3) 保存
    writetable(T_f, outPath);
    fprintf('[SAVE] %s (rows=%d, removed=%d)\n', outPath, n1, nx);

    % --- 4) サマリー（任意）
    info = struct;
    info.InputQC           = qcPath;
    info.OutlierList       = outlierListPath;
    info.OutputFilteredCSV = outPath;
    info.NBefore           = n0;
    info.NAfter            = n1;
    info.NRemoved          = nx;
    info.RemovedFiles      = T.File(isOut);

    if varargin.Summarize
        vars = varargin.Vars;
        vars = vars(ismember(vars, string(T_f.Properties.VariableNames))); % 実在のみ
        if isempty(vars)
            warning('サマリー対象 Vars が見つかりませんでした。スキップします。');
        else
            % 全体サマリー
            S_overall = local_basic_stats(T_f, vars);
            disp("=== Overall summary (filtered) ===");
            disp(S_overall);

            % Task × Cond があればグループサマリー
            hasTask = ismember("Task", string(T_f.Properties.VariableNames));
            hasCond = ismember("Cond", string(T_f.Properties.VariableNames));
            if hasTask && hasCond
                if ~iscategorical(T_f.Task), T_f.Task = categorical(T_f.Task); end
                if ~iscategorical(T_f.Cond), T_f.Cond = categorical(T_f.Cond); end

                Gmean = groupsummary(T_f, ["Task","Cond"], "mean", vars);
                Gstd  = groupsummary(T_f, ["Task","Cond"], "std",  vars);

                % 表示
                disp("=== Mean by Task x Cond (filtered) ===");
                meanCols = ["Task","Cond", "mean_" + vars];
                disp(Gmean(:, meanCols));
                disp("=== Std by Task x Cond (filtered) ===");
                stdCols  = ["Task","Cond", "std_" + vars];
                disp(Gstd(:, stdCols));

                % 必要ならCSVにも
                if varargin.WriteSummaryCSV
                    [p,f,~] = fileparts(outPath);
                    writetable(S_overall, fullfile(p, f + "_overall_summary.csv"));
                    writetable(Gmean,     fullfile(p, f + "_group_mean.csv"));
                    writetable(Gstd,      fullfile(p, f + "_group_std.csv"));
                end

                info.GroupMean = Gmean;
                info.GroupStd  = Gstd;
            else
                if varargin.WriteSummaryCSV
                    [p,f,~] = fileparts(outPath);
                    writetable(S_overall, fullfile(p, f + "_overall_summary.csv"));
                end
            end
            info.Overall = S_overall;
        end
    end
end

% ===== ローカル関数 =====
function S = local_basic_stats(T, vars)
    stat = @(x)[mean(x,'omitnan') std(x,'omitnan') min(x) max(x)];
    C = cell(numel(vars),1);
    for i=1:numel(vars)
        v = vars(i);
        if isnumeric(T.(v)) || islogical(T.(v))
            C{i} = stat(T.(v));
        else
            C{i} = [NaN NaN NaN NaN];
        end
    end
    S = array2table(vertcat(C{:}), ...
        'VariableNames', {'Mean','Std','Min','Max'}, ...
        'RowNames', cellstr(vars));
end