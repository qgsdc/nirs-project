function S = read_hot2000_csv(csvfile, varargin)
% READ_HOT2000_CSV
%   専用パーサ：HOT-2000 仕様固定のCSVを読み込み
%   2: Headset time [s]
%   5: Estimated pulse rate (unused)
%   6–9: HbT change (left/right, SD1cm/SD3cm)
%   15: Mark (rest_start/end, task1_start/end, task2_start/end)
%
%   HbT(left/right) = SD3 - SD1
%   前処理: Band-pass 0.01–0.2 Hz (Hampel完全OFF)

% パラメータ（将来の拡張用だがデフォは仕様固定）
p = inputParser;
addParameter(p, 'Band', [0.01 0.20], @(x)isnumeric(x)&&numel(x)==2&&all(x>=0));
parse(p, varargin{:});
band = p.Results.Band;

% 読み込み（列名破損対策: preserve & 可変長にも耐える）
T = readtable(csvfile, 'VariableNamingRule','preserve');

% 最低限の列数チェック（15列想定）
if width(T) < 15
    error('read_hot2000_csv:BadFormat', ...
        '列数が不足しています（期待>=15, 実際=%d）: %s', width(T), csvfile);
end

% ---- 列マッピング ----
% 2: 時刻[s]
t = T{:,2};
if ~isnumeric(t); t = str2double(string(t)); end
% 欠損/NaN除去はここではせず、fs推定で整える

% 6–9: HbT change (left/right, SD1/SD3) → HbT = SD3 - SD1
% 想定: col6 = L_SD1, col7 = R_SD1, col8 = L_SD3, col9 = R_SD3
L_SD1 = T{:,6}; if ~isnumeric(L_SD1), L_SD1 = str2double(string(L_SD1)); end
R_SD1 = T{:,7}; if ~isnumeric(R_SD1), R_SD1 = str2double(string(R_SD1)); end
L_SD3 = T{:,8}; if ~isnumeric(L_SD3), L_SD3 = str2double(string(L_SD3)); end
R_SD3 = T{:,9}; if ~isnumeric(R_SD3), R_SD3 = str2double(string(R_SD3)); end

HbT_L = L_SD3 - L_SD1;
HbT_R = R_SD3 - R_SD1;

% 15: Mark（文字列想定）
MarkCol = T{:,15};
if ~iscellstr(MarkCol) && ~isstring(MarkCol)
    % 数値や空の場合にも備える
    Mark = string(MarkCol);
else
    Mark = string(MarkCol);
end
% 空文字は <missing> に寄せる
Mark = strtrim(Mark);
Mark(ismissing(Mark) | Mark=="") = string(missing);

% サンプリング周波数推定（timeは秒）
% 時刻が単調増加であることを前提に、中央部の差分中央値で頑健に推定
dt = diff(t);
dt = dt(isfinite(dt) & dt>0);
if isempty(dt)
    error('read_hot2000_csv:BadTime', '時刻列が不正です: %s', csvfile);
end
fs = 1/median(dt);

% ---- Band-pass 0.01–0.2 Hz ----
% Hampel完全OFF（=何もしない）
% フィルタは 4次Butterworth両方向（filtfilt）
[b,a] = butter(2, band/(fs/2), 'bandpass'); % 2nd x filtfilt ≒ 4th zero-phase
HbT_L_bp = filtfilt(b,a, HbT_L);
HbT_R_bp = filtfilt(b,a, HbT_R);

% 出力パック
S = struct();
S.t        = t(:);
S.fs       = fs;
S.HbT_L    = HbT_L(:);
S.HbT_R    = HbT_R(:);
S.HbT_L_bp = HbT_L_bp(:);
S.HbT_R_bp = HbT_R_bp(:);
S.Mark     = Mark(:);
S.info.csv = string(csvfile);
S.info.band= band;
S.info.note= "Hampel OFF; HbT=SD3−SD1 from cols 6–9; Mark at col 15";
end