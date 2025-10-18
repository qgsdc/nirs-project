function [T, S] = read_neu_csv(csvf, varargin)
%READ_NEU_CSV  NeU (HOT-2000) CSV robust reader for fNIRS/HRV analysis
%   T = read_neu_csv(csvf, Name,Value,...)  returns raw table with cleaned headers.
%   [T,S] ... returns simplified table S (HbT etc.) ready for analysis.
%
% Name-Value options (all optional):
%   'Quiet'          (false) – true: suppress warnings
%   'DropSubtracted' (true)  – drop columns containing "subtracted"
%   'ApplyNoiseMask' (false) – mask rows where Noise flag ~= 0
%   'MaskTargets'    ('HbT') – 'HbT'|'all'|'none' (targets of noise mask)
%   'TimeColumn'     ('Headset') – 'Headset'|'Device' (analysis base; S.t stays Headset)
%   'Extract'        ('none') – 'HbT' to output S=(time_device,t,pulse,HbT_L,HbT_R,Mark)
%
% Header expectations (one example of NeU spec):
%   "# Device time", "Headset time", "Estimated pulse rate",
%   "HbT change(left SD1cm)","HbT change(left SD3cm)",
%   "HbT change(right SD1cm)","HbT change(right SD3cm)",
%   "Noise detection flag","Mark", ...

% ---- Parse inputs
ip = inputParser;
ip.addRequired('csvf', @(s)ischar(s) || isstring(s));
ip.addParameter('Quiet',          false,  @(b)islogical(b) || isnumeric(b));
ip.addParameter('DropSubtracted', true,   @(b)islogical(b) || isnumeric(b));
ip.addParameter('ApplyNoiseMask', false,  @(b)islogical(b) || isnumeric(b));
ip.addParameter('MaskTargets',    'HbT',  @(s)ischar(s) || isstring(s));
ip.addParameter('TimeColumn',     'Headset', @(s)ischar(s) || isstring(s));
ip.addParameter('Extract',        'none', @(s)ischar(s) || isstring(s));
ip.parse(csvf, varargin{:});

Quiet          = logical(ip.Results.Quiet);
DropSubtracted = logical(ip.Results.DropSubtracted);
ApplyNoiseMask = logical(ip.Results.ApplyNoiseMask);
MaskTargets    = lower(string(ip.Results.MaskTargets));
TimeColumn     = lower(string(ip.Results.TimeColumn));
Extract        = lower(string(ip.Results.Extract));

csvf = string(csvf);
if ~isfile(csvf)
    error("ファイルが見つかりません: %s", csvf);
end

% ---- Robust header line detection ("Headset time")
L = readlines(csvf);
if isempty(L)
    error("空ファイルです: %s", csvf);
end
tok = @(s) lower(strtrim(erase(erase(erase(s, char(65279)), char(8203)), '"'))); % BOM & ZWSP & quotes
hdr = [];
maxScan = min(200, numel(L)); % 先頭200行までで十分
for k = 1:maxScan
    line = tok(L(k));
    % コメント行 '# ...' でも残骸として含む場合があるので contains で検出
    if contains(line, "headset time")
        hdr = k;
        break;
    end
end
if isempty(hdr)
    error("NeU CSV: 'Headset time' 行が見つかりません: %s", csvf);
end

% ---- Read table with delimiter fallback & comment handling
T = table();
delims = {',', sprintf('\t')};
lastME = [];
for d = 1:numel(delims)
    try
        opts = detectImportOptions(csvf, ...
            'TextType','string', ...
            'Delimiter', delims{d}, ...
            'CommentStyle','#', ...
            'VariableNamingRule','preserve');
        opts.VariableNamesLine = hdr;
        opts.DataLines = [hdr+1, Inf];
        T = readtable(csvf, opts);
        if ~isempty(T), break; end
    catch ME
        lastME = ME; %#ok<NASGU>
        if d == numel(delims)
            rethrow(ME);
        end
    end
end
if isempty(T)
    error("readtableに失敗しました（区切り候補を試行しました）: %s", csvf);
end

% ---- Normalize variable names (strip BOM/ZWSP/quotes/spaces)
names = string(T.Properties.VariableNames);
names = regexprep(names, '[\x{FEFF}\x{200B}]', ''); % BOM/ZWSP
names = replace(names, '"', '');
names = strtrim(names);
T.Properties.VariableNames = cellstr(names);
names = string(T.Properties.VariableNames); % refresh
names_lc = lower(names);

% ---- Drop "subtracted" columns (recommended)
maskSub = contains(names_lc, "subtracted");
if any(maskSub)
    if DropSubtracted && ~Quiet
        warning("[NeU] subtracted列がありますが解析には使用しません:\n%s", csvf);
    elseif ~DropSubtracted && ~Quiet
        warning("[NeU] subtracted列が見つかりました（保持中）:\n%s", csvf);
        warning("[NeU] subtracted列は解析非推奨です（DropSubtracted=true を推奨）:\n%s", csvf);
    end
    if DropSubtracted
        T = T(:, ~maskSub);
        names = string(T.Properties.VariableNames);
        names_lc = lower(names);
    end
end

% ---- Helper accessors
starts = @(key) find(startsWith(names_lc, lower(string(key))), 1, 'first');
hascol = @(key) ~isempty(starts(key));
getcol = @(key) T.(names(starts(key)));

% ---- Required columns (soft check)
req = ["headset time","estimated pulse rate", ...
       "hbt change(left sd1cm)","hbt change(left sd3cm)", ...
       "hbt change(right sd1cm)","hbt change(right sd3cm)"];
missing = req(~arrayfun(hascol, req));
if ~isempty(missing) && ~Quiet
    warning("[NeU] 期待列が見つかりません: %s", strjoin(missing, ", "));
end

% ---- Time columns
% Headset time → numeric seconds (double)
if hascol("headset time")
    try
        t = double(getcol("headset time"));
    catch
        if ~Quiet, warning("[NeU] 'Headset time' を数値に変換できませんでした。"); end
        t = [];
    end
else
    error("必須列 'Headset time' が見つかりません。");
end

% Device time (several header variants could exist)
tdev = NaT(height(T),1);
devKeys = ["# device time","device time","#  device time"];
idk = find(arrayfun(hascol, devKeys), 1, 'first');
if ~isempty(idk)
    try
        dtxt = string(getcol(devKeys(idk)));
        % Typical: 2025/04/05 14:00:38.789
        tdev = datetime(dtxt, "InputFormat","yyyy/MM/dd HH:mm:ss.SSS", ...
                        "TimeZone","Asia/Tokyo", "Locale","ja_JP");
    catch
        if ~Quiet
            warning("[NeU] 'Device time' の日時パースに失敗（NaTのまま保持）: %s", csvf);
        end
    end
end

% ---- Optional noise mask
if ApplyNoiseMask
    candNoise = ["noise detection flag","noise flag","noisedetectionflag"];
    j = find(arrayfun(hascol, candNoise), 1, "first");
    if isempty(j)
        if ~Quiet, warning("[NeU] Noiseフラグ列が見つからないためマスクを適用しません: %s", csvf); end
    else
        noisev = double(getcol(candNoise(j)));
        bad = ~isnan(noisev) & (noisev ~= 0);
        if any(bad)
            switch MaskTargets
                case "none"
                    % no-op
                case "hbt"
                    hbtCols = contains(names_lc, "hbt change(");
                    T{bad, hbtCols} = NaN;
                otherwise % 'all'
                    T{bad, :} = NaN;
            end
        end
    end
end

% ---- Build S if requested / nargout
S = table();
if nargout > 1 || Extract == "hbt"
    % Mark normalization before use (VarN事故対策)
    iMark = find(names_lc=="mark" | contains(names_lc,"mark"), 1, 'first');
    if ~isempty(iMark)
        T.Properties.VariableNames{iMark} = 'Mark';
        names = string(T.Properties.VariableNames);
        names_lc = lower(names);
    end

    % Pull raw channels (may be missing)
    HbTL = NaN(height(T),1); HbTR = NaN(height(T),1);
    hasAllHb = all(ismember( ...
        ["hbt change(left sd1cm)","hbt change(left sd3cm)", ...
         "hbt change(right sd1cm)","hbt change(right sd3cm)"], names_lc));
    if hasAllHb
        L1 = double(getcol("hbt change(left sd1cm)"));
        L3 = double(getcol("hbt change(left sd3cm)"));
        R1 = double(getcol("hbt change(right sd1cm)"));
        R3 = double(getcol("hbt change(right sd3cm)"));

        % --- Finite guard: drop non-finite rows BEFORE computing HbT
        finiteMask = isfinite(L1) & isfinite(L3) & isfinite(R1) & isfinite(R3);
        if ~all(finiteMask)
            if ~Quiet
                warning("[NeU] 非有限を含む行を %d 件ドロップ: %s", sum(~finiteMask), csvf);
            end
            T  = T(finiteMask, :);
            t  = t(finiteMask, :);
            tdev = tdev(finiteMask, :);
            L1 = L1(finiteMask); L3 = L3(finiteMask);
            R1 = R1(finiteMask); R3 = R3(finiteMask);
            names = string(T.Properties.VariableNames);
            names_lc = lower(names);
        end
        HbTL = L3 - L1;
        HbTR = R3 - R1;
    else
        if ~Quiet
            warning("[NeU] HbT(SD3−SD1) の算出に必要な列が不足しています（HbTはNaNで出力）: %s", csvf);
        end
    end

    pulse = NaN(height(T),1);
    if hascol("estimated pulse rate")
        pulse = double(getcol("estimated pulse rate"));
    end

    Mark = strings(height(T),1);
    if any(names_lc=="mark")
        Mark = string(T.("Mark"));
    end

    % Assemble S
    S = table();
    S.time_device = tdev;  % 参照用
    S.t           = t;     % Headset秒基準
    S.pulse       = pulse;
    S.HbT_L       = HbTL;
    S.HbT_R       = HbTR;
    S.Mark        = Mark;

    % Enforce TimeColumn choice (S.t は Headset のまま、警告のみ)
    switch TimeColumn
        case "headset"
            % no-op
        case "device"
            if all(isnat(tdev)) && ~Quiet
                warning("TimeColumn='Device' ですが Device time が取得できません（Headset継続）。");
            end
        otherwise
            if ~Quiet
                warning("未対応 TimeColumn='%s'（Headset を使用）。", TimeColumn);
            end
    end

    if Extract ~= "hbt" && Extract ~= "none" && ~Quiet
        warning("Extract='%s' は未対応です。'HbT' か 'none' を指定してください。", Extract);
    end
end
end