function batch_make_stim(groupdir)
% 各セッションで、(1) {session}.csv から hotlog_marks.csv を作成し
% (2) mk_stim_from_hot2000_mark で stim.mat を作る
% HOTLog_*.csv は使用しない

d = dir(groupdir);
subs = string({d([d.isdir] & ~startsWith({d.name},'.')).name});

for s = subs
    ss = dir(fullfile(groupdir, s, '*'));
    ss = ss([ss.isdir] & ~startsWith({ss.name},'.'));
    for k = 1:numel(ss)
        sessdir = string(fullfile(ss(k).folder, ss(k).name));
        % 既に stim.mat があればスキップ
        if isfile(fullfile(sessdir,'stim.mat')), continue; end

        try
            % 1) セッション名CSV → hotlog_marks.csv
            if ~isfile(fullfile(sessdir,'hotlog_marks.csv'))
                mk_marks_from_sessioncsv(sessdir);
            end
            % 2) marks → stim.mat
            mk_stim_from_hot2000_mark(sessdir);
            fprintf('[STIM] ok -> %s\n', erase(sessdir, groupdir + "/"));

        catch ME
            warning('[STIM-MISS] %s : %s', erase(sessdir, groupdir + "/"), ME.message);
            % 続行（他セッションは処理）
        end
    end
end
end