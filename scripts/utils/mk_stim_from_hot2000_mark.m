function mk_stim_from_hot2000_mark(sessdir)
% mk_stim_from_hot2000_mark
% 入力:
%   sessdir/hotlog_marks.csv を読み、sessdir/stim.mat を作る
% サポート:
%   (A) HOT-2000生ログ: "Headset time" と "Mark" 列あり
%   (B) 既存イベント表: onset,duration,(condition|name) 列あり

markfile = fullfile(sessdir, 'hotlog_marks.csv');
if ~isfile(markfile)
    error('mk_stim: file not found: %s', markfile);
end

opts = detectImportOptions(markfile,'TextType','string','CommentStyle','#','Delimiter',',');
opts.VariableNamingRule = 'preserve';
T = readtable(markfile, opts);

% 正規化名
vn      = string(T.Properties.VariableNames);
vn_norm = lower(strrep(vn,' ',''));

% -------- 方式B: 既存イベント表を優先検出 --------
hasOnset = any(vn_norm=="onset");
hasDur   = any(vn_norm=="duration");
hasCond  = any(vn_norm=="condition") | any(vn_norm=="name");
if hasOnset && hasDur && hasCond
    % 列名を取得
    colOn  = vn( find(vn_norm=="onset",1,'first') );
    colDur = vn( find(vn_norm=="duration",1,'first') );
    condIdx = find(vn_norm=="condition" | vn_norm=="name", 1, 'first');
    colCond = vn(condIdx);

    onset    = T.(colOn);
    duration = T.(colDur);
    name     = T.(colCond);

    % 型チェック
    if ~isnumeric(onset) || ~isnumeric(duration)
        error('mk_stim: onset/duration must be numeric. File: %s', markfile);
    end
    if ~isstring(name) && ~iscellstr(name) && ~ischar(name)
        error('mk_stim: condition/name must be text. File: %s', markfile);
    end
    name = string(name);

    % events table を作成
    events = table(name, onset, duration);
    save(fullfile(sessdir,'stim.mat'), 'events');
    fprintf('[STIM] accepted ODC table -> %s\n', erase(markfile, sessdir+filesep));
    return
end

% -------- 方式A: 生ログ（Headset time / Mark）から生成 --------
% ※ Device time は無視。Headset time のみ使用。
idxHT = find(vn=="Headset time" | vn_norm=="headsettime" | vn_norm=="headset_time", 1, 'first');
if isempty(idxHT)
    error("mk_stim: 'Headset time' column not found.\nFile: %s\nAvailable: %s", ...
        markfile, strjoin(vn, ', '));
end
idxMark = find(vn=="Mark" | vn_norm=="mark", 1, 'first');
if isempty(idxMark)
    error("mk_stim: Mark column not found (need 'Mark'). File: %s", markfile);
end

t = T.(vn(idxHT));
if ~isnumeric(t)
    error("mk_stim: 'Headset time' must be numeric seconds. Got: %s", class(t));
end
mark = string(T.(vn(idxMark)));

% マーク文字列から rest/task の開始終了を抽出
% 期待例: rest_start/rest_end, task1_start/task1_end 等
pat = "(?i)^\s*([a-z0-9_]+)\s*_(start|end)\s*$";
m = regexp(mark, pat, 'tokens', 'once');

% 名前ごとに start/end をペアリング
S = struct;  % S.(cond).start_idx / end_idx
for i = 1:numel(m)
    tok = m{i};
    if isempty(tok), continue; end
    cond = lower(string(tok{1}));
    se   = lower(string(tok{2}));
    if ~isfield(S, cond), S.(cond) = struct('start_idx', [], 'end_idx', []); end
    if se=="start", S.(cond).start_idx(end+1) = i; else, S.(cond).end_idx(end+1) = i; end
end

% onset/duration を作成
name = strings(0,1); onset = []; duration = [];
conds = fieldnames(S);
for c = 1:numel(conds)
    cond = string(conds{c});
    si = S.(conds{c}).start_idx; ei = S.(conds{c}).end_idx;
    n = min(numel(si), numel(ei)); % ペア数
    for k = 1:n
        t0 = t(si(k));
        t1 = t(ei(k));
        if t1 <= t0, continue; end
        name(end+1,1) = cond; %#ok<AGROW>
        onset(end+1,1) = t0;   %#ok<AGROW>
        duration(end+1,1) = t1 - t0; %#ok<AGROW>
    end
end

if isempty(onset)
    error('mk_stim: no (start,end) pairs were found in Mark. File: %s', markfile);
end

% 時刻を 0 基準に
on0 = onset - min(onset);
events = table(name, on0, duration, 'VariableNames', {'name','onset','duration'});
save(fullfile(sessdir,'stim.mat'), 'events');
fprintf('[STIM] built from Headset time/Mark -> %s\n', erase(markfile, sessdir+filesep));
end