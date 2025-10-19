function out = make_stats_table_merged(groupA_dir, groupD_dir, varargin)
% make_stats_table_merged
%   QC済みCSVを group_a / group_d から読み込み、結合してサマリーを出力
%   - 優先して読む: QC_hot2000_metrics_filtered.csv
%     無ければ:      QC_hot2000_metrics_classified.csv
%     それも無ければ:QC_hot2000_metrics.csv
%
% Usage:
%   out = make_stats_table_merged(groupA_dir, groupD_dir, ...
%           'SaveTxt', true, 'SaveCsv', true, 'OutName', 'QC_merged');
%
% 出力（同ディレクトリ= groupA_dir のひとつ上に保存）:
%   <OutName>.csv           : 結合テーブル
%   <OutName>_stats.csv     : 要約統計（Overall / Group / Task×Cond）
%   <OutName>_summary.txt   : 人間向けテキスト要約
%
% 返り値 out は struct:
%   .T          : 結合テーブル
%   .overall    : overall統計
%   .byGroup    : group別統計
%   .byTaskCond : Task×Cond の mean/std
%
% 依存なし（MATLAB標準関数のみ）

    p = inputParser;
    p.addRequired('groupA_dir', @(s)ischar(s)||isstring(s));
    p.addRequired('groupD_dir', @(s)ischar(s)||isstring(s));
    p.addParameter('SaveTxt', true,  @(x)islogical(x)||ismember(x,[0 1]));
    p.addParameter('SaveCsv', true,  @(x)islogical(x)||ismember(x,[0 1]));
    p.addParameter('OutName','QC_merged', @(s)ischar(s)||isstring(s));
    p.parse(groupA_dir, groupD_dir, varargin{:});
    opt = p.Results;

    groupA_dir = string(groupA_dir);
    groupD_dir = string(groupD_dir);
    assert(isfolder(groupA_dir), 'groupA_dir not found: %s', groupA_dir);
    assert(isfolder(groupD_dir), 'groupD_dir not found: %s', groupD_dir);

    % ---- 読み込み（存在するものを自動選択） ----
    Ta = local_read_qc_csv(groupA_dir);
    Td = local_read_qc_csv(groupD_dir);
    Ta.File = string(Ta.File);
Td.File = string(Td.File);

   % ---- 必須列チェック（最低限） ----
need = ["File","BandPowerSum","AccelRMS"];

for TT = {Ta, Td}                 % ← 横結合ではなくセルでループ
    Tt = TT{1};
    miss = need(~ismember(need, string(Tt.Properties.VariableNames)));
    assert(isempty(miss), 'Missing columns: %s', strjoin(miss, ', '));
