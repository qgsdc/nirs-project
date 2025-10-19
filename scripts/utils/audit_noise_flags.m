function D = audit_noise_flags(rootdir, varargin)
%AUDIT_NOISE_FLAGS  NeU CSVのNoise detection flagを一括監査
%   D = audit_noise_flags(rootdir) は rootdir 配下のセッションCSVを走査し、
%   各ファイルのノイズ行数・割合・連続ノイズ(>=3s)の本数などを返します。
%
%   追加オプション:
%     'MinRunSec' (3)   連続ノイズとみなす最短秒数
%     'Verbose'   (false)
%
% 依存: read_neu_csv.m（scripts/utils）
ip = inputParser;
ip.addRequired('rootdir', @(s)ischar(s)||isstring(s));
ip.addParameter('MinRunSec', 3, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter('Verbose', false, @(b)islogical(b)||isnumeric(b));
ip.parse(rootdir, varargin{:});
minRunSec = ip.Results.MinRunSec;
verbose   = logical(ip.Results.Verbose);

rootdir = string(rootdir);
if ~isfolder(rootdir), error("フォルダがありません: %s", rootdir); end

% セッション直下パターン: <sess>/<sess>.csv を想定
csvfiles = dir(fullfile(rootdir, "**", "*.csv"));
csvfiles = csvfiles(~startsWith({csvfiles.name},'.'));  % 隠し除外

rows = [];
for k = 1:numel(csvfiles)
    csvf = string(fullfile(csvfiles(k).folder, csvfiles(k).name));
    % セッション直下の主CSVだけに限定（*_glm.csv などを除外）
    [p,base,~] = fileparts(csvf);
    isSessionMain = isfile(fullfile(p, base + ".mat")) || ... % 既にstimがある所も拾う
                    endsWith(p, base);                         % 一般的ケース: .../<sess>/<sess>.csv
    if ~isSessionMain, continue; end
    if endsWith(base, "_glm"), continue; end

    try
        % 読み: マスク適用はせず（実態把握のため）
        [T, S] = read_neu_csv(csvf, 'Quiet',true, 'DropSubtracted',true, ...
                              'ApplyNoiseMask',false, 'Extract','HbT');
        names = lower(string(T.Properties.VariableNames));
        cand  = ["noise detection flag","noise flag","noisedetectionflag"];
        idx   = find(ismember(names, cand), 1, 'first');
        if isempty(idx)
            nf = zeros(height(T),1);  % 列なし→0扱い
        else
            nf = double(T.(T.Properties.VariableNames{idx}));
        end
        nRows = height(T);
        bad   = ~isnan(nf) & nf~=0;
        nBad  = nnz(bad);
        pct   = 100*nBad/max(nRows,1);

        % サンプリングと連続ノイズ（>= minRunSec）
        Fs = NaN;
        if ~isempty(S) && numel(S.t)>=2
            dt = median(diff(double(S.t)), 'omitnan');
            if isfinite(dt) && dt>0, Fs = 1/dt; end
        end
        if ~isfinite(Fs) || Fs<=0, Fs = 10; end  % NeU標準想定

        minRunLen = max(1, round(minRunSec*Fs));
        nRuns = count_runs(bad, minRunLen);

        if verbose
            fprintf("[NOISE] %s  bad=%d/%d (%.1f%%), runs>=%.1fs: %d (Fs≈%.2f)\n", ...
                csvf, nBad, nRows, pct, minRunSec, nRuns, Fs);
        end

        rows = [rows; {csvf, nRows, nBad, pct, nRuns, Fs}]; %#ok<AGROW>
    catch ME
        if verbose
            fprintf("[SKIP] %s -> %s\n", csvf, ME.message);
        end
    end
end

if isempty(rows)
    D = table(string([]),[],[],[],[],[], 'VariableNames', ...
        {'file','nRows','nFlag','pctFlag','nRuns_geMinSec','Fs'});
else
    D = cell2table(rows, 'VariableNames', ...
        {'file','nRows','nFlag','pctFlag','nRuns_geMinSec','Fs'});
end

% 見やすさ用の並べ替え（ノイズ多い順）
if ~isempty(D)
    D = sortrows(D, {'pctFlag','nRuns_geMinSec'},{'descend','descend'});
end
end

% --- helper: true連続区間のうち、len>=minLen の本数を数える
function n = count_runs(logicalVec, minLen)
if ~islogical(logicalVec), logicalVec = logical(logicalVec); end
v = [false; logicalVec(:); false];
dv = diff(v);
runStarts = find(dv==1);
runEnds   = find(dv==-1)-1;
runLens   = runEnds - runStarts + 1;
n = nnz(runLens >= minLen);
end