function check_marks(csvf)
%CHECK_MARKS  NeU (HOT-2000) CSV の Mark 列を確認
%
%  check_marks(csvf)
%     指定CSVのMark列を読み込み、出現しているラベルとその件数を表示。
%     *_start / *_end のペア数も確認し、課題マーカーの整合性を簡易チェック。
%
%  使用例:
%     check_marks('/Users/.../20251012_iwamoto/20251012_133844_ct_test1_iwamoto.csv');

    if nargin < 1 || ~isfile(csvf)
        error('ファイルが見つかりません: %s', csvf);
    end

    % --- CSVを robust に読み込む（Header探索つき） ---
    L = readlines(csvf);
    hdr = find(contains(L, 'Headset time'), 1, 'first');
    if isempty(hdr)
        error("'Headset time' 行が見つかりません: %s", csvf);
    end

    opts = detectImportOptions(csvf, 'TextType','string', 'Delimiter',',');
    opts.VariableNamesLine = hdr;
    opts.DataLines = [hdr+1 Inf];
    opts.VariableNamingRule = 'preserve';
    T = readtable(csvf, opts);

    % --- Mark列の存在チェック ---
    names = lower(string(T.Properties.VariableNames));
    idxMark = find(startsWith(names, "mark"), 1);
    if isempty(idxMark)
        error("Mark列が見つかりません: %s", csvf);
    end
    mark = string(T{:, idxMark});

    % --- 欠損を除く ---
    mark = mark(~ismissing(mark) & strlength(mark) > 0);

    % --- 出現ラベルと件数を表示 ---
    if isempty(mark)
        fprintf("[INFO] Mark列に有効なラベルがありません。\n");
        return;
    end

    fprintf("\n=== %s ===\n", csvf);
    disp(unique(mark));
    Tmark = groupsummary(table(mark), "mark");
    disp(Tmark);

    % --- *_start / *_end ペア数をカウント ---
    labels = ["rest","task1","task2"];
    for lb = labels
        ns = sum(mark == lb+"_start");
        ne = sum(mark == lb+"_end");
        fprintf("%s: start=%d, end=%d\n", lb, ns, ne);
    end

    % --- 日本語表記のマークもチェック（NeU旧形式対策） ---
    jpMarks = mark(contains(mark, ["開始","終了"]));
    if ~isempty(jpMarks)
        disp("（日本語マーカーも検出されました）");
        disp(unique(jpMarks));
        Tjp = groupsummary(table(jpMarks), "jpMarks");
        disp(Tjp);
    end
end