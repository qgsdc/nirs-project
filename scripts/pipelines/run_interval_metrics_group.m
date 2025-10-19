function run_interval_metrics_group(groupdir, varargin)
p = inputParser;
addParameter(p,'BL',15);
parse(p,varargin{:});
blSec = p.Results.BL;

d = dir(groupdir);
isSubj = [d.isdir] & ~startsWith({d.name}, '.') ...
       & ~ismember({d.name},{'fig','logs','results_figs','qc_yamamoto_full'});
subjNames = string({d(isSubj).name});
fprintf('[INFO] subjects: %s\n', strjoin(subjNames, ', '));

for s = subjNames
    ss = dir(fullfile(groupdir, s, '*'));
    ss = ss([ss.isdir] & ~startsWith({ss.name},'.'));
    for k = 1:numel(ss)
        sessdir = fullfile(ss(k).folder, ss(k).name);
        try
            compute_interval_metrics(sessdir, 'BL', blSec);
        catch ME
            warning('[interval] %s/%s: %s', s, ss(k).name, ME.message);
        end
    end
end
end