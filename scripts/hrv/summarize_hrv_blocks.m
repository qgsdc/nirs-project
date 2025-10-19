function tbl = summarize_hrv_blocks(t_nirs, bpm_sync, blocks, rr_ms, lag_sec, opts)
% summarize_hrv_blocks.m
% Markで切った各ブロックについて、平均HR・LF/HF（BPM系列）に加えて
% RR系列から RMSSD を計算して同じ表にまとめます。
%
% 入力:
%   t_nirs   : NIRSの時間ベクトル[sec]
%   bpm_sync : NIRS時間軸に同期済みBPM（sync_bpm_to_nirs_time の出力）
%   blocks   : extract_blocks_from_marks(T) の結果（name/start/endの配列）
%   rr_ms    : RR間隔[ms]（原本。外れ値処理は本関数内で実施可）
%   lag_sec  : 推定ラグb（RR→NIRSに合わせた時間シフト, sec）
%   opts.fs  : Welch用サンプリング[Hz]（既定=4）
%   opts.rr_valid_ms : RRの有効範囲[ms]（既定=[300 2000]）
%
% 出力:
%   tbl: table
%     block, t_start, t_end, N  …（BPMベース）
%     mean_bpm, sd_bpm, median_bpm, min_bpm, max_bpm …（BPM）
%     LF, HF, LF_HF  …（BPMのWelch）
%     RMSSD_ms       …（RRから算出）
%
% 依存: pwelch (Signal Processing Toolbox)

arguments
    t_nirs (:,1) double
    bpm_sync (:,1) double
    blocks (1,:) struct
    rr_ms (:,1) double
    lag_sec (1,1) double = 0
    opts.fs (1,1) double {mustBePositive} = 4
    opts.rr_valid_ms (1,2) double = [300 2000]
end

% まずBPMベースの要約（既存関数と同等処理）
names  = {blocks.name}';
starts = [blocks.start]';
ends   = [blocks.end]';
nb = numel(starts);
mu=nan(nb,1); sd=mu; n=mu; med=mu; minv=mu; maxv=mu; LF=mu; HF=mu; LF_HF=mu; RMSSD=mu;

fs = opts.fs; bands = [0.04 0.15; 0.15 0.40];

for i=1:nb
    m = t_nirs>=starts(i) & t_nirs<ends(i);
    x = bpm_sync(m);
    n(i)   = sum(isfinite(x));
    mu(i)  = mean(x,'omitnan');
    sd(i)  = std(x,[],'omitnan');
    med(i) = median(x,'omitnan');
    minv(i)= min(x,[],'omitnan');
    maxv(i)= max(x,[],'omitnan');

    % LF/HF（十分な点数があるときのみ）
    if n(i) > 64
        x0 = x - mean(x,'omitnan');
        [pxx,f] = pwelch(x0, min(256,n(i)), [], [], fs);
        lf = trapz(f(f>=bands(1,1)&f<bands(1,2)), pxx(f>=bands(1,1)&f<bands(1,2)));
        hf = trapz(f(f>=bands(2,1)&f<bands(2,2)), pxx(f>=bands(2,1)&f<bands(2,2)));
        LF(i)=lf; HF(i)=hf; LF_HF(i)=lf/hf;
    end
end

% ---- ここからRMSSD（RR系列ベース） ----
% RRをNIRS時間に対してずらす（mid-timesで区間切りが素直）
rr_ms_clean = rr_ms(rr_ms>opts.rr_valid_ms(1) & rr_ms<opts.rr_valid_ms(2));
rr_s = rr_ms_clean/1000;                 % [s]
t_beats = cumsum(rr_s);                  % 各拍の時刻（RR終端時刻）
t_mid   = t_beats - rr_s/2 + lag_sec;    % 各RRインターバルの中心時刻（NIRS時間系にシフト）

for i=1:nb
    % ブロック時間に含まれるRRを抽出（中心時刻で判定）
    k = t_mid>=starts(i) & t_mid<ends(i);
    rr_blk = rr_ms_clean(k);             % [ms]
    if numel(rr_blk)>=3
        d = diff(rr_blk);
        RMSSD(i) = sqrt(mean(d.^2));     % [ms]
    else
        RMSSD(i) = NaN;
    end
end

% テーブル化
tbl = table(names, starts, ends, n, mu, sd, med, minv, maxv, LF, HF, LF_HF, RMSSD, ...
    'VariableNames',{'block','t_start','t_end','N','mean_bpm','sd_bpm','median_bpm','min_bpm','max_bpm','LF','HF','LF_HF','RMSSD_ms'});

end