function [bpm_on_nirs_t, lag_sec] = sync_bpm_to_nirs_time(t_rr, bpm_rr, t_nirs, hr_est_nirs, mode, opts)
% sync_hrv_nirs.m
% RR→BPM 時系列を NIRS の時間軸に同期させるユーティリティ。
% 3つの同期モード:
%   mode = 'fixed' : 固定ラグ（opts.fixed_lag_sec）
%   mode = 'marker': 共通イベントの絶対時刻差で合わせる
%                    （opts.marker_rr_time_sec, opts.marker_nirs_time_sec）
%   mode = 'xcorr' : 交差相関で自動ラグ推定（hr_est_nirs が必要）
%
% 入力:
%   t_rr, bpm_rr      : 等間隔BPMの時間軸(秒)と系列（例: rr_to_bpm で作成）
%   t_nirs            : NIRS時間軸（秒）
%   hr_est_nirs       : NIRS側の推定脈拍数（例: HOT-2000の Estimated pulse rate）
%   mode              : 'fixed' | 'marker' | 'xcorr'
%   opts              : 構造体（下の arguments 参照）
%
% 出力:
%   bpm_on_nirs_t     : NIRS時間軸上へ補間・同期したBPM
%   lag_sec           : 推定ラグ（t_rr を +lag_sec だけ未来へシフトした）

arguments
    t_rr (:,1) double
    bpm_rr (:,1) double
    t_nirs (:,1) double
    hr_est_nirs (:,1) double = []
    mode (1,:) char {mustBeMember(mode,{'fixed','marker','xcorr'})} = 'xcorr'
    opts.fixed_lag_sec (1,1) double = 6
    opts.marker_rr_time_sec (1,1) double = NaN
    opts.marker_nirs_time_sec (1,1) double = NaN
    opts.max_lag_sec (1,1) double = 20
    opts.fs_rr (1,1) double = 4
end

switch mode
    case 'fixed'
        lag_sec = opts.fixed_lag_sec;

    case 'marker'
        assert(~isnan(opts.marker_rr_time_sec),  'marker基準: opts.marker_rr_time_sec が必要');
        assert(~isnan(opts.marker_nirs_time_sec),'marker基準: opts.marker_nirs_time_sec が必要');
        lag_sec = opts.marker_nirs_time_sec - opts.marker_rr_time_sec;

    case 'xcorr'
        if isempty(hr_est_nirs)
            error("mode='xcorr' には hr_est_nirs（NIRS側推定HR）が必要です。");
        end
        % 共通区間へ再サンプル（fs_rr）
        fs = opts.fs_rr;
        t0 = max(t_rr(1), t_nirs(1));
        t1 = min(t_rr(end), t_nirs(end));
        t_common = (t0:1/fs:t1)';

        x = interp1(t_rr,  bpm_rr,      t_common, 'linear', 'extrap');
        y = interp1(t_nirs, hr_est_nirs, t_common, 'linear', 'extrap');

        m = isfinite(x) & isfinite(y);
        x = (x(m) - mean(x(m)))./std(x(m));  % RR由来BPM
        y = (y(m) - mean(y(m)))./std(y(m));  % NIRS推定HR

        maxLag = round(opts.max_lag_sec * fs);
        [xc,lags] = xcorr(y, x, maxLag, 'coeff'); % y vs x
        [~,I] = max(xc);
        lag_sec = lags(I)/fs;

    otherwise
        error('unknown mode');
end

% ラグを反映して NIRS時間軸へ補間
t_rr_shifted = t_rr + lag_sec;
bpm_on_nirs_t = interp1(t_rr_shifted, bpm_rr, t_nirs, 'linear', 'extrap');
end

% ===== 補助: RR(ms)→等間隔BPM =====
function [t_uniform, bpm] = rr_to_bpm(rr_ms, fs)
% rr_ms: RR間隔[ms] 1列ベクトル, fs: 等間隔サンプリング周波数[Hz]
arguments
    rr_ms (:,1) double
    fs (1,1) double {mustBePositive} = 4
end
rr_s = rr_ms/1000;
t_beats = cumsum(rr_s);
t_uniform = (0:1/fs:t_beats(end))';
bpm_beats = 60./rr_s;
t_mid = t_beats - rr_s/2;
bpm = interp1(t_mid, bpm_beats, t_uniform, 'linear', 'extrap');
bpm(bpm<30 | bpm>200) = nan;
bpm = fillmissing(bpm,'movmedian',round(fs*5));
end

% ===== 補助: HOT-2000 table から時間 & 推定HR =====
function [t_nirs, hr_est] = read_from_hot2000_table(tbl)
if any(strcmpi(tbl.Properties.VariableNames,'Headset_time'))
    t_nirs = tbl.Headset_time;        % 秒想定
elseif any(strcmpi(tbl.Properties.VariableNames,'Headset_time_sec'))
    t_nirs = tbl.Headset_time_sec;
else
    t_nirs = tbl{:,2};                % フォールバック
end
if any(strcmpi(tbl.Properties.VariableNames,'Estimated_pulse_rate'))
    hr_est = tbl.Estimated_pulse_rate;
elseif any(strcmpi(tbl.Properties.VariableNames,'Estimated_pulse_rate_bpm'))
    hr_est = tbl.Estimated_pulse_rate_bpm;
else
    hr_est = [];                      % 無くても 'fixed'/'marker' は動く
end
end

% ===== 補助: RRテキスト読み込み =====
function rr_ms = load_rr_text(rr_txt_path)
rr_ms = readmatrix(rr_txt_path);
rr_ms = rr_ms(:);
end