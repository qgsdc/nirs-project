function N = qc_hot2000_metrics(rootDir, varargin)
% HOT-2000 fNIRS QCメトリクス抽出（NeU CSV対応・除外強化版）
% 2025-10-18 str/char混在バグ修正

%% 入力
p = inputParser;
p.addRequired('rootDir', @(x)isfolder(x));
p.addParameter('Band',[0.01 0.2], @(x)isnumeric(x)&&numel(x)==2);
p.addParameter('MinRunSec',3,@isnumeric);
p.addParameter('ApplyNoiseMask',true,@islogical);
p.addParameter('SaveCSV',true,@islogical);
p.addParameter('Verbose',true,@islogical);
p.addParameter('UseReadNeUCSV',false,@islogical);
p.parse(rootDir,varargin{:});
opt = p.Results;

%% === ファイル列挙（除外フィルタ強化：すべて string に統一） ===
files = dir(fullfile(rootDir,'**','*.csv'));
% dotファイル除外
files = files(~startsWith({files.name},'.'));

% 最新のフルパス（string）を計算
fullpaths = string(fullfile({files.folder},{files.name}));

% 解析対象外トークン（全部string）
exclude_dir_tokens    = ["out_of_", filesep+"out_of_", "/out_of_", "motionreg"];
exclude_name_starts   = ["HOTLog_","glm"];
exclude_name_ends     = ["_glm.csv","_stim.csv"];
exclude_name_contains = ["betas","results","design"];

keep = true(numel(files),1);
for k = 1:numel(files)
    fp = fullpaths(k);           % string
    nm = string(files(k).name);  % string

    % ディレクトリ名で除外
    if any(contains(fp, exclude_dir_tokens, 'IgnoreCase', true))
        keep(k) = false; continue;
    end
    % ファイル名で除外（先頭/末尾/包含）
    if any(startsWith(nm, exclude_name_starts,   'IgnoreCase', true)) || ...
       any(endsWith(  nm, exclude_name_ends,     'IgnoreCase', true)) || ...
       any(contains(  nm, exclude_name_contains, 'IgnoreCase', true))
        keep(k) = false; continue;
    end
end
files = files(keep);

% （必要なら自然順ソート）
fullpaths = string(fullfile({files.folder},{files.name}));
[~,idx] = sort(lower(fullpaths));
files = files(idx);

% ←この直後に追加：自分が吐くQCファイルを除外
outFile = string(fullfile(rootDir, 'QC_hot2000_metrics.csv'));
keep = ~strcmpi(string(fullfile({files.folder},{files.name})), outFile);
files = files(keep);

if opt.Verbose
    fprintf('[QC] %d analysis CSV found under %s\n', numel(files), rootDir);
end

%% 出力テーブル
QC = table();

%% === メイン処理 ===
for i = 1:numel(files)
    f = fullfile(files(i).folder, files(i).name);
    if opt.Verbose
        fprintf('[QC] %d/%d : %s\n', i, numel(files), f);
    end

    try
        TT = local_read_neu_csv_as_timetable(f, opt.UseReadNeUCSV);
        if isempty(TT) || height(TT) < max(1,round(opt.MinRunSec*2))
            warning('[QC][SKIP] Too short or empty: %s', f);
            continue;
        end

        fs = estimate_fs(TT);
        if ~isfinite(fs) || fs<=0
            warning('[QC][SKIP] Invalid Fs: %s', f);
            continue;
        end

        % HbT列
        hbtCols = contains(TT.Properties.VariableNames, 'HbT', 'IgnoreCase', true);
        if ~any(hbtCols)
            warning('[QC][SKIP] No HbT columns: %s', f); 
            continue;
        end
        chans = TT(:, hbtCols);

        % 前処理
        Y   = detrend(table2array(chans));
        Ybp = bandpass(Y, opt.Band, fs);

        % 1行分
        row = table;
        row.File = string(f);
        row.Fs = fs;
        row.N = height(TT);
        row.DurationSec = row.N / fs;
        row.HasNoiseFlag = any(contains(TT.Properties.VariableNames,'Noise','IgnoreCase',true));
        row.MaskKeepRatio = 1;
        row.NumHbTChannels = width(Ybp);

        for c = 1:width(Ybp)
            vname  = chans.Properties.VariableNames{c};
            prefix = matlab.lang.makeValidName(vname);
            row.([prefix '__Mean'])    = mean(Ybp(:,c),'omitnan');
            row.([prefix '__Std'])     = std( Ybp(:,c),'omitnan');
            row.([prefix '__BandPow']) = sum(Ybp(:,c).^2,'omitnan')/numel(Ybp(:,c));
        end

        % 加速度/ジャイロRMS
        accCols = contains(TT.Properties.VariableNames, {'Accel','Accerelo','Gyro'}, 'IgnoreCase', true);
        if any(accCols)
            A = table2array(TT(:,accCols));
            row.AccelRMS = rms(A(:));
        else
            row.AccelRMS = NaN;
        end

        row.BandLow_Hz  = opt.Band(1);
        row.BandHigh_Hz = opt.Band(2);
        row.BandPowerSum = sum(sum(Ybp.^2)) / numel(Ybp);

        QC = [QC; row];

    catch ME
        warning('[QC][SKIP] %s -> %s', f, ME.message);
        continue;
    end
end

%% 保存
if opt.SaveCSV
    outFile = fullfile(rootDir, 'QC_hot2000_metrics.csv');
    writetable(QC, outFile);
    if opt.Verbose
        fprintf('[QC] Wrote %s (%d rows)\n', outFile, height(QC));
    end
end

N = height(QC);
end % main

%% ===== ローカル関数 =====
function TT = local_read_neu_csv_as_timetable(f, useReadNeU)
    if nargin < 2, useReadNeU = false; end

    if useReadNeU && exist('read_neu_csv','file')==2
        T = read_neu_csv(f);
        if istimetable(T)
            TT = T; return;
        elseif istable(T) && any(strcmpi(T.Properties.VariableNames,'Headset time'))
            ht = T.('Headset time');
            if iscell(ht), ht = str2double(string(ht)); end
            TT = table2timetable(T,'RowTimes',seconds(ht));
            return;
        end
    end

    lines = readlines(f);
    idx = find(contains(lines, 'Headset time', 'IgnoreCase', true), 1, 'first');
    if isempty(idx)
        error("Headset time 行が見つかりません: %s", f);
    end
    header = regexprep(string(lines(idx)), '^\s*#\s*', '');
    varnames = strtrim(split(header, ','));

    opts = detectImportOptions(f, 'FileType','text', 'Delimiter', ',');
    opts.VariableNames = matlab.lang.makeValidName(varnames);
    opts.DataLines = [idx+1 Inf];

    T = readtable(f, opts);

    hcol = find(contains(T.Properties.VariableNames,'Headset','IgnoreCase',true) & ...
                contains(T.Properties.VariableNames,'time','IgnoreCase',true), 1);
    ht = T{:,hcol};
    if iscell(ht), ht = str2double(string(ht)); end
    TT = table2timetable(T,'RowTimes',seconds(ht));
end

function fs = estimate_fs(TT)
    t  = seconds(TT.Time - TT.Time(1));
    dt = diff(t);
    dt = dt(isfinite(dt) & dt>0);
    fs = 1/median(dt);
end