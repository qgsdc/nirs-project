function plot_interval_metrics(groupdir, blSec)
if nargin<2, blSec=15; end
csv = fullfile(groupdir,'results_interval_metrics', ...
               sprintf('group_interval_metrics_BL%ds.csv', blSec));
T = readtable(csv);

sig = 'HbT_L'; % 例。'HbT_R','HbO_L' なども同様に回せる
TT = T(strcmp(T.signal,sig),:);

% 被験者×ブロックの散布（ΔTask, ΔCtrl, ΔΔ）
figure('Color','w'); tiledlayout(1,3,'Padding','compact','TileSpacing','compact');
nexttile; scatter(TT.block, TT.dTask, 'filled'); xlabel('Block'); ylabel('\Delta Task'); title([sig ' \DeltaTask']);
nexttile; scatter(TT.block, TT.dCtrl, 'filled'); xlabel('Block'); ylabel('\Delta Ctrl'); title([sig ' \DeltaCtrl']);
nexttile; scatter(TT.block, TT.dDiff, 'filled'); xlabel('Block'); ylabel('\Delta\Delta'); title([sig ' \Delta\Delta (Task-Ctrl)']);

outdir = fullfile(groupdir,'results_interval_metrics','figs');
if ~exist(outdir,'dir'), mkdir(outdir); end
saveas(gcf, fullfile(outdir, sprintf('scatter_%s_BL%ds.png', sig, blSec)));
fprintf('[FIG] %s\n', fullfile(outdir, sprintf('scatter_%s_BL%ds.png', sig, blSec)));
end