function out = mk_stim_from_session_csv(session_dir, varargin)
%MK_STIM_FROM_SESSION_CSV  セッションフォルダから stim.mat を生成（NaN安全 & フォールバック内蔵）

% ----- Parse inputs --------------------------------------------------------
ip = inputParser;
ip.addRequired('session_dir', @(s)ischar(s) || isstring(s));
ip.addParameter('Band',        [0.01 0.20], @(v)isnumeric(v) && numel(v)==2 && all(v>0));
ip.addParameter('Quiet',       false,       @(b)islogical(b) || isnumeric(b));
ip.addParameter('UseNoiseMask',false,       @(b)islogical(b) || isnumeric(b));
ip.addParameter('TimeColumn',  'Headset',   @(s)ischar(s) || isstring(s));
ip.addParameter('Save',        true,        @(b)islogical(b) || isnumeric(b));
ip.parse(session_dir, varargin{:});

band        = double(ip.Results.Band(:))';
Quiet       = logical(ip.Results.Quiet);
UseNoise    = logical(ip.Results.UseNoiseMask);
TimeColumn  = string(ip.Results.TimeColumn);
DoSave      = logical(ip.Results.Save);

session_dir = string(session_dir);
if ~isfolder(session_dir)
    error("mk_stim: セッションフォルダが見つかりません: %s", session_dir);
end

% ----- CSV 自動選択 -------------------------------------------------------
csvfile = i_pick_main_csv(session_dir);
if csvfile == ""
    error("mk_stim: セッション内にCSVが見つかりません（glmや派生物のみ？）: %s", session_dir);
end

% ----- 読み込み（NeUリーダ）＋ フォールバック再構成 ----------------------
[T, S] = read_neu_csv(csvfile, ...
    'Quiet', Quiet, ...
    'DropSubtracted', true, ...
    'ApplyNoiseMask', UseNoise, ...
    'MaskTargets', 'HbT', ...
    'TimeColumn', TimeColumn, ...
    'Extract', 'HbT');

if ~isstruct(S) || ~isfield(S,'t') || isempty(S.t)
    % ---- フォールバック: T から S を再構成 ----
    names    = string(T.Properties.VariableNames);
    names_lc = lower(names);
    getcol = @(key) T.(names(startsWith(names_lc, lower(key))));
    hascol = @(key) any(startsWith(names_lc, lower(key)));

    % t（Headset time）
    if hascol("headset time")
        try
            t = double(getcol("headset time"));
        catch
            t = [];
        end
    else
        t = [];
    end
    if isempty(t)
        error("mk_stim: 時間列 S.t が空で、Tからも再構成できません: %s", csvfile);
    end

    % HbT = SD3 - SD1
    L1 = []; L3 = []; R1 = []; R3 = [];
    if hascol("hbt change(left sd1cm)");  L1 = double(getcol("hbt change(left sd1cm)")); end
    if hascol("hbt change(left sd3cm)");  L3 = double(getcol("hbt change(left sd3cm)")); end
    if hascol("hbt change(right sd1cm)"); R1 = double(getcol("hbt change(right sd1cm)")); end
    if hascol("hbt change(right sd3cm)"); R3 = double(getcol("hbt change(right sd3cm)")); end
    if isempty(L1) || isempty(L3) || isempty(R1) || isempty(R3)
        error("mk_stim: HbT再構成に必要な列が不足: %s", csvfile);
    end
    HbTL = L3 - L1;
    HbTR = R3 - R1;

    % pulse & mark
    pulse = NaN(height(T),1);
    if hascol("estimated pulse rate"); pulse = double(getcol("estimated pulse rate")); end
    mark = strings(height(T),1);
    if hascol("mark"); mark = string(getcol("mark")); end

    % device time（任意）
    tdev = NaT(height(T),1);
    if hascol("# device time") || hascol("device time") || hascol("#  device time")
        try
            dtxt = string(getcol("# device time"));
            tdev = datetime(dtxt, "InputFormat","yyyy/MM/dd HH:mm:ss.SSS", ...
                            "TimeZone","Asia/Tokyo", "Locale","ja_JP");
        catch
            tdev = NaT(height(T),1);
        end
    end

    % S を構築
    S = table();
    S.time_device = tdev;
    S.t           = t;
    S.pulse       = pulse;
    S.HbT_L       = HbTL;
    S.HbT_R       = HbTR;
    S.Mark        = mark;
end

% ----- サンプリング周波数推定 --------------------------------------------
dt = median(diff(S.t), 'omitnan');
if ~isfinite(dt) || dt<=0
    error("mk_stim: S.t の刻みが不正（dt<=0またはNaN）: %s", csvfile);
end
Fs = 1/dt;

% ----- バンドパス（NaN安全） ---------------------------------------------
Wn = band * 2 / Fs;
if any(~isfinite(Wn)) || numel(Wn)~=2 || Wn(1)<=0 || Wn(2)>=1 || Wn(1)>=Wn(2)
    error("mk_stim: Band指定が不正です: Band=[%.4f %.4f], Fs=%.3f -> Wn=[%.4f %.4f]", ...
        band(1), band(2), Fs, Wn(1), Wn(2));
