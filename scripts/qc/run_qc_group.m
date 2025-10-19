function run_qc_group(groupdir)
%RUN_QC_GROUP  グループフォルダ以下の全セッションに対してQCメトリクスを実行
% 例:
%   run_qc_group("/Users/keisaruwatari/Documents/nirs-project/data/group_a")

fprintf("\n=== QC GROUP START: %s ===\n", groupdir);

% --- サブフォルダ一覧（被験者単位） ---
subs = dir(groupdir);
subs = subs([subs.isdir] & ~startsWith({subs.name}, '.'));

if isempty(subs)
    warning("No subject folders found under %s", groupdir);
    return;
end

% === すべてのQCメトリクスを格納する配列 ===
Ms = [];

% --- 各被験者フォルダを順に処理 ---
for iSub = 1:numel(subs)
    subdir = fullfile(groupdir, subs(iSub).name);
    fprintf("\n[%02d/%02d] Subject: %s\n", iSub, numel(subs), subs(iSub).name);

    % === セッション候補CSVを抽出 ===
    csvs = dir(fullfile(subdir, '*', '*.csv'));

    % NeU計測本体のみ抽出（親フォルダ名と同名のCSVだけ）
    is_session = false(size(csvs));
    for k = 1:numel(csvs)
        [~, leaf] = fileparts(csvs(k).folder);
        is_session(k) = strcmp(csvs(k).name, leaf + ".csv");
    end
    csvs = csvs(is_session);

    if isempty(csvs)
        fprintf("  (no valid NeU CSVs found)\n");
        continue;
    end

    % --- 各セッションをQC ---
    for j = 1:numel(csvs)
        csvf = fullfile(csvs(j).folder, csvs(j).name);
        try
            M = qc_session_metrics(csvf);   % ← 各セッションQC（noise_frac含む）
            Ms = [Ms; M];                   % 結果を蓄積
            fprintf("  [%2d/%2d] OK: %s\n", j, numel(csvs), csvs(j).name);
        catch ME
            fprintf("  [ERR] %s: %s\n", csvs(j).name, ME.message);
        end
    end
end

% --- 全セッションの結果をまとめて出力 ---
if isempty(Ms)
    warning("No QC metrics generated.");
    return;
end

% === レポート保存先 ===
repdir = fullfile(fileparts(groupdir), 'reports');   % data の親に reports フォルダ
if ~isfolder(repdir), mkdir(repdir); end

% グループ名を安全に取得
[~, group_name] = fileparts(char(groupdir));

% === 集計テーブル ===
Tsum = struct2table(Ms);

% 見やすい列順（存在する列だけを安全に移動）
optCols = ["session","n_rows","fs","duration","noise_n","noise_frac"];
keep = intersect(optCols, string(Tsum.Properties.VariableNames), 'stable');
try
    Tsum = movevars(Tsum, keep, 'Before', 1);
end

% === 書き出し ===
outf = fullfile(repdir, sprintf('qc_group_%s_%s.csv', ...
    group_name, datestr(now,'yyyymmdd_HHMM')));
writetable(Tsum, outf);
fprintf("\n✅ [QC] Saved summary: %s\n", outf);

fprintf("=== QC GROUP END ===\n\n");
end