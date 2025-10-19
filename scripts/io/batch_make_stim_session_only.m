function batch_make_stim_session_only(groupdir)
% ================================================================
% batch_make_stim_session_only(groupdir)
%   HOT-2000 セッション名CSVから stim.mat を一括生成
%   (HOTLog_ は無視し、Headset time + Mark 列を持つCSVを対象)
%
%   例:
%       batch_make_stim_session_only('/Users/.../data/group_a')
% ================================================================

fprintf('\n[STIM] Start creating stim.mat in %s\n', groupdir);

d = dir(groupdir);
isSub = [d.isdir] & ~startsWith({d.name},'.') & ~ismember({d.name},{'fig','logs','qc'});
subj = {d(isSub).name};

created = 0; skipped = 0; failed = 0;

for s = subj
    subjdir = fullfile(groupdir, s{1});
    ss = dir(fullfile(subjdir,'*'));
    ss = ss([ss.isdir] & ~startsWith({ss.name},'.'));

    for k = 1:numel(ss)
        sessdir = fullfile(ss(k).folder, ss(k).name);
        stimfile = fullfile(sessdir,'stim.mat');

        % 既に stim.mat がある場合はスキップ
        if isfile(stimfile)
            skipped = skipped + 1;
            continue;
        end

        % セッション名そのものと同名のCSVを探す
        [~,sessname] = fileparts(sessdir);
        csvcand = fullfile(sessdir, sessname + ".csv");

        if ~isfile(csvcand)
            fprintf('[STIM] skip: no session CSV -> %s\n', sessdir);
            failed = failed + 1;
            continue;
        end

        try
            % --- CSV読込オプション ---
            opts = detectImportOptions(csvcand, ...
                'Delimiter', ',', ...
                'TextType','string', ...
                'CommentStyle','#', ...
                'VariableNamingRule','preserve');

            T = readtable(csvcand, opts);
            vars = lower(strrep(T.Properties.VariableNames,' ',''));
            tcol = find(ismember(vars, {'headsettime','headset_time','time','sec','seconds'}),1);
            mcol = find(contains(vars,'mark','IgnoreCase',true),1);

            if isempty(tcol) || isempty(mcol)
                warning('[STIM] no Headset time or Mark column -> %s', csvcand);
                failed = failed + 1;
                continue;
            end

            t = T{:,tcol};
            m = string(T{:,mcol});

            % --- Mark解析 ---
            onset = [];
            dur   = [];
            name  = [];

            starts = find(contains(m,"start",'IgnoreCase',true));
            for i = 1:numel(starts)
                txt = m(starts(i));
                t0  = t(starts(i));

                % 対応するendを検索
                en = find(contains(m,"end",'IgnoreCase',true) & (1:numel(m))' > starts(i), 1);
                if isempty(en)
                    % 終了マークがない場合は既知タスク長を仮定（60s）
                    t1 = t0 + 60;
                else
                    t1 = t(en);
                end
                % 条件名（例: rest_start → rest）
                cond = regexprep(lower(txt), "_?start","");

                onset(end+1,1) = t0;
                dur(end+1,1)   = t1 - t0;
                name(end+1,1)  = cond;
            end

            events = table(name,onset,dur,'VariableNames',{'name','onset','duration'});
            save(stimfile,'events');
            fprintf('[STIM] created -> %s\n', erase(stimfile, groupdir));
            created = created + 1;

        catch ME
            warning('[STIM] failed (%s): %s', ME.identifier, csvcand);
            failed = failed + 1;
        end
    end
end

fprintf('\n[STIM] summary: created=%d, skipped=%d, failed=%d\n', created, skipped, failed);
end