end

    % ---- 由来グループを付与 ----
    Ta.Group = repmat("A", height(Ta), 1);
    Td.Group = repmat("D", height(Td), 1);

    % ---- Task / Cond をファイルパスから推定 ----
    Ta = local_parse_task_cond(Ta);
    Td = local_parse_task_cond(Td);

    % ---- 結合 ----
    T = [Ta; Td];

    % ---- 数値列の基本統計（全体） ----
    metrics = ["BandPowerSum","AccelRMS"];
    statFun = @(x)[mean(x,'omitnan') std(x,'omitnan') min(x,[],'omitnan') max(x,[],'omitnan')];
    Svals = cellfun(@(v) statFun(T.(v)), cellstr(metrics), 'UniformOutput', false);
    overall = array2table(vertcat(Svals{:}), 'VariableNames',{'Mean','Std','Min','Max'}, ...
                          'RowNames', cellstr(metrics));

    % ---- Group別（A/D） ----
    byGroupMean = groupsummary(T, "Group", "mean", metrics);
    byGroupStd  = groupsummary(T, "Group", "std",  metrics);

    byGroup = join( ...
        renamevars(byGroupMean, "GroupCount","N_mean"), ...
        renamevars(byGroupStd,  "GroupCount","N_std"), ...
        "Keys","Group" );

    % ---- Task×Cond の mean/std ----
    hasTC = all(ismember(["Task","Cond"], string(T.Properties.VariableNames)));
    if hasTC
        gmean = groupsummary(T, ["Task","Cond"], "mean", metrics);
        gstd  = groupsummary(T, ["Task","Cond"], "std",  metrics);
        byTaskCond = join(gmean, gstd, "Keys", ["Task","Cond"]);
    else
        byTaskCond = table;
    end

    % ---- 保存先（groupA_dir の親にまとめて保存） ----
    outdir = fileparts(groupA_dir);  % data/
    outbase = fullfile(outdir, string(opt.OutName));

        if opt.SaveCsv
        % 1) 結合表
        writetable(T, outbase + ".csv");

        % 2) 統計CSV（overall は RowNames を明示列にしてから書き出し）
        O = overall;
        metricNames = string(overall.Properties.RowNames);
        O = addvars(O, metricNames, 'Before', 1, 'NewVariableNames', 'Metric');
        O.Properties.RowNames = {};   % RowNames は外す
        writetable(O, outbase + "_stats_overall.csv");

        writetable(byGroup, outbase + "_stats_byGroup.csv");
        if ~isempty(byTaskCond)
            writetable(byTaskCond, outbase + "_stats_byTaskCond.csv");
        end
    end

    if opt.SaveTxt
        fid = fopen(outbase + "_summary.txt","w");
        c = onCleanup(@()fclose(fid));
        fprintf(fid, "[QC MERGED SUMMARY]\n\n");
        fprintf(fid, "Rows: A=%d, D=%d, Total=%d\n\n", height(Ta), height(Td), height(T));
        fprintf(fid, "== Overall ==\n");
        for k=1:height(overall)
            r = overall(k,:);
            fprintf(fid, "  %-12s : mean=%.4f, std=%.4f, min=%.4f, max=%.4f\n", ...
                overall.Properties.RowNames{k}, r.Mean, r.Std, r.Min, r.Max);
        end
        fprintf(fid, "\n== By Group ==\n");
        for i=1:height(byGroup)
            fprintf(fid, "  Group %s : mean_Band=%.4f, std_Band=%.4f, mean_Accel=%.4f, std_Accel=%.4f (N_mean=%d)\n", ...
                string(byGroup.Group(i)), byGroup.mean_BandPowerSum(i), byGroup.std_BandPowerSum(i), ...
                byGroup.mean_AccelRMS(i), byGroup.std_AccelRMS(i), byGroup.N_mean(i));
        end
        if ~isempty(byTaskCond)
            fprintf(fid, "\n== By Task x Cond (mean only) ==\n");
            for i=1:height(byTaskCond)
                fprintf(fid, "  %s-%s : mean_Band=%.4f, mean_Accel=%.4f\n", ...
                    string(byTaskCond.Task(i)), string(byTaskCond.Cond(i)), ...
                    byTaskCond.mean_BandPowerSum(i), byTaskCond.mean_AccelRMS(i));
            end
        end
    end

    % ---- 画面にも要点表示 ----
    fprintf('[MERGE] A=%d, D=%d, Total=%d\n', height(Ta), height(Td), height(T));
    disp('=== Overall ==='); disp(overall);
    disp('=== By Group ==='); disp(byGroup);
    if ~isempty(byTaskCond)
        disp('=== By Task x Cond (mean/std) ==='); disp(byTaskCond(:,["Task","Cond","mean_BandPowerSum","std_BandPowerSum","mean_AccelRMS","std_AccelRMS"]));
    end

    % 返り値
    out = struct('T',T,'overall',overall,'byGroup',byGroup,'byTaskCond',byTaskCond);
end

% ===== ローカル関数群 =====

function T = local_read_qc_csv(gdir)
    cands = ["QC_hot2000_metrics_filtered.csv", ...
             "QC_hot2000_metrics_classified.csv", ...
             "QC_hot2000_metrics.csv"];
    hit = "";
    for f = cands
        p = fullfile(gdir, f);
        if isfile(p), hit = p; break; end
    end
    assert(hit~="", 'No QC CSV found under %s', gdir);
    fprintf('[LOAD] %s\n', hit);
    T = readtable(hit);
    % File は stringに
    if ismember("File", string(T.Properties.VariableNames))
        T.File = string(T.File);
    end
end

function T = local_parse_task_cond(T)
    % File 末尾のファイル名から Task(ct/dt) と Cond(control/test) を推定
    if ~ismember("File", string(T.Properties.VariableNames))
        T.Task = repmat("", height(T), 1);
        T.Cond = repmat("", height(T), 1);
        return;
    end

    bname = regexprep(string(T.File), '^.*[/\\]', ''); % basename.csv

    task = repmat("", height(T),1);
    task(contains(bname,"_ct_","IgnoreCase",true)) = "ct";
    task(contains(bname,"_dt_","IgnoreCase",true)) = "dt";

    cond = repmat("", height(T),1);
    cond(contains(bname,"_control","IgnoreCase",true)) = "control";
    cond(contains(bname,"_test","IgnoreCase",true))    = "test";

    T.Task = task;
    T.Cond = cond;
end