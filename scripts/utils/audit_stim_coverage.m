function missing = audit_stim_coverage(groupdir)
d = dir(groupdir);
isSubj = [d.isdir] & ~startsWith({d.name},'.') ...
    & ~ismember({d.name},{'fig','logs','results_figs','qc_yamamoto_full'});
subj = string({d(isSubj).name});
missing = strings(0,1);
for s = subj
    ss = dir(fullfile(groupdir,s,'*'));
    ss = ss([ss.isdir] & ~startsWith({ss.name},'.'));
    for k = 1:numel(ss)
        sessdir = fullfile(ss(k).folder, ss(k).name);
        if ~exist(fullfile(sessdir,'stim.mat'),'file')
            warning('[STIM-MISS] %s/%s', s, ss(k).name);
            missing(end+1) = string(fullfile(s, ss(k).name)); %#ok<AGROW>
        end
    end
end
fprintf('[STIM] missing=%d\n', numel(missing));
end