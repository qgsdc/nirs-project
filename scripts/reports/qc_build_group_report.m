function outpath = qc_build_group_report(qc_csv, varargin)
% qc_build_group_report  ── QC CSV からグループレポート(PDF/PNG)を生成
%
% outpath = qc_build_group_report(qc_csv, 'Name',Value, ...)
%
% Name-Value:
%   OutDir            出力ディレクトリ (default: fileparts(qc_csv))
%   GroupName         レポート表紙に出すグループ名 (default: auto from csv)
%   UseReportGenerator trueならReport GeneratorでPDF化を試みる (default: true)
%   TopN              サマリ表・棒グラフで表示する上位件数 (default: 12)
%
% 入力となる qc_csv は run_qc_group が吐く CSV を想定
% 必須列: session, noise_n, noise_frac
% あれば使う列: n_rows, fs, duration
%
% 依存: なし（Report Generatorは任意）

%% ---- parse args ---------------------------------------------------------
p = inputParser;
p.addRequired('qc_csv', @(s)ischar(s) || isstring(s));
p.addParameter('OutDir', '', @(s)ischar(s) || isstring(s));
p.addParameter('GroupName', '', @(s)ischar(s) || isstring(s));
p.addParameter('UseReportGenerator', true, @(x)islogical(x) || isnumeric(x));
p.addParameter('TopN', 12, @(x)isnumeric(x) && isscalar(x) && x>0);
p.parse(qc_csv, varargin{:});
args = p.Results;

qc_csv = string(qc_csv);
outdir = string(args.OutDir);
if outdir == "", outdir = string(fileparts(qc_csv)); end
if ~isfolder(outdir), mkdir(outdir); end
group = string(args.GroupName);
if group == ""
    % .../qc_group_<group>_YYYYMMDD_HHMM.csv から推定
    tok = regexp(qc_csv, "qc_group_([^_]+)_\d{8}_\d{4}\.csv$", "tokens", "once");
    if ~isempty(tok), group = tok{1}; else, group = "group"; end
end
TopN = args.TopN;

ts = datestr(now,'yyyymmdd_HHMM');

%% ---- load table & column normalization ---------------------------------
Q = readtable(qc_csv);

% 正規化（列の有無に頑健）
needCols = ["session","noise_n","noise_frac"];
optCols  = ["n_rows","fs","duration"];
for c = needCols
    if ~ismember(c, string(Q.Properties.VariableNames))
        error("qc_build_group_report:badcsv", ...
              "Required column '%s' not found in %s", c, qc_csv);
    end
end
for c = optCols
    if ~ismember(c, string(Q.Properties.VariableNames))
        Q.(c) = NaN(height(Q),1);
    end
end

% 文字列化
Q.session   = string(Q.session);
if ~isnumeric(Q.noise_n),     Q.noise_n     = double(Q.noise_n);     end
if ~isnumeric(Q.noise_frac),  Q.noise_frac  = double(Q.noise_frac);  end

% 主体（被験者）名を抽出: .../group_a/YYYYMMDD_subject/...
subj = regexp(Q.session,'(?<=group_[^/]+/)\d{8}_[^/]+','match','once');
Q.Subject = string(subj);

%% ---- stats --------------------------------------------------------------
nSess  = height(Q);
mn     = mean(Q.noise_frac, 'omitnan');
md     = median(Q.noise_frac, 'omitnan');
mx     = max(Q.noise_frac, [], 'omitnan');
nOver  = nnz(Q.noise_frac > 0.005);

% 上位セッション（表）
Q_top = sortrows(Q, 'noise_frac', 'descend');
Q_top = Q_top(:, {'session','noise_n','noise_frac','n_rows','fs','duration'});
Q_top = Q_top(1:min(TopN, height(Q_top)), :);

% 被験者別 最大値（棒グラフ）
S = groupsummary(Q, 'Subject', 'max', 'noise_frac');
S = sortrows(S, 'max_noise_frac', 'descend');
S = S(1:min(TopN, height(S)), :);

%% ---- figures (always generate PNG) -------------------------------------
png1 = fullfile(outdir, sprintf("qc_hist_noise_frac_%s.png", ts));
png2 = fullfile(outdir, sprintf("qc_bar_max_by_subject_%s.png", ts));

% 図1: ヒストグラム
f1 = figure('Color','w','Units','centimeters','Position',[1 1 20 14]);
ax1 = axes('Parent',f1);
histogram(ax1, Q.noise_frac, 30);
xlabel(ax1,'noise_frac'); ylabel(ax1,'Count');
title(ax1,'Distribution of noise fraction');
grid(ax1,'on');
try axtoolbar(ax1,'Visible','off'); catch, end % 旧版でも無視される
exportgraphics(f1, png1, 'Resolution', 200, 'BackgroundColor','white');

% 図2: 被験者別最大値
f2 = figure('Color','w','Units','centimeters','Position',[1 1 20 14]);
ax2 = axes('Parent',f2);
bar(ax2, S.max_noise_frac);
xt = S.Subject; % ラベルは日付だけに圧縮（視認性）
xt = regexprep(xt, '^(\d{8}).*', '$1');
set(ax2,'XTick',1:height(S),'XTickLabel',xt,'XTickLabelRotation',45);
ylabel(ax2,'max noise frac');
title(ax2, sprintf('Maximum noise fraction by Subject (Top %d)', height(S)));
grid(ax2,'on');
try axtoolbar(ax2,'Visible','off'); catch, end
exportgraphics(f2, png2, 'Resolution', 200, 'BackgroundColor','white');

