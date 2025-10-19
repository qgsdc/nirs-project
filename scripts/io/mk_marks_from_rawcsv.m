function mk_marks_from_rawcsv(sessdir)
% HOT-2000 生CSV（Headset time, Mark を含む）→ hotlog_marks.csv を作成

% 候補CSVを探索
cands = [dir(fullfile(sessdir,"HOTLog_*.csv")); dir(fullfile(sessdir,"*.csv"))];
if isempty(cands), error('RAW not found in %s', sessdir); end

% Headset time & Mark を含むCSVを選別
tOK = [];
for i=1:numel(cands)
    f = fullfile(cands(i).folder, cands(i).name);
    try
        opts = detectImportOptions(f,'TextType','string','Delimiter',',','CommentStyle','#');
        opts.VariableNamingRule = 'preserve';
        T = readtable(f, opts);
        v = lower(strrep(T.Properties.VariableNames,' ',''));
        if any(strcmp(v,'headsettime')) && any(strcmp(v,'mark'))
            tOK = f; break;
        end
    catch
    end
end
if isempty(tOK), error('No CSV with Headset time and Mark in %s', sessdir); end

% 読み込み（列名保持）
opts = detectImportOptions(tOK,'TextType','string','Delimiter',',','CommentStyle','#');
opts.VariableNamingRule = 'preserve';
T = readtable(tOK, opts);

vn = T.Properties.VariableNames;
idxTime = find(strcmpi(strrep(vn,' ',''),'headsettime'), 1);
idxMark = find(strcmpi(strrep(vn,' ',''),'mark'), 1);
if isempty(idxTime) || isempty(idxMark)
    error('Required columns not found in %s', tOK);
end

time = T{:,idxTime};
mark = string(T{:,idxMark});
m = lower(strtrim(mark));

% *_start/_end を結んで区間化
ev  = table(string.empty(0,1), zeros(0,1), zeros(0,1), ...
            'VariableNames',{'condition','onset','duration'});

blocks = unique(regexprep(m, '^.*?(rest|task[0-9]*|control[0-9]*|dt|ct).*$', '$1'));
blocks(blocks=="") = [];

for b = blocks'
    ib = ~cellfun(@isempty, regexp(m, "^"+b+"_(start|end)$", 'once'));
    if ~any(ib), continue; end
    Mb = m(ib); Tb = time(ib);
    [Tb,ord] = sort(Tb); Mb = Mb(ord);

    st = Tb(endsWith(Mb,"_start"));
    ed = Tb(endsWith(Mb,"_end"));
    n = min(numel(st), numel(ed));
    for k=1:n
        ev = [ev ; {b, st(k), max(ed(k)-st(k),0)}]; %#ok<AGROW>
    end
end

% 保存
fcsv = fullfile(sessdir,'hotlog_marks.csv');
writetable(ev, fcsv);
events = table(ev.condition, ev.onset, ev.duration, 'VariableNames',{'name','onset','duration'});
save(fullfile(sessdir,'stim.mat'), 'events');

fprintf('[MARKS] built from RAW -> %s\n', erase(fcsv, sessdir + filesep));
end