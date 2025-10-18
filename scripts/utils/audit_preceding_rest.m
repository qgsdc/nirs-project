function audit_preceding_rest(groupdir)
d = dir(groupdir);
isSubj = [d.isdir] & ~startsWith({d.name}, '.') ...
         & ~ismember({d.name},{'fig','logs','results_figs','qc_yamamoto_full'});
subj = string({d(isSubj).name});
pat = '(?i)^\s*rest(?:ing)?\s*\d*$'; % ← ゆるめのRest判定

for s = subj
    ss = dir(fullfile(groupdir,s,'*'));
    ss = ss([ss.isdir] & ~startsWith({ss.name},'.'));
    for k = 1:numel(ss)
        sessdir = fullfile(ss(k).folder, ss(k).name);
        try
            S = load(fullfile(sessdir,'stim.mat'));  % ← あなたのeventsの取得方法に合わせて
            events = S.events;                        % name/onset/duration を想定
            if isstruct(events), events=struct2table(events); end
            events.Properties.VariableNames = lower(events.Properties.VariableNames);
            names = string(events.name);
            names = regexprep(names,'\s+$',''); % 末尾空白除去
            isRest = ~cellfun(@isempty, regexpi(names, pat));
            restTbl = events(isRest,:);
            taskTbl = events(~isRest,:);

            miss = [];
            restEnd = restTbl.onset + restTbl.duration;
            for i = 1:height(taskTbl)
                t0 = taskTbl.onset(i);
                cand = find(restEnd <= t0 + eps); % 同時刻を許容
                if isempty(cand), miss(end+1)=i; end %#ok<AGROW>
            end
            if ~isempty(miss)
                fprintf('[MISS] %s/%s: %d task(s) no preceding Rest -> %s\n', ...
                    s, ss(k).name, numel(miss), strjoin(string(taskTbl.name(miss)),', '));
            end
        catch
            % セッションフォルダにcsv/matが無いケースなど
        end
    end
end
end