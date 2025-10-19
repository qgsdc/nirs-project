function S = qc_session_metrics(rootdir, varargin)
% qc_session_metrics — QC指標を subject×session で集約（最新版）
%
% 使い方:
%   S = qc_session_metrics(rootdir);
%   S = qc_session_metrics(rootdir, 'Band',[0.01 0.2], 'SaveCSV',true);
%
% 入出力:
%   入力 rootdir : 被験者フォルダ群（group_* 等）を含むルート
%   出力 S       : subject×session の集約テーブル
%
% オプション（主なもの）:
%   'Band'          : 相対帯域パワーの帯域 [lo hi]（qc_hot2000_metricsへ委譲）
%   'MinRunSec'     : フラグrunの最短秒（同上）
%   'ApplyNoiseMask': ノイズマスク適用（同上）
%   'Verbose'       : 進捗表示
%   'SaveCSV'       : 集約CSVを保存するか（デフォルト true）
%   'OutPath'       : 保存パス（未指定なら自動命名）
%
% 備考:
%   先に qc_hot2000_metrics で CSV→timetable 変換・QC算出を行い、
%   その結果テーブルDを subject×sessionで集約します。

p = inputParser;
addRequired(p, 'rootdir', @(s)ischar(s) || isstring(s));
addParameter(p, 'Band', [0.01 0.20], @(v)isnumeric(v) && numel(v)==2);
addParameter(p, 'MinRunSec', 3, @(x)isnumeric(x) && isscalar(x) && x>=0);
addParameter(p, 'ApplyNoiseMask', true, @(x)islogical(x) || ismember(x,[0 1]));
addParameter(p, 'Verbose', true, @(x)islogical(x) || ismember(x,[0 1]));
addParameter(p, 'SaveCSV', true, @(x)islogical(x) || ismember(x,[0 1]));
addParameter(p, 'OutPath', '', @(s)ischar(s) || isstring(s));
parse(p, rootdir, varargin{:});
Band          = p.Results.Band;
MinRunSec     = p.Results.MinRunSec;
ApplyMask     = logical(p.Results.ApplyNoiseMask);
Verbose       = logical(p.Results.Verbose);
SaveCSV       = logical(p.Results.SaveCSV);
OutPath       = string(p.Results.OutPath);

rootdir = string(rootdir);

% 1) まずファイル別QCを作成
if Verbose; fprintf('[SESSION] Collecting per-file QC…\n'); end
D = qc_hot2000_metrics(rootdir, ...
    'Band',Band, 'MinRunSec',MinRunSec, ...
    'ApplyNoiseMask',ApplyMask, 'SaveCSV',false, ...
    'Verbose',Verbose);

if isempty(D) || height(D)==0
    warning('[SESSION] ファイル別QCが空です（対象が無い/全スキップ）');
    S = table(); return;
end

% 2) 欠損を数値に
numvars = {'nRows','Fs','duration_sec','pctNaN','pctFlag', ...
           'motion_frac_gt5sd','drift_ppm_per_min','amp_mad','amp_iqr', ...
           'bp_rel','nRuns_geMinSec','sig_nChan','sig_5pct','sig_50pct','sig_95pct'};
for i = 1:numel(numvars)
    if ~ismember(numvars{i}, D.Properties.VariableNames); continue; end
    if ~isnumeric(D.(numvars{i}))
        D.(numvars{i}) = double(D.(numvars{i}));
    end
end

% 3) group summary: subject×session
[grp,~,ix] = unique(D(:,{'subject','session'}), 'rows');
G = groupsummary(D, {'subject','session'});

% groupsummary だと列名が長くなるので、独自に主要統計をまとめ直す
ng = height(grp);
rows = cell(ng, 1);
for g = 1:ng
    sel = (ix==g);
    Di  = D(sel,:);
    nFiles = height(Di);

    % 代表値（重みなしの素直な代表統計）
    Fs_median      = median(Di.Fs, 'omitnan');
    dur_total_sec  = nansum(Di.duration_sec);
    dur_min        = dur_total_sec/60;

    pctNaN_mean    = mean(Di.pctNaN, 'omitnan');
    pctFlag_mean   = mean(Di.pctFlag, 'omitnan');
    motion_mean    = mean(Di.motion_frac_gt5sd, 'omitnan');
    drift_median   = median(Di.drift_ppm_per_min, 'omitnan');
    amp_mad_median = median(Di.amp_mad, 'omitnan');
    amp_iqr_median = median(Di.amp_iqr, 'omitnan');
    bp_rel_mean    = mean(Di.bp_rel, 'omitnan');

    runs_sum       = nansum(Di.nRuns_geMinSec);
    nChan_median   = median(Di.sig_nChan, 'omitnan');
    rms5_median    = median(Di.sig_5pct, 'omitnan');
    rms50_median   = median(Di.sig_50pct, 'omitnan');
    rms95_median   = median(Di.sig_95pct, 'omitnan');

    rows{g,1} = { ...
        string(grp.subject(g)), string(grp.session(g)), nFiles, ...
        Fs_median, dur_total_sec, dur_min, ...
        pctNaN_mean, pctFlag_mean, motion_mean, drift_median, ...
        amp_mad_median, amp_iqr_median, bp_rel_mean, ...
        runs_sum, nChan_median, rms5_median, rms50_median, rms95_median};
end

S = cell2table(vertcat(rows{:}), 'VariableNames', { ...
    'subject','session','nFiles', ...
    'Fs_median','duration_sec_total','duration_min_total', ...
    'pctNaN_mean','pctFlag_mean','motion_frac_gt5sd_mean','drift_ppm_per_min_median', ...
    'amp_mad_median','amp_iqr_median','bp_rel_mean', ...
    'nRuns_geMinSec_sum','sig_nChan_median','sig_rms_5pct_median', ...
    'sig_rms_50pct_median','sig_rms_95pct_median'});

% 4) 保存
if SaveCSV && ~isempty(S)
    if OutPath == ""
        [parentDir, groupName] = fileparts(rootdir);
        if groupName == ""; [parentDir, groupName] = fileparts(parentDir); end
        ts = datestr(now, 'yyyymmdd_HHMMSS');
        OutPath = fullfile(parentDir, sprintf('qc_session_metrics_%s_%s.csv', groupName, ts));
    end
    try
        if ~isfolder(fileparts(OutPath)); mkdir(fileparts(OutPath)); end
        writetable(S, OutPath);
        if Verbose
            fprintf('[SESSION] saved session summary: %s\n', OutPath);
        end
    catch ME
        warning('[SESSION] CSV保存に失敗: %s -> %s', OutPath, ME.message);
    end
end
end