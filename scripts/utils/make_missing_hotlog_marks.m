function make_missing_hotlog_marks(groupdir)
% グループ内で hotlog_marks.csv が無いセッションだけ raw から作る
d = dir(groupdir);
subs = string({d([d.isdir] & ~startsWith({d.name},'.')).name});
for s = subs
    ss = dir(fullfile(groupdir,s,'*'));
    ss = ss([ss.isdir] & ~startsWith({ss.name},'.'));
    for k = 1:numel(ss)
        sessdir = string(fullfile(ss(k).folder, ss(k).name));
        if ~isfile(fullfile(sessdir,'hotlog_marks.csv'))
            try
                mk_marks_from_rawcsv(sessdir);
            catch ME
                warning('[MARKS] %s -> %s', erase(sessdir, groupdir + "/"), ME.message);
            end
        end
    end
end
end