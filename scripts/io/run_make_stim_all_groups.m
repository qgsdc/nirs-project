%% ============================================================
%  run_make_stim_all_groups.m
%  group_a と group_d の全セッションから stim.mat を自動生成し、
%  欠落チェック → 区間解析 → グループ可視化まで一括実行
% =============================================================

addpath(genpath('/Users/keisaruwatari/Documents/nirs-project/scripts'));
rehash;

proj = "/Users/keisaruwatari/Documents/nirs-project";
groups = ["group_a", "group_d"];  % ← 必要に応じて追加も可

for g = groups
    fprintf('\n\n=== Processing %s ===\n', g);
    groupdir = fullfile(proj, "data", g);

    %% Step 1: stim.mat生成（セッション名CSVのみ）
    which -all batch_make_stim_session_only;
    batch_make_stim_session_only(groupdir);

    %% Step 2: 欠落チェック
    missing = audit_missing_stim(groupdir);
    fprintf('[%s] missing stim.mat = %d\n', g, numel(missing));
    if ~isempty(missing)
        disp(missing(1:min(10,numel(missing)))); % 先頭10件だけ表示
    end

    %% Step 3: サンプルセッション（任意1件）の確認
    % 任意の1セッションを自動的に検出
    sessExample = dir(fullfile(groupdir,"**","*_test1_*"));
    if ~isempty(sessExample)
        sessdir = fullfile(sessExample(1).folder);
        stimfile = fullfile(sessdir, "stim.mat");
        if isfile(stimfile)
            load(stimfile,'events');
            fprintf('Example events from: %s\n', erase(sessdir, proj + filesep));
            disp(head(events));
        else
            fprintf('No stim.mat yet in example session: %s\n', sessdir);
        end
    end

    %% Step 4: 区間解析（Baseline=直前Rest末尾15秒）
    run_interval_metrics_group(groupdir,'BL',15);
    aggregate_interval_metrics(groupdir,15);
    plot_interval_metrics(groupdir,15);
end

fprintf('\n=== All groups finished ===\n');