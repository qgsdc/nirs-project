function [idxBL, tBL] = get_baseline15s(t, events, task_onset, Fs, blSec)
% t: 時間ベクトル（秒）; events: table(name,onset,duration)
% task_onset: 当該Taskの開始時刻（秒）; Fs: サンプリング周波数; blSec: 15
% 出力: idxBL（logicalインデックス）, tBL（[t0 t1]）

% 直前Restを特定（終了時刻が task_onset 以下で最大のもの）
restTbl = events(regexpi(string(events.name),'^\s*rest(ing)?\s*\d*$', 'once')>0, :);
restEnd = restTbl.onset + restTbl.duration;
[restEndBefore, ix] = max(restEnd(restEnd <= task_onset + eps));
assert(~isempty(ix),'直前Restが見つかりません。');

% 末尾15秒ウィンドウ
t1 = restEndBefore;
t0 = max(t1 - blSec, restTbl.onset(ix));  % 念のためRest開始を跨がないよう制限
idxBL = (t >= t0) & (t <= t1);
tBL  = [t0 t1];
end