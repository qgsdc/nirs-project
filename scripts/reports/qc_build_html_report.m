function out = qc_build_html_report(subjdir, varargin)
% qc_build_html_report  Build a simple HTML QC report per subject.
%
% USAGE:
%   out = qc_build_html_report(subjdir)
%   out = qc_build_html_report(subjdir, 'Band',[0.01 0.20], ...
%                                       'Overwrite',true, ...
%                                       'Quiet',false, ...
%                                       'Alpha',0.22)
%
% INPUT:
%   subjdir : 対象被験者ディレクトリ (例: .../data/group_a/20250405_uesugi)
%
% Name-Value:
%   Band        : [low high] Hz（バンドパス帯域, 既定 [0.01 0.20]）
%   Overwrite   : 既存PNGを再生成するか（既定 false）
%   Quiet       : 進捗を抑制（既定 false）
%   Alpha       : タスク帯の半透明度（既定 0.22）
%
% OUTPUT:
%   out : 生成した HTML のフルパス (subjdir/qc_report.html)
%
% 依存:
%   read_neu_csv.m（Headset time / HbT change(...) / Mark）

% -------------------- Parse args --------------------
p = inputParser;
addRequired(p,'subjdir',@(s)ischar(s)||isstring(s));
addParameter(p,'Band',[0.01 0.20],@(v)isnumeric(v)&&numel(v)==2&&all(v>=0));
addParameter(p,'Overwrite',false,@islogical);
addParameter(p,'Quiet',false,@islogical);
addParameter(p,'Alpha',0.22,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);
parse(p, subjdir, varargin{:});
band      = p.Results.Band(:).';
overwrite = p.Results.Overwrite;
quiet     = p.Results.Quiet;
taskAlpha = p.Results.Alpha;

subjdir = string(subjdir);
if ~isfolder(subjdir)
    error('qc_build_html_report:NotFound','Subject folder not found: %s', subjdir);
end

% -------------------- Style (unified) --------------------
leftColor  = [0.20 0.60 0.90];   % Left series
rightColor = [0.90 0.50 0.20];   % Right series
task1Color = [0.95 0.45 0.45];   % task1 band
task2Color = [0.45 0.55 0.98];   % task2 band
lwRaw      = 0.8;
lwBP       = 1.0;

% -------------------- Find sessions --------------------
% 「親フォルダ名と同名のCSV」があるディレクトリを"セッション"とみなす
allcsv = dir(fullfile(subjdir, '**', '*.csv'));
is_session = false(numel(allcsv),1);
for i = 1:numel(allcsv)
    [leaf,~] = fileparts(allcsv(i).folder);
    [~,leaf] = fileparts(allcsv(i).folder);       % 親フォルダ名
    is_session(i) = strcmp(allcsv(i).name, leaf + ".csv");
end
sessions = allcsv(is_session);
if isempty(sessions)
    error('qc_build_html_report:NoSessions','No session CSVs found under: %s', subjdir);
end

if ~quiet
    fprintf('[HTML] Found %d sessions in %s\n', numel(sessions), subjdir);
end

% -------------------- HTML preamble --------------------
html_path = fullfile(subjdir,'qc_report.html');
fid = fopen(html_path,'w');
if fid<0, error('Cannot open for write: %s', html_path); end

subjname = string(get_last_token(subjdir));

css = [
"body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:24px;}"
"h1{font-size:20px;margin:0 0 12px 0;}"
"h2{font-size:16px;margin:18px 0 8px 0;border-bottom:1px solid #ddd;padding-bottom:4px;}"
".card{border:1px solid #e5e7eb;border-radius:10px;padding:12px;margin:12px 0;background:#fff;box-shadow:0 1px 2px rgba(0,0,0,0.04);}"
".row{display:flex;gap:14px;flex-wrap:wrap;}"
".col{flex:1 1 480px;min-width:320px;}"
".meta{color:#666;font-size:12px;margin-bottom:8px;}"
"img{max-width:100%;height:auto;border:1px solid #eee;border-radius:8px;}"
".badge{display:inline-block;font-size:11px;color:#334155;background:#eef2ff;border:1px solid #c7d2fe;border-radius:999px;padding:2px 8px;margin-left:6px;}"
];

fprintf(fid,'<!doctype html>\n<html><head><meta charset="utf-8">\n');
fprintf(fid,'<title>QC Report — %s</title>\n', subjname);
fprintf(fid,'<style>%s</style>\n', strjoin(css,""));
fprintf(fid,'</head><body>\n');
fprintf(fid,'<h1>QC Report — %s <span class="badge">Band %.3g–%.3g Hz</span></h1>\n', subjname, band(1), band(2));
fprintf(fid,'<div class="meta">Generated: %s</div>\n', datestr(now,'yyyy-mm-dd HH:MM'));

% -------------------- Loop sessions --------------------
for i = 1:numel(sessions)
    sessdir = string(sessions(i).folder);
    [~,sessname] = fileparts(sessdir);
    csvf = fullfile(sessdir, sessions(i).name);

    try
        % 読み込み（ノイズフラグは必要なら後段でマスクに使う）
        [T, S] = read_neu_csv(csvf, 'Quiet', true, 'ApplyNoiseMask', false, 'Extract','HbT');
        t = double(S.t);
        % 左右 HbT を raw として扱う（S.HbT_L / S.HbT_R が SD3-SD1）
        HbT_L_raw = double(S.HbT_L);
        HbT_R_raw = double(S.HbT_R);

        % サンプリング周波数
        dt = median(diff(t));
        fs = 1/max(dt,eps);

        % バンドパス（双一次 Butterworth 4次）
        [b,a] = butter_bp(band, fs, 4);
        HbT_L_bp = filtfilt(b,a, HbT_L_raw);
        HbT_R_bp = filtfilt(b,a, HbT_R_raw);

        % タスク窓を Mark から抽出
        [win1, win2] = marks_to_windows(T);

        % QCディレクトリ
        qcdir = fullfile(sessdir,'qc');
        if ~isfolder(qcdir), mkdir(qcdir); end

        % 出力 PNG パス
        raw_png = fullfile(qcdir, sessname + "_raw.png");
        bp_png  = fullfile(qcdir, sessname + "_bp.png");

        if overwrite || ~isfile(raw_png)
            fig = figure('Visible','off'); ax = axes(fig); hold(ax,'on'); box(ax,'on');
            % 線色固定（凡例と一致）
            hL = plot(ax, t, HbT_L_raw, 'Color', leftColor , 'LineWidth', lwRaw);
            hR = plot(ax, t, HbT_R_raw, 'Color', rightColor, 'LineWidth', lwRaw);
            % タスク帯（raw も bandpass と同じ濃さ）
            draw_task_bands(ax, win1, win2, task1Color, task2Color, taskAlpha);
            xlabel(ax,'Time [s]'); ylabel(ax,'HbT (SD3-SD1)'); title(ax, sessname + " — RAW");
            legend(ax,[hL hR],{'Left','Right'},'Location','northeast');
            grid(ax,'on'); axis(ax,'tight');
            export_ax(ax, raw_png);
            close(fig);
        end

        if overwrite || ~isfile(bp_png)
            fig = figure('Visible','off'); ax = axes(fig); hold(ax,'on'); box(ax,'on');
            hL = plot(ax, t, HbT_L_bp, 'Color', leftColor , 'LineWidth', lwBP);
            hR = plot(ax, t, HbT_R_bp, 'Color', rightColor, 'LineWidth', lwBP);
            draw_task_bands(ax, win1, win2, task1Color, task2Color, taskAlpha);
            xlabel(ax,'Time [s]');
            ylabel(ax, sprintf('HbT (%.3g–%.3g Hz)', band(1), band(2)));
            title(ax, sessname + " — Bandpass");
            legend(ax,[hL hR],{'Left','Right'},'Location','northeast');
            grid(ax,'on'); axis(ax,'tight');
            export_ax(ax, bp_png);
            close(fig);
        end

        % HTML 追記（相対パスにする）
        raw_rel = relpath(raw_png, subjdir);
        bp_rel  = relpath(bp_png , subjdir);

        fprintf(fid,'<div class="card">');
        fprintf(fid,'<h2>%s</h2>\n', sessname);
        fprintf(fid,'<div class="row">');
        fprintf(fid,'<div class="col"><img src="%s" alt="%s raw"></div>\n', raw_rel, sessname);
        fprintf(fid,'<div class="col"><img src="%s" alt="%s bandpass"></div>\n', bp_rel, sessname);
        fprintf(fid,'</div></div>\n');

        if ~quiet
            fprintf('  [+] %s\n', sessname);
        end

    catch ME
        if ~quiet
            fprintf('  [SKIP] %s (%s)\n', sessname, ME.message);
        end
        % エラーでも続行（セクションだけメモ）
        fprintf(fid,'<div class="card"><h2>%s</h2><div class="meta" style="color:#b91c1c;">%s</div></div>\n', ...
            sessname, html_escape(ME.message));
    end
end

fprintf(fid,'</body></html>\n');
fclose(fid);

if ~quiet
    fprintf('✅ HTML saved: %s\n', html_path);
end
out = string(html_path);
end

% ================== Local helpers ==================
function [b,a] = butter_bp(band, fs, ord)
    if numel(band)~=2 || band(1)<=0 || band(2)>=fs/2 || band(1)>=band(2)
        error('butter_bp:InvalidBand','Invalid band or sampling: [%.4g %.4g], fs=%.4g', band(1),band(2),fs);
    end
    wn = band./(fs/2);
    [b,a] = butter(ord, wn, 'bandpass');
end

function [win1,win2] = marks_to_windows(T)
% Mark 列中の task1_start/task1_end, task2_start/task2_end を時間[s]で窓に
    win1 = zeros(0,2); win2 = zeros(0,2);
    if ~ismember('Mark', string(T.Properties.VariableNames))
        return;
    end
    M = string(T.("Mark"));
    t = double(T.("Headset time"));
    % task1
    s1 = find(strcmpi(M,'task1_start'));
    e1 = find(strcmpi(M,'task1_end'));
    % task2
    s2 = find(strcmpi(M,'task2_start'));
    e2 = find(strcmpi(M,'task2_end'));

    win1 = pair_to_windows(t, s1, e1);
    win2 = pair_to_windows(t, s2, e2);
end

function W = pair_to_windows(t, sidx, eidx)
    W = zeros(0,2);
    n = min(numel(sidx), numel(eidx));
    if n==0, return; end
    sidx = sidx(1:n); eidx = eidx(1:n);
    bad = eidx<=sidx; sidx(bad)=[]; eidx(bad)=[];
    n = numel(sidx);
    if n==0, return; end
    W = [t(sidx) t(eidx)];
end

function draw_task_bands(ax, win1, win2, c1, c2, alpha)
    yl = ylim(ax);
    hold(ax,'on');
    for k=1:size(win1,1)
        xr = win1(k,:);
        if any(isnan(xr)), continue; end
        p = patch(ax,[xr(1) xr(2) xr(2) xr(1)],[yl(1) yl(1) yl(2) yl(2)], c1, ...
                  'FaceAlpha',alpha,'EdgeColor','none','HitTest','off');
        uistack(p,'bottom');
    end
    for k=1:size(win2,1)
        xr = win2(k,:);
        if any(isnan(xr)), continue; end
        p = patch(ax,[xr(1) xr(2) xr(2) xr(1)],[yl(1) yl(1) yl(2) yl(2)], c2, ...
                  'FaceAlpha',alpha,'EdgeColor','none','HitTest','off');
        uistack(p,'bottom');
    end
end

function export_ax(ax, outpng)
    % 軸ツールバー非表示（バージョン差吸収）
    try
        ax.Toolbar.Visible = 'off';
    catch
        try axtoolbar(ax,'Visible','off'); end %#ok<TRYNC>
    end
    exportgraphics(ax, outpng, 'Resolution', 150, 'BackgroundColor','white');
end

function s = get_last_token(p)
    p = string(p);
    tok = split(p, filesep);
    s = tok(find(tok~="",1,'last'));
end

function r = relpath(target, base)
% base から target への相対パス（MATLAB R2023b/R2025b 互換）
    target = char(string(target));
    base   = char(string(base));
    try
        r = char(string(relativepath(target, base))); % 新しめの関数があれば
        if ~isempty(r), return; end
    catch
    end
    % 手作り版
    tgt = java.io.File(target).getCanonicalPath();
    bas = java.io.File(base  ).getCanonicalPath();
    spT = split(string(tgt), filesep); spB = split(string(bas), filesep);
    i = 1;
    while i<=min(numel(spT),numel(spB)) && spT(i)==spB(i)
        i = i+1;
    end
    ups = repmat("..",1, numel(spB)-i+1);
    down = spT(i:end);
    if isempty(ups), parts = down; else, parts = [ups down]; end
    r = char(fullfile(parts{:}));
end

function s = html_escape(s)
    s = string(s);
    s = strrep(s,'&','&amp;');
    s = strrep(s,'<','&lt;');
    s = strrep(s,'>','&gt;');
    s = strrep(s,'"','&quot;');
    s = strrep(s,'''','&#39;');
end