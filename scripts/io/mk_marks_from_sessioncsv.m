function mk_marks_from_sessioncsv(sessdir)
% セッションフォルダ名と同名の CSV から "Headset time" と "Mark" を読み取り、
% hotlog_marks.csv（onset,duration,condition） と stim.mat を作成する
%
% 例:
%  sessdir = .../20250405_140034_dt_test1_uesugi
%  使うCSV = .../20250405_140034_dt_test1_uesugi/20250405_140034_dt_test1_uesugi.csv

% --- 対象CSVの決定（HOTLog_* は無視） ---
[pth, sessname] = fileparts(char(sessdir));
csvExact = fullfile(sessdir, sessname + ".csv");
if ~isfile(csvExact)
    warning('[MARKS] %s -> session-named CSV not found: %s', ...
            erase(sessdir, pth + filesep), csvExact);
    error('No session-named CSV');
end

% --- 読み込み（ヘッダは # でコメント扱い、列名はそのまま保持） ---
opts = detectImportOptions(csvExact,'TextType','string','Delimiter',',','CommentStyle','#');
opts.VariableNamingRule = 'preserve';
T = readtable(csvExact, opts);

% --- 列名の特定（Device time は使わない） ---
vn  = string(T.Properties.VariableNames);
vnl = lower(strrep(vn,' ',''));

idxTime = find(vnl == "headsettime", 1);
if isempty(idxTime)
    error('Time column "Headset time" not found in %s', csvExact);
end

% 「Mark」「marker」などの表記ゆれを許容（contains）
candMark = find(contains(vnl,"mark"));
candMark = candMark(candMark ~= idxTime);   % 念のため time と同一列を除外
if isempty(candMark)
    error('Mark column not found in %s', csvExact);
end
idxMark = candMark(1);

% --- イベント列生成 ---
timeSec = T{:, idxTime};
markRaw = string(T{:, idxMark});
m = lower(strtrim(markRaw));

% *_start/_end を区間に変換
ev  = table(string.empty(0,1), zeros(0,1), zeros(0,1), ...
            'VariableNames',{'condition','onset','duration'});

pat = "(rest|task[0-9]*|control[0-9]*|dt|ct)_(start|end)$";
isEvt = ~cellfun(@isempty, regexp(m, pat, 'once'));
Mm = m(isEvt);  Tm = timeSec(isEvt);
[Tm, ord] = sort(Tm);  Mm = Mm(ord);

labels = unique(regexprep(Mm,'_(start|end)$',''));
for lb = labels'
    st = Tm(Mm==lb+"_start");
    ed = Tm(Mm==lb+"_end");
    n  = min(numel(st), numel(ed));
    for k = 1:n
        ev = [ev ; {lb, st(k), max(ed(k)-st(k),0)}]; %#ok<AGROW>
    end
end

% --- 保存 ---
fcsv = fullfile(sessdir, 'hotlog_marks.csv');
writetable(ev, fcsv);

events = table(ev.condition, ev.onset, ev.duration, ...
               'VariableNames', {'name','onset','duration'});
save(fullfile(sessdir,'stim.mat'), 'events');

fprintf('[MARKS] built from session CSV -> %s\n', erase(fcsv, sessdir + filesep));
end