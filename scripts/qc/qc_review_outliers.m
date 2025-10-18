function qc_review_outliers(qcfile, zth, savePng, maxN)
% qc_review_outliers
%   QC_hot2000_metrics.csv を読み、主要メトリクスのZスコアで外れ値候補を抽出。
%   オプションで、各外れ値セッションのタイムシリーズを描画（PNG保存可）。
%
% 使い方:
%   qc_review_outliers;                                % 既定: Z=3, PNG保存なし, 最大12本表示
%   qc_review_outliers(qcfile, 2.5, true, 15);         % パス明示, Z=2.5, PNG保存, 最大15本
%
% 依存:
%   - neu_quick_read_as_tt.m  (タイムテーブルでNeU CSVを読む軽量関数)
%
% 出力:
%   - QC_outliers_detected_from_recomputedZ.csv  （外れ値候補の一覧 + Z列）
%   - 保存ON時は、各セッションPNG（*_quickview.png）を同ディレクトリに吐き出し
%

    % -------------------- 引数既定 --------------------
    if nargin < 1 || isempty(qcfile)
        % カレント直下 or よく使う既定パスを試す
        guess = ["QC_hot2000_metrics.csv", ...
                 fullfile(pwd, "QC_hot2000_metrics.csv")];
        m = find(isfile(guess), 1);
        if ~isempty(m)
            qcfile = guess(m);
        else
            % 失敗したら例として group_d 配下を推測（任意で書き換えOK）
            qcfile = fullfile(fileparts(pwd), "data", "group_d", "QC_hot2000_metrics.csv");
        end
    end
    if nargin < 2 || isempty(zth),     zth     = 3;     end
    if nargin < 3 || isempty(savePng), savePng = false; end
    if nargin < 4 || isempty(maxN),    maxN    = 12;    end

    % 受け取った qcfile をそのまま使う（勝手に上書きしない）
    assert(isfile(qcfile), 'QCファイルが見つかりません: %s', qcfile);

    fprintf('[INFO] Loading: %s\n', qcfile);
    T = readtable(qcfile, 'TextType', 'string');

    % -------------------- 列名（stringで統一） --------------------
    vnames = string(T.Properties.VariableNames);

    % 解析に使うメトリクス（ベース名）を定義
    metricBase = ["BandPowerSum", "AccelRMS", ...
                  "HbTChange_leftSD1cm__Std", "HbTChange_rightSD1cm__Std"];

    % 実際の列名にマッチさせる（アンダースコア数の揺れ等を吸収）
    metricsResolved = resolveNames(metricBase, vnames);
    fprintf('[INFO] 外れ値判定に用いる列(解決名): %s\n', join(metricsResolved, ', '));

    % -------------------- Zスコア（再）計算 --------------------
    % 既存のZ_*があっても、選択した列については再計算して上書き
    for i = 1:numel(metricsResolved)
        col = metricsResolved(i);
        x   = double(T.(col));
        mu  = mean(x, 'omitnan');
        sd  = std(x,  'omitnan');
        z   = (x - mu) ./ sd;
        T.("Z_"+col) = z;
    end

    % Z列（stringで抽出）
    zvars = vnames(startsWith(vnames, "Z_"));
    % 再計算で増えたZ列を反映
    vnames2 = string(T.Properties.VariableNames);
    zvars   = union(zvars, vnames2(startsWith(vnames2,"Z_")));

    % -------------------- 外れ値判定 & 出力テーブル --------------------
    % 指定指標だけで判定（全Z列ではなく、metricsResolvedに対応するZ_*のみ）
    zvars_for_judge = "Z_" + metricsResolved;
    zvars_for_judge = zvars_for_judge(ismember(zvars_for_judge, vnames2));

    if isempty(zvars_for_judge)
        warning('判定対象のZ列が見つかりません。処理を終了します。');
        return;
    end

    Zjudge = abs(T{:, cellstr(zvars_for_judge)});
    isOut  = any(Zjudge >= zth, 2);

    % 欲しい列を string で作って存在チェック、最後に cellstr で抽出
    wantCols = ["File", metricsResolved, zvars_for_judge, zvars];  % 表示用に全Zも付ける
    wantCols = unique(wantCols, 'stable');
    wantCols = wantCols( ismember(wantCols, ["File", string(T.Properties.VariableNames)]) );

    % ★ ここが修正ポイント：列指定を cellstr に統一
    outTbl = T(isOut, cellstr(wantCols));

    % 指標別件数表示
    fprintf('\n--- 外れ値の指標別件数 (|Z|>=%g) ---\n', zth);
    for i = 1:numel(zvars_for_judge)
        zc = zvars_for_judge(i);
        cnt = sum(abs(T.(zc)) >= zth);
        fprintf('%-28s : %2d 件\n', char(zc), cnt);
    end

    % 書き出し
    outcsv = fullfile(fileparts(qcfile), 'QC_outliers_detected_from_recomputedZ.csv');
    writetable(outTbl, outcsv);
    fprintf('\n[QC] 外れ値リストを書き出しました: %s\n\n', outcsv);

    % -------------------- タイムシリーズのクイック確認 --------------------
    % 表示数制限
    files = string(outTbl.File);
    files = files(1:min(numel(files), maxN));

    for k = 1:numel(files)
        f = files(k);
        fprintf('[Plot] %s\n', f);

        try
            TT = neu_quick_read_as_tt(f);

            % 時間軸
            if ismember("Time", string(TT.Properties.VariableNames))
                t = TT.Time;
                if ~isduration(t)  % 念のため
                    t = seconds(double(t));
                end
            else
                % RowTimes が duration のはずだが保険で作成
                t = TT.Properties.RowTimes;
                if ~isduration(t)
                    t = seconds(double(t));
                end
            end

            % チャネル候補
            ch = ["HbTChange_leftSD1cm","HbTChange_leftSD3cm", ...
                  "HbTChange_rightSD1cm","HbTChange_rightSD3cm"];
            ch = ch(ismember(ch, string(TT.Properties.VariableNames)));

            if isempty(ch)
                warning('  可視化可能な HbTChange 系列が見つかりません。スキップ。');
                continue;
            end

            % 表示
            fig = figure('Name', char(f), 'Visible', tern(savePng,'off','on'));
            plot(t, TT{:, cellstr(ch)}, 'LineWidth', 1.0); grid on
            xlabel('Time (s)'); ylabel('\DeltaHbT');
            legend(cellstr(ch), 'Location', 'best');
            title(getShortTitleFromPath(f), 'Interpreter','none');

            % 保存
            if savePng
                png = fullfile(fileparts(f), replace(basename(f), ".csv", "_quickview.png"));
                try
                    exportgraphics(fig, png, 'Resolution', 150);
                catch
                    saveas(fig, png);
                end
                fprintf('  -> saved: %s\n', png);
                close(fig);
            end
        catch ME
            warning('時系列描画に失敗\n(%s):\n%s', f, ME.message);
        end
    end

    fprintf('\n[Done] Outlier review finished.\n');
