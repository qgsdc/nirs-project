function T_filt = qc_filter_keep_normal_signal(qcClassFile)
% qc_filter_keep_normal_signal
%   QC分類済みCSV（qc_classify_noiseで出力したファイル）を読み込み、
%   "normal" および "signal_noise" の行のみを残して保存します。
%
% 使用例:
%   qcfile = "/Users/.../QC_hot2000_metrics_classified.csv";
%   T_filt = qc_filter_keep_normal_signal(qcfile);

    % --- ファイル存在チェック ---
    qcClassFile = string(qcClassFile);
    assert(isfile(qcClassFile), ...
        'qc_filter_keep_normal_signal:FileNotFound', ...
        'ファイルが見つかりません: %s', qcClassFile);

    fprintf('[INFO] Loading classified QC: %s\n', qcClassFile);
    T = readtable(qcClassFile);

    % --- 必須列確認 ---
    assert(ismember("Class", T.Properties.VariableNames), ...
        'QC表に "Class" 列がありません。qc_classify_noise で作成されたファイルを指定してください。');

    % --- フィルタリング ---
    keep = ismember(T.Class, ["normal","signal_noise"]);
    T_filt = T(keep,:);
    fprintf('[INFO] 保持: %d / %d 行 (%.1f%%)\n', ...
        sum(keep), height(T), 100*sum(keep)/height(T));

    % --- 保存 ---
    outPath = fullfile(fileparts(qcClassFile), ...
        "QC_hot2000_metrics_filtered.csv");
    writetable(T_filt, outPath);
    fprintf('[SAVE] %s (rows=%d)\n', outPath, height(T_filt));

    % --- 概要表示 ---
    disp('--- Class counts (filtered) ---');
    disp(groupsummary(T_filt,"Class"));
end