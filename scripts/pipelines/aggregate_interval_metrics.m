function outCsv = aggregate_interval_metrics(groupdir, blSec)
if nargin<2, blSec=15; end
pat = sprintf('interval_metrics_BL%ds.csv', blSec);
rows = [];
D = dir(fullfile(groupdir,'*'));
D = D([D.isdir] & ~startsWith({D.name},'.'));
for i = 1:numel(D)
    subj = D(i).name;
    S = dir(fullfile(D(i).folder, subj, '*', 'interval_metrics', pat));
    for j = 1:numel(S)
        sessdir = fileparts(S(j).folder);           % …/session
        sess = string(split(sessdir, filesep)); sess = sess(end);
        T = readtable(fullfile(S(j).folder, S(j).name));
        T.subject = repmat(string(subj), height(T), 1);
        T.session = repmat(sess,         height(T), 1);
        rows = [rows; T]; %#ok<AGROW>
    end
end
G = rows(:,{'subject','session','block','signal','BLmean','TaskMean','CtrlMean','dTask','dCtrl','dDiff'});
outdir = fullfile(groupdir,'results_interval_metrics');
if ~exist(outdir,'dir'), mkdir(outdir); end
outCsv = fullfile(outdir, sprintf('group_interval_metrics_BL%ds.csv', blSec));
writetable(G,outCsv);
fprintf('[OK] aggregated -> %s (rows=%d)\n', outCsv, height(G));
end