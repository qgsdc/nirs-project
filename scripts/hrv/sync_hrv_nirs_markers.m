function [bpm_sync, lag_sec, blocks, tbl_summary] = sync_hrv_nirs_markers(T_hot, t_rr, bpm_rr, mode, opts)
% sync_hrv_nirs_markers.m
% HOT-2000の Mark 列（rest_start/rest_end/task1_start/task1_end/task2_start/task2_end）
% を使って HRV(BPM) を NIRS時間に同期し、ブロック要約を返すユーティリティ。
%
% 入力:
%   T_hot : HOT-2000のCSVを readtable したテーブル（Headset_time[_sec], Mark などを含む）
%   t_rr, bpm_rr : RR→BPM 等間隔化後の時間軸[sec]とBPM系列（例: rr_to_bpm の出力）
%   mode  : 'xcorr' | 'marker' | 'fixed'   （'xcorr'推奨）
%   opts  : 構造体（下の arguments 参照）
%
% 出力:
%   bpm_sync   : NIRS時間軸上へ同期・補間されたBPM
%   lag_sec    : 推定ラグ（t_rr を +lag_sec だけ未来へシフト）
%   blocks     : Mark列から抽出したブロック配列（name/start/end）
%   tbl_summary: ブロックごとのBPM要約表
%
% 依存: sync_hrv_nirs.m の下記関数
%   - sync_bpm_to_nirs_time
%   - rr_to_bpm
%   - read_from_hot2000_table
%   - load_rr_text

arguments
    T_hot table
    t_rr (:,1) double
    bpm_rr (:,1) double
    mode (1,:) char {mustBeMember(mode,{'xcorr','marker','fixed'})} = 'xcorr'
    opts.fixed_lag_sec (1,1) double = 6
    opts.marker_label (1,:) char = ''           % 例: 'task1_start'（mode='marker'時）
    opts.rr_marker_time_sec (1,1) double = NaN  % RR側の同イベント時刻（秒）
    opts.max_lag_sec (1,1) double = 20
    opts.fs_rr (1,1) double = 4
end

% NIRS時間と推定HRを取得
[t_nirs, hr_est_nirs] = read_from_hot2000_table(T_hot);

% ラグ決定
switch mode
    case 'fixed'
        lag_sec = opts.fixed_lag_sec;

    case 'marker'
        assert(~isempty(opts.marker_label), 'mode=''marker'' では opts.marker_label を指定してください');
        assert(isfinite(opts.rr_marker_time_sec), 'mode=''marker'' では opts.rr_marker_time_sec を指定してください');
        t_m = get_hot2000_marker_time(T_hot, opts.marker_label);
        lag_sec = t_m - opts.rr_marker_time_sec;

    case 'xcorr'
        assert(~isempty(hr_est_nirs), 'mode=''xcorr'' には NIRS側の推定心拍数列が必要です（Estimated_pulse_rate[_bpm]）。');
        [~, lag_sec] = sync_bpm_to_nirs_time(t_rr, bpm_rr, t_nirs, hr_est_nirs, 'xcorr', ...
                            struct('max_lag_sec', opts.max_lag_sec, 'fs_rr', opts.fs_rr));
    otherwise
        error('unknown mode');
end

% 同期（補間）
t_rr_shifted = t_rr + lag_sec;
bpm_sync = interp1(t_rr_shifted, bpm_rr, t_nirs, 'linear', 'extrap');

% ブロック抽出 → 要約
blocks = extract_blocks_from_marks(T_hot);
tbl_summary = summarize_bpm_by_blocks(t_nirs, bpm_sync, blocks);
end

%% ====== HOT-2000: 特定ラベルのマーカー時刻を1つ取得 ======
function t_marker = get_hot2000_marker_time(tbl, label)
% label: 'rest_start' | 'rest_end' | 'task1_start' | 'task1_end' | 'task2_start' | 'task2_end'
% 大文字小文字・空白・_・- を無視してマッチ
[t_nirs, mk] = local_get_time_and_mark(tbl);
normf = @(s) regexprep(lower(string(s)), '[\s_-]+', '');
target = normf(label);
normalized = normf(mk);
valid = ["reststart","restend","task1start","task1end","task2start","task2end"];
assert(any(target==valid), '未対応のlabel: %s', label);
idx = find(normalized==target, 1, 'first');
assert(~isempty(idx), 'Mark列に %s が見つかりません', label);
t_marker = t_nirs(idx);
end

