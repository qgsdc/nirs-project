function out = hrv_from_rr(rr_file, opts)
% hrv_from_rr.m
% RRテキストファイル → HRV解析（時間領域 + 周波数領域）＋図表
%
% INPUT:
%   rr_file : RR間隔テキストファイルのパス
%   opts.fs : 補間サンプリング周波数 [Hz] （例：4Hz）
%   opts.plot : 図を出すか（true/false）
%
% OUTPUT:
%   out : 構造体
%       .rr         RR間隔系列（秒）
%       .t_rr       累積時間ベクトル（秒）
%       .bpm        HR系列（bpm）
%       .t_uniform  補間後の時間軸
%       .rr_interp  補間RR
%       .bpm_uniform 補間HR
%       .SDNN, .RMSSD, .LF, .HF, .LFHF : 指標値

    if nargin < 2, opts = struct; end
    if ~isfield(opts,'fs'), opts.fs = 4; end
    if ~isfield(opts,'plot'), opts.plot = true; end

    % ===== 1. RRファイル読み込み =====
    rr_ms = load(rr_file);   % 単位: ms
    rr = rr_ms(:) / 1000;    % [s]

    % ===== 2. 時間ベクトル =====
    t_rr = cumsum(rr);

    % ===== 3. 心拍数系列（bpm） =====
    bpm = 60 ./ rr;

    % ===== 4. 補間（等間隔時間軸） =====
    t_uniform = 0 : 1/opts.fs : t_rr(end);
    rr_interp = interp1(t_rr, rr, t_uniform, 'pchip');
    bpm_uniform = 60 ./ rr_interp;

    % ===== 5. 時間領域指標 =====
    SDNN = std(rr) * 1000;                     % [ms]
    RMSSD = sqrt(mean(diff(rr).^2)) * 1000;    % [ms]

    % ===== 6. 周波数領域（Welch法） =====
    [pxx,f] = pwelch(detrend(rr_interp),[],[],[],opts.fs);
    LF_band = [0.04 0.15];
    HF_band = [0.15 0.40];
    LF = bandpower(pxx,f,LF_band,'psd');
    HF = bandpower(pxx,f,HF_band,'psd');
    LFHF = LF/HF;

    % ===== 7. 結果まとめ =====
    out.rr = rr;
    out.t_rr = t_rr;
    out.bpm = bpm;
    out.t_uniform = t_uniform;
    out.rr_interp = rr_interp;
    out.bpm_uniform = bpm_uniform;
    out.SDNN = SDNN;
    out.RMSSD = RMSSD;
    out.LF = LF;
    out.HF = HF;
    out.LFHF = LFHF;

    % ===== 8. プロット =====
    if opts.plot
        figure;
        subplot(2,1,1);
        plot(t_rr, bpm, '.-'); hold on;
        plot(t_uniform, bpm_uniform, 'r-');
        xlabel('Time [s]'); ylabel('BPM');
        legend('Raw','Interpolated');
        title('Heart Rate Series');

        subplot(2,1,2);
        plot(f,10*log10(pxx));
        xlim([0 0.5]);
        xlabel('Frequency [Hz]'); ylabel('PSD [dB/Hz]');
        title(sprintf('HRV Spectrum (LF/HF=%.2f)',LFHF));
    end
end