end

% ======================================================================
% 補助：希望列名（ベース）を実在列名に寄せる（アンダースコア揺れ等を吸収）
function resolved = resolveNames(bases, vnames)
    % bases, vnames は string 前提
    resolved = strings(size(bases));
    for i = 1:numel(bases)
        b = bases(i);

        % 1) 完全一致があればそれ
        m = find(vnames == b, 1);
        if ~isempty(m)
            resolved(i) = vnames(m); continue;
        end

        % 2) アンダースコア連続/個数の揺れを削って比較
        b2 = erase(b, "_");
        m  = find(erase(vnames, "_") == b2, 1);
        if ~isempty(m)
            resolved(i) = vnames(m); continue;
        end

        % 3) 前方一致/部分一致の緩い一致（安全のため前方一致優先）
        m  = find(startsWith(vnames, b), 1);
        if ~isempty(m)
            resolved(i) = vnames(m); continue;
        end
        m  = find(contains(vnames, b), 1);
        if ~isempty(m)
            resolved(i) = vnames(m); continue;
        end

        % 4) 見つからなければベース名をそのまま（存在しない可能性あり）
        resolved(i) = b;
    end
end

% basename互換
function b = basename(fp)
    [~, b, ext] = fileparts(fp);
    b = b + ext;
end

% 図タイトル用の短縮名
function s = getShortTitleFromPath(fp)
    try
        parts = split(string(fp), filesep);
        if numel(parts) >= 2
            s = parts(end-1) + filesep + parts(end);
        else
            s = parts(end);
        end
    catch
        s = string(fp);
    end
end

% 三項（文字列制御用）
function out = tern(cond, a, b)
    if cond, out = a; else, out = b; end
end