%% ====== HOT-2000: すべてのマーカー時刻を取得（配列） ======
function M = get_hot2000_all_mark_times(tbl)
labels = ["rest_start","rest_end","task1_start","task1_end","task2_start","task2_end"];
[t_nirs, mk] = local_get_time_and_mark(tbl);
normf = @(s) regexprep(lower(string(s)), '[\s_-]+', '');
normalized = normf(mk);
for L = labels
    target = normf(L);
    idx = find(normalized==target);
    M.(strrep(L,'-','_')) = t_nirs(idx);
end
end

%% ====== HOT-2000: ブロック（区間）抽出 ======
function blocks = extract_blocks_from_marks(tbl)
% 想定シーケンス：rest_start→rest_end→task1_start→task1_end→task2_start→task2_end→rest_start→...
M = get_hot2000_all_mark_times(tbl);
n_cycle = min([numel(M.rest_start), numel(M.rest_end), numel(M.task1_start), numel(M.task1_end), numel(M.task2_start), numel(M.task2_end)]);
blocks = struct('name',{},'start',{},'end',{});
k = 0;
for i = 1:n_cycle
    segs = {
        'rest',  M.rest_start(i),  M.rest_end(i);
        'task1', M.task1_start(i), M.task1_end(i);
        'rest',  M.task1_end(i),   M.task2_start(i);  % task1_end→task2_start を Rest とみなす
        'task2', M.task2_start(i), M.task2_end(i)
    };
    for s = 1:size(segs,1)
        k = k+1;
        blocks(k).name  = segs{s,1}; %#ok<AGROW>
        blocks(k).start = segs{s,2}; %#ok<AGROW>
        blocks(k).end   = segs{s,3}; %#ok<AGROW>
    end
end
% end>start のみ残す
blocks = blocks(arrayfun(@(b) isfinite(b.start)&&isfinite(b.end)&&(b.end>b.start), blocks));
end

%% ====== ブロック要約：BPMの平均・標準偏差など ======
function T = summarize_bpm_by_blocks(t_nirs, bpm_on_nirs_t, blocks)
names = {blocks.name}';
starts = [blocks.start]';
ends   = [blocks.end]';
mu = nan(size(starts)); sd = mu; n = mu; med = mu; minv = mu; maxv = mu;
for i=1:numel(starts)
    m = t_nirs>=starts(i) & t_nirs<ends(i);
    x = bpm_on_nirs_t(m);
    mu(i)  = mean(x,'omitnan');
    sd(i)  = std(x,[],'omitnan');
    n(i)   = sum(isfinite(x));
    med(i) = median(x,'omitnan');
    minv(i)= min(x,[],'omitnan');
    maxv(i)= max(x,[],'omitnan');
end
T = table(names, starts, ends, n, mu, sd, med, minv, maxv, ...
          'VariableNames',{'block','t_start','t_end','N','mean_bpm','sd_bpm','median_bpm','min_bpm','max_bpm'});
end

%% ====== 内部：時間列とMark列の取得 ======
function [t_nirs, mk] = local_get_time_and_mark(tbl)
% 時間列
if any(strcmpi(tbl.Properties.VariableNames,'Headset_time'))
    t_nirs = tbl.Headset_time;
elseif any(strcmpi(tbl.Properties.VariableNames,'Headset_time_sec'))
    t_nirs = tbl.Headset_time_sec;
else
    t_nirs = tbl{:,2};
end
% Mark列
cands = {'Mark','Marker','mark','marker'};
mk = [];
for nm = cands
    if any(strcmpi(tbl.Properties.VariableNames, nm{1})), mk = tbl.(nm{1}); break; end
end
assert(~isempty(mk), 'HOT-2000テーブルに Mark 列が見つかりません');
end