close([f1 f2]);

%% ---- try Report Generator ----------------------------------------------
outpdf = fullfile(outdir, sprintf("qc_report_%s_%s.pdf", group, ts));

if args.UseReportGenerator
    try
        import mlreportgen.report.*
        import mlreportgen.dom.*

        rpt = Report(outpdf, 'pdf');

        % Title page
        tp = TitlePage;
        tp.Title  = sprintf('Quality Control Summary\n(Group: %s)', group);
        tp.Subtitle = 'fNIRS Project';
        tp.Author = char(string(datetime('now','Format','dd-MMM-yyyy','Locale','en_US')));
        add(rpt, tp);
        add(rpt, TableOfContents);

        % Chapter 1: Overview
        ch1 = Chapter('Overview');

        p = Paragraph(sprintf( ...
            ['Total sessions: %d\nMean noise_frac: %.4f\nMedian noise_frac: %.4f\n' ...
             'Max noise_frac: %.4f\nSessions with noise_frac > 0.005: %d'], ...
            nSess, mn, md, mx, nOver));
        p.WhiteSpace = 'preserve';
        add(ch1, p);

        % 画像を貼る
        add(ch1, Image(whichLocal(png1)));
        add(ch1, Image(whichLocal(png2)));
        add(rpt, ch1);

        % Chapter 2: Top sessions by noise_frac（表）
        ch2 = Chapter('1.2 Top sessions by noise\_frac');
        % 変数名を短く整形
        Tdisp = Q_top;
        Tdisp.Properties.VariableNames = {'session','noise_n','noise_frac','n_rows','fs','duration'};
        tbl = BaseTable(Tdisp);
        tbl.Title = 'Top sessions by noise\_frac';
        add(ch2, tbl);
        add(rpt, ch2);

        close(rpt);
        fprintf('✅ Report Generator で作成: %s\n', outpdf);
        outpath = outpdf;
        return;

    catch ME
        warning("Report Generator でのPDF作成に失敗: %s\n→ フォールバックで作成します。", ME.message);
        % 続いてフォールバックへ
    end
end

%% ---- fallback: PNGとCSVだけ残す & 簡易PDF(画像だけ) ---------------------
% 簡易PDF（Report Generator不要）: 画像をPDFにまとめたい場合は exportgraphics をPDFに向けて実行
try
    fp = figure('Color','w','Units','centimeters','Position',[1 1 20 14]);
    ax = axes('Parent',fp); axis(ax,'off');
    t = text(ax, 0.01, 0.95, sprintf('QC Summary (%s)', group), 'FontSize', 16, 'FontWeight','bold', 'Interpreter','none');
    text(ax, 0.01, 0.85, sprintf('Total sessions: %d', nSess), 'FontSize', 12);
    text(ax, 0.01, 0.80, sprintf('Mean noise\\_frac: %.4f', mn), 'FontSize', 12, 'Interpreter','tex');
    text(ax, 0.01, 0.75, sprintf('Median noise\\_frac: %.4f', md), 'FontSize', 12, 'Interpreter','tex');
    text(ax, 0.01, 0.70, sprintf('Max noise\\_frac: %.4f', mx), 'FontSize', 12, 'Interpreter','tex');
    text(ax, 0.01, 0.65, sprintf('Sessions with noise\\_frac > 0.005: %d', nOver), 'FontSize', 12, 'Interpreter','tex');
    exportgraphics(fp, outpdf, 'Resolution', 200, 'ContentType','vector');
    close(fp);

    % 画像も別ページとして追記
    appendImagePageToPDF(outpdf, png1);
    appendImagePageToPDF(outpdf, png2);

    fprintf('⚠️ Report Generator 無しフォールバックでPDF作成: %s\n', outpdf);
catch
    % PDF化が無理なら PNG だけ
    fprintf('⚠️ Report Generator 無しフォールバックでPNGのみ保存: %s, %s\n', png1, png2);
end

outpath = outpdf;

end % function

% ---- helpers -------------------------------------------------------------
function p = whichLocal(p)
% DOM Imageに渡すための実在フルパス
p = char(p); % DOMはchar推奨
end

function appendImagePageToPDF(pdffile, imgfile)
% シンプルに「画像→PDF1ページ」にして既存PDFへ結合
% 追加ページPDFを作る
tmpPdf = tempname + ".pdf";
fh = figure('Visible','off','Color','w','Units','centimeters','Position',[1 1 20 14]);
ax = axes('Parent',fh); axis(ax,'off');
I = imread(imgfile);
image(ax, I); axis(ax,'image','off');
exportgraphics(fh, tmpPdf, 'ContentType','vector');
close(fh);

% 結合（R2022a+ の append_pdfs が無い環境もあるため、簡易に外部に依存しない方法：
% MATLAB純正の "append" API は無いので、Report Generatorが無い場合は
% 1ページのPDFを順に結合できません。ここでは最初の表紙に続き、
% 画像PDFを「最後に置き換える」簡易策として makeshift で上書き結合を回避。
try
    import mlreportgen.dom.*
    d = Document(pdffile,'pdf');
    open(d); % 既存PDFは開けないため、ここに来たら失敗する
catch
    % 代替: 単純に最初のPDF（表紙）をそのまま、画像PDFは別ファイルとして残す
    [fp,fn] = fileparts(pdffile);
    copyfile(tmpPdf, fullfile(fp, fn + "_page_" + datestr(now,'HHMMSS') + ".pdf"));
end
if isfile(tmpPdf), delete(tmpPdf); end
end