end
[b,a] = butter(2, Wn, 'bandpass');
[L_bp, R_bp] = i_filt_nan_safe(S.HbT_L, S.HbT_R, b, a, csvfile); %#ok<NASGU>

% ----- Mark ペア抽出 ------------------------------------------------------
% Table の列存在チェックは ismember/strcmpi を使う（isfield はNG）
hasMarkVar = any(strcmpi(S.Properties.VariableNames, 'Mark'));
if ~hasMarkVar
    error("mk_stim: Mark列が見つかりません: %s", csvfile);
end

% 全部 <missing> のケースも落とす
if all(ismissing(S.Mark))
    error("mk_stim: Mark列はありますが全て<missing>です: %s", csvfile);
end

labels = ["rest","task1","task2"];
pairs  = table(strings(0,1), zeros(0,1), zeros(0,1), ...
               'VariableNames',{'name','onset','dur'});

for lb = labels
    st = lb + "_start";
    en = lb + "_end";
    t_start = S.t( strcmp(string(S.Mark), st) );
    t_end   = S.t( strcmp(string(S.Mark), en) );

    if isempty(t_start) && isempty(t_end), continue; end
    if numel(t_start) ~= numel(t_end)
        error("mk_stim: %s の start/end の数が不一致です: start=%d, end=%d (%s)", ...
            lb, numel(t_start), numel(t_end), csvfile);
    end
    t_start = sort(t_start(:));
    t_end   = sort(t_end(:));
    if any(t_end <= t_start)
        error("mk_stim: %s で end<=start の区間があります（Mark順序異常）: %s", lb, csvfile);
    end
    tmp = table( repmat(lb,numel(t_start),1), t_start, t_end - t_start, ...
        'VariableNames',{'name','onset','dur'});
    pairs = [pairs; tmp]; %#ok<AGROW>
end

if isempty(pairs)
    error("mk_stim: Mark列はありますが *_start/_end の有効ペアが見つかりません: %s", csvfile);
end

% ----- 保存 & 出力 --------------------------------------------------------
stim = struct();
stim.onset   = pairs.onset;
stim.dur     = pairs.dur;
stim.name    = pairs.name;
stim.t0      = S.t(1);
stim.Fs      = Fs;
stim.band    = band;
stim.csvfile = csvfile;
stim.note    = "HbT(SD3−SD1), butter(2), filtfilt(ナンセーフ)";

out = struct();
out.csvfile   = csvfile;
out.stim_path = "";
out.N         = numel(stim.onset);
out.Fs        = Fs;
out.Band      = band;
out.labels    = i_label_summary(S);

if DoSave
    spath = fullfile(session_dir, "stim.mat");
    save(spath, 'stim');
    out.stim_path = spath;
end

% ------- ローカル関数群 ----------------------------------------------------
function csvf = i_pick_main_csv(sdir)
    cand = dir(fullfile(sdir, "*.csv"));
    if isempty(cand), csvf = ""; return; end
    % 除外（glm派生）
    cand = cand(~contains({cand.name}, "_glm.csv", 'IgnoreCase',true));
    cand = cand(~contains({cand.name}, "glm_results", 'IgnoreCase',true));
    cand = cand(~contains({cand.name}, "glm_betas",  'IgnoreCase',true));
    cand = cand(~strcmpi({cand.name}, "glm_betas_ALL_sessions.csv"));
    if isempty(cand), csvf = ""; return; end
    % セッション名優先
    [~, base] = fileparts(sdir);
    idx = find(startsWith({cand.name}, base), 1, 'first');
    if ~isempty(idx)
        csvf = string(fullfile(cand(idx).folder, cand(idx).name)); return;
    end
    % 更新日が新しいもの
    [~,iSort] = sort([cand.datenum], 'descend');
    csvf = string(fullfile(cand(iSort(1)).folder, cand(iSort(1)).name));
end

function [L_bp, R_bp] = i_filt_nan_safe(HbL, HbR, b, a, csvpath)
    L = double(HbL); R = double(HbR);
    if isempty(L) || isempty(R)
        error("mk_stim: HbT列が空です（L/R）: %s", csvpath);
    end
    mL = ~isfinite(L); mR = ~isfinite(R);
    if all(mL), error("mk_stim: HbT_L が全欠損でフィルタ不可: %s", csvpath); end
    if all(mR), error("mk_stim: HbT_R が全欠損でフィルタ不可: %s", csvpath); end
    % 欠損を一時補間（端点は最近傍）
    L2 = fillmissing(L,'linear','EndValues','nearest');
    R2 = fillmissing(R,'linear','EndValues','nearest');
    L_bp = filtfilt(b,a,L2);
    R_bp = filtfilt(b,a,R2);
    % 元欠損は復元
    L_bp(mL) = NaN; R_bp(mR) = NaN;
end

function L = i_label_summary(Sin)
    m = string(Sin.Mark); m = m(~ismissing(m));
    labs = ["rest","task1","task2"];
    L = struct();
    for lb = labs
        L.(lb+"_start") = sum(m==lb+"_start");
        L.(lb+"_end")   = sum(m==lb+"_end");
    end
end

end