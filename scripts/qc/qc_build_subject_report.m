function out = qc_build_subject_report(csv_or_dir, varargin)
% qc_build_subject_report  個人QCレポート（Raw vs Band-pass比較つき）
%
% out = qc_build_subject_report(csv_or_dir, Name,Value,...)
%
% 入力:
%   csv_or_dir : セッションCSVのフルパス もしくは セッションフォルダ
%                （フォルダを渡した場合は <folder>/<leaf>.csv を自動探索）
%
% Name-Value:
%   'OutDir'         : 出力先フォルダ（既定: セッションフォルダ内 'qc'）
%   'PlotFiltered'   : band-pass後も描画するか（既定: true）
%   'FilterRange'    : [low high] (Hz) （既定: [0.01 0.2]）
%   'ApplyNoiseMask' : noise flagで HbTのみ NaN マスク（既定: true）
%   'Quiet'          : メッセージ抑制（既定: false）
%   'SaveFigures'    : 図の保存（PNG/PDF）（既定: true）
%
% 依存:
%   read_neu_csv.m  （本スレの最新版 / Name-Value対応版）
%
% 出力:
%   out : 構造体（基本統計と保存先パス）
%
% 例:
%   csvf = "/Users/you/nirs/data/group_a/20251011_xxx/20251011_xxx.csv";
%   qc_build_subject_report(csvf,'FilterRange',[0.01 0.2],'PlotFiltered',true);

% -------------------- 引数 --------------------
ip = inputParser;
ip.addRequired('csv_or_dir', @(x)ischar(x)||isstring(x));
ip.addParameter('OutDir', "", @(x)ischar(x)||isstring(x));
ip.addParameter('PlotFiltered', true, @(x)islogical(x)&&isscalar(x));
ip.addParameter('FilterRange', [0.01 0.2], @(x)isnumeric(x)&&numel(x)==2&&all(x>0));
ip.addParameter('ApplyNoiseMask', true, @(x)islogical(x)&&isscalar(x));
ip.addParameter('Quiet', false, @(x)islogical(x)&&isscalar(x));
ip.addParameter('SaveFigures', true, @(x)islogical(x)&&isscalar(x));
ip.parse(csv_or_dir, varargin{:});

OutDir         = string(ip.Results.OutDir);
PlotFiltered   = ip.Results.PlotFiltered;
FilterRange    = double(ip.Results.FilterRange(:))';
ApplyNoiseMask = ip.Results.ApplyNoiseMask;
Quiet          = ip.Results.Quiet;
SaveFigures    = ip.Results.SaveFigures;

% -------------------- パス解決 --------------------
p = string(csv_or_dir);
if isfolder(p)
    leaf = string(extractAfter(p, filesep));
    if leaf == ""
        [~,leaf] = fileparts(p);
    end
    csvf = fullfile(p, leaf + ".csv");
else
    csvf = p;
    [p,leaf] = fileparts(csvf);
end
if ~isfile(csvf)
    error('QC:NoCSV','CSV not found: %s', csvf);
end

% 出力フォルダ
if OutDir == ""
    OutDir = fullfile(p, "qc");
end
if ~isfolder(OutDir)
    mkdir(OutDir);
end

% -------------------- 読み込み（HbT抽出つき） --------------------
% S: time_device, t, pulse, HbT_L, HbT_R, Mark
try
    [T,S] = read_neu_csv(csvf, ...
        'ApplyNoiseMask', ApplyNoiseMask, ...
        'Quiet', Quiet, ...
        'Extract','HbT');   %#ok<ASGLU>  % Tは必要なら使える
catch ME
    error('QC:ReadFail','read_neu_csv failed: %s', ME.message);
end

t   = double(S.t(:));
HbL = double(S.HbT_L(:));
HbR = double(S.HbT_R(:));

% 無限・非数を整理
bad = ~isfinite(t) | ~isfinite(HbL) | ~isfinite(HbR);
t(bad) = []; HbL(bad) = []; HbR(bad) = [];

% サンプリング周波数推定
if numel(t) < 10
    error('QC:Short','Too few samples after cleaning');
end
dt = median(diff(t));
fs = 1/max(dt, eps);

% -------------------- band-pass フィルタ --------------------
fL = FilterRange(1); fH = FilterRange(2);
doFilt = PlotFiltered && fL < fH && fH < (fs/2);
if doFilt
    % 4次Butterworth, zero-phase
    [b,a] = butter(4, [fL, fH] / (fs/2), 'bandpass');
    HbL_f = filtfilt(b,a,HbL);
    HbR_f = filtfilt(b,a,HbR);
else
    HbL_f = [];
    HbR_f = [];
end

% -------------------- ノイズ率の概算（フラグ→NaN化後の欠損率） --------------------
noise_frac = mean(~isfinite(double(S.HbT_L(:))) | ~isfinite(double(S.HbT_R(:))));
if isnan(noise_frac), noise_frac = 0; end

% -------------------- 図作成 --------------------
ts = datestr(now,'yyyymmdd_HHMM');
base = leaf + "_qc_" + ts;
png1 = fullfile(OutDir, base + "_timeseries.png");
png2 = fullfile(OutDir, base + "_psd.png");
pdf  = fullfile(OutDir, base + ".pdf");

% （1）時系列 Raw vs Filtered
f1 = figure('Color','w','Units','pixels','Position',[100 100 1200 500]); %#ok<NASGU>
tmin = t(1); tt = t - tmin;
subplot(2,1,1);
plot(tt, HbL, 'DisplayName','HbT L (raw)'); hold on;
plot(tt, HbR, 'DisplayName','HbT R (raw)');
xlabel('Time (s)'); ylabel('\DeltaHbT'); title('Raw HbT (L/R)');
grid on; legend('show');

subplot(2,1,2);
if doFilt
    plot(tt, HbL_f, 'DisplayName',sprintf('HbT L (BP %.3g–%.3g Hz)', fL, fH)); hold on;
    plot(tt, HbR_f, 'DisplayName',sprintf('HbT R (BP %.3g–%.3g Hz)', fL, fH));
    title('Filtered HbT');
else
    plot(tt, HbL, 'DisplayName','HbT L (raw)'); hold on;
    plot(tt, HbR, 'DisplayName','HbT R (raw)');
    title('Filtered HbT (disabled)');
end
xlabel('Time (s)'); ylabel('\DeltaHbT'); grid on; legend('show');

if SaveFigures
    exportgraphics(gcf, png1, 'Resolution', 200);
end

% （2）PSD Raw vs Filtered（Welch）
f2 = figure('Color','w','Units','pixels','Position',[150 150 1200 500]); %#ok<NASGU>
Nw = min( floor(fs*64), numel(HbL) );  % セグメント長（適度）
if Nw < 16, Nw = min(256, numel(HbL)); end
[PL,freq] = pwelch(HbL, Nw, round(0.5*Nw), [], fs);
[PR,~]   = pwelch(HbR, Nw, round(0.5*Nw), [], fs);
loglog(freq, PL, 'DisplayName','L raw'); hold on;
loglog(freq, PR, 'DisplayName','R raw');
if doFilt
    [PLf,~] = pwelch(HbL_f, Nw, round(0.5*Nw), [], fs);
    [PRf,~] = pwelch(HbR_f, Nw, round(0.5*Nw), [], fs);
    loglog(freq, PLf, 'DisplayName','L filtered');
    loglog(freq, PRf, 'DisplayName','R filtered');
end
xline([fL fH],'--k','HandleVisibility','off');  % pass帯の目安
grid on; xlabel('Frequency (Hz)'); ylabel('Power'); title('Power Spectrum (Welch)');
legend('show','Location','southwest');
xlim([max(1e-3, freq(2)) fs/2]);

if SaveFigures
    exportgraphics(gcf, png2, 'Resolution', 200);
end

% -------------------- 簡易PDF（Report Generator無しでもOK） --------------------
if SaveFigures
    try
        import mlreportgen.report.*
        import mlreportgen.dom.*

        rpt  = Report(char(pdf), 'pdf');
        open(rpt);

        tp = TitlePage;
        tp.Title  = sprintf('QC Report (Subject) - %s', leaf);
        tp.Author = 'fNIRS Project';
        add(rpt, tp);
        add(rpt, TableOfContents);

        ch = Chapter(sprintf('Summary: %s', leaf));
        p  = Paragraph(sprintf(['fs=%.3f Hz, N=%d, noise_frac=%.4f\n' ...
            'Filter: [%g %g] Hz (applied=%d)'], fs, numel(tt), noise_frac, fL, fH, doFilt));
        p.WhiteSpace = 'preserve'; add(ch, p);

        add(ch, Image(char(png1)));
        add(ch, Image(char(png2)));
        add(rpt, ch);

        close(rpt);
        out.pdf = string(rpt.OutputPath);
        if ~Quiet, fprintf('✅ Report Generator で作成: %s\n', out.pdf); end
    catch
        % フォールバック（画像→PDF）
        try
            fig = figure('Visible','off'); imshow(imtile({png1,png2})); %#ok<IMSHO>
            exportgraphics(fig, pdf, 'Resolution', 200); close(fig);
            out.pdf = pdf;
            if ~Quiet
                warning('ReportGenなしフォールバックでPDF作成: %s', pdf);
            end
        catch
            out.pdf = "";  % 失敗時は空
        end
    end
else
    out.pdf = "";
end

% -------------------- 出力構造体 --------------------
out.session_csv  = string(csvf);
out.outdir       = string(OutDir);
out.png_timeser  = string(png1);
out.png_psd      = string(png2);
out.fs           = fs;
out.n_rows       = numel(tt);
out.noise_frac   = noise_frac;
out.filter_applied = logical(doFilt);
out.filter_range   = [fL fH];

if ~Quiet
    fprintf('[QC Subject] %s: fs=%.3fHz, N=%d, noise_frac=%.4f, saved in %s\n', ...
        leaf, fs, numel(tt), noise_frac, OutDir);
end
end