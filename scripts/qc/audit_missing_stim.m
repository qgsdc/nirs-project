function missing = audit_missing_stim(groupdir, varargin)
% AUDIT_MISSING_STIM  Return session paths missing stim.mat (CSVあり)
%   missing = audit_missing_stim(groupdir)
%   missing = audit_missing_stim(groupdir, 'IncludeSummary', true/false)
%
% 仕様:
%  - 再帰しない2階層想定:
%       groupdir/
%         YYYYMMDD_name/
%           <session_dir>/   % 例: 20250524_095948_dt_test2_tomonaga
%             <session_dir>.csv
%             stim.mat (あればOK)
%           <..._summary>/ はデフォルト除外
%
%  - デフォルトは summary を除外（末尾が "summary" または "_summary" を含むディレクトリ）

opts = struct('IncludeSummary', false);
if ~isempty(varargin)
    opts = parseopts(opts, varargin{:});
end

missing = strings(0,1);

lv1 = dir(groupdir);
lv1 = lv1([lv1.isdir]);
lv1 = lv1(~ismember({lv1.name},{'.','..'}));

for i = 1:numel(lv1)
    topdir = fullfile(groupdir, lv1(i).name);
    lv2 = dir(topdir);
    lv2 = lv2([lv2.isdir]);
    lv2 = lv2(~ismember({lv2.name},{'.','..'}));

    for j = 1:numel(lv2)
        sessname = lv2(j).name;
        sessdir  = fullfile(topdir, sessname);

        % summary系はデフォルト除外
        isSummary = endsWith(lower(sessname), "summary") || contains(lower(sessname), "_summary");
        if ~opts.IncludeSummary && isSummary
            continue
        end

        % 「<sessname>.csv」があるセッションのみ監査対象
        csvf = fullfile(sessdir, sessname + ".csv");
        if ~isfile(csvf)
            continue
        end

        % stim.mat が無ければ missing に追加（相対パスで）
        stimf = fullfile(sessdir, "stim.mat");
        if ~isfile(stimf)
            rel = string(fullfile(lv1(i).name, sessname));
            missing(end+1,1) = rel; %#ok<AGROW>
        end
    end
end

% 重複除去 & ソート
missing = unique(missing);
missing = missing(missing ~= "");
missing = sort(missing);

end

% ---- local helper ----
function out = parseopts(def, varargin)
out = def;
if mod(numel(varargin),2) ~= 0
    error('Name-Value の数が不正です');
end
for k = 1:2:numel(varargin)
    name = varargin{k};
    val  = varargin{k+1};
    if ~isfield(out, name)
        error('未知のオプション: %s', name);
    end
    out.(name) = val;
end
end