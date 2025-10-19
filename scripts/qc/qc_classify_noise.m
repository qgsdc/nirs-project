function T = qc_classify_noise(qcfile, varargin)
% qc_classify_noise
%   HOT-2000 QC表 (CSV) を読み込み、BandPowerSum と AccelRMS の関係から
%   セッションを normal / signal_noise / motion_noise / mixed_noise に自動分類。
%   分類結果とロバストZを付加してCSV保存＆散布図を作成できます。
%
% 例:
%   T = qc_classify_noise(".../QC_hot2000_metrics.csv", ...
%         'ZBandThresh',3, 'ZAccelThresh',3, ...
%         'UseRobust',true, 'SaveCSV',true, 'SavePlot',true);

    % ---- 引数 ----
    p = inputParser;
    p.addRequired('qcfile', @(s)ischar(s) || isstring(s));
    p.addParameter('ZBandThresh', 3, @(x)isnumeric(x)&&isscalar(x)&&x>0);
    p.addParameter('ZAccelThresh',3, @(x)isnumeric(x)&&isscalar(x)&&x>0);
    p.addParameter('UseRobust', true, @(x)islogical(x)||ismember(x,[0 1]));
    p.addParameter('SaveCSV', true, @(x)islogical(x)||ismember(x,[0 1]));
    p.addParameter('SavePlot', true, @(x)islogical(x)||ismember(x,[0 1]));
    p.addParameter('MaxLabel', 15, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
    p.parse(qcfile, varargin{:});
    opt = p.Results;

    qcfile = string(qcfile);
    assert(isfile(qcfile), 'qc_classify_noise:FileNotFound', ...
        'QCファイルが見つかりません: %s', qcfile);

    fprintf('[INFO] Loading QC: %s\n', qcfile);
    T = readtable(qcfile);

    % 必須列チェック
    need = ["File","BandPowerSum","AccelRMS"];
    miss = need(~ismember(need, string(T.Properties.VariableNames)));
    assert(isempty(miss), 'qc_classify_noise:MissingVars', ...
        'QC表に必要な列がありません: %s', strjoin(miss, ', '));

    % ---- ロバストZの算出（median/MAD） ----
    function z = robustZ(x)
        x = double(x);
        m = median(x,'omitnan');
        madv = mad(x,1);                 % scale=1
        scale = madv * 1.4826;
        if scale==0 || ~isfinite(scale)
            s = std(x,'omitnan');
            if s==0 || ~isfinite(s), z = zeros(size(x)); return; end
            z = (x - m) ./ s;
        else
            z = (x - m) ./ scale;
        end
    end

    if opt.UseRobust
        zBand  = robustZ(T.BandPowerSum);
        zAccel = robustZ(T.AccelRMS);
    else
        zBand  = (T.BandPowerSum - mean(T.BandPowerSum,'omitnan')) ./ std(T.BandPowerSum,'omitnan');
        zAccel = (T.AccelRMS     - mean(T.AccelRMS,'omitnan'))     ./ std(T.AccelRMS,'omitnan');
    end

    T.Z_BandPowerSum = zBand;
    T.Z_AccelRMS     = zAccel;

    % ---- ルールで分類 ----
    zb  = abs(zBand);
    za  = abs(zAccel);
    thB = opt.ZBandThresh;
    thA = opt.ZAccelThresh;

    cls = strings(height(T),1); cls(:) = "normal";
    isSignal = (zb>=thB) & (za< thA);
    isMotion = (za>=thA) & (zb< thB);
    isMixed  = (za>=thA) & (zb>=thB);
    cls(isSignal) = "signal_noise";
    cls(isMotion) = "motion_noise";
    cls(isMixed)  = "mixed_noise";

    % 安定のため categorical に
    classesAll = {'normal','signal_noise','motion_noise','mixed_noise'};
    T.Class = categorical(cellstr(cls), classesAll);

    % 視覚用カラー (hex) を付与
    hexMap = containers.Map( ...
        classesAll, {'#2E7D32','#E65100','#1565C0','#8E24AA'}); % 緑,橙,青,紫
    classHex = strings(height(T),1);
    for i=1:height(T)
        key = char(string(T.Class(i)));
        if isKey(hexMap, key)
            classHex(i) = string(hexMap(key));
        else
            classHex(i) = "#757575";
        end
    end
    T.ClassColor = classHex;

    % ---- 概要表示 ----
    counts = groupsummary(T,'Class');
    disp('--- Class counts ---');
    disp(counts(:,{'Class','GroupCount'}));

    % ---- 保存（CSV） ----
    if opt.SaveCSV
        outcsv = fullfile(fileparts(qcfile), 'QC_hot2000_metrics_classified.csv');
        writetable(T, outcsv);
        fprintf('[SAVE] %s (rows=%d)\n', outcsv, height(T));
    end

    % ---- 散布図（保存） ----
    if opt.SavePlot
        f = figure('Color','w','Name','BandPower vs AccelRMS (classified)');
        hold on; grid on;
        ucls = categories(T.Class);
        lgd = strings(0,1);
        for k = 1:numel(ucls)
            cName = ucls{k};
            idx = (string(T.Class) == cName);
            if ~any(idx), continue; end
            rgb = hex2rgb(T.ClassColor(find(idx,1,'first')));
            scatter(double(T.AccelRMS(idx)), double(T.BandPowerSum(idx)), ...
                    36, 'filled', 'MarkerEdgeColor','k', 'MarkerFaceColor', rgb);
            lgd(end+1) = string(cName); %#ok<AGROW>
        end
        xlabel('AccelRMS'); ylabel('BandPowerSum');
        title(sprintf('BandPower vs AccelRMS (Zth: band=%.1f, accel=%.1f, robust=%d)', ...
            opt.ZBandThresh, opt.ZAccelThresh, opt.UseRobust));
        legend(lgd,'Location','bestoutside');
        xline(median(T.AccelRMS,'omitnan'), ':', 'Median Accel', 'LabelVerticalAlignment','bottom');
        yline(median(T.BandPowerSum,'omitnan'), ':', 'Median Band', 'LabelHorizontalAlignment','left');

        % ラベル（|Z| 上位）
        if opt.MaxLabel>0
            score = max(abs(T.Z_BandPowerSum), abs(T.Z_AccelRMS));
            [~,ord] = maxk(score, min(opt.MaxLabel, height(T)));
            text(double(T.AccelRMS(ord)), double(T.BandPowerSum(ord)), ...
                 string(T.File(ord)), 'FontSize',8, 'Interpreter','none', ...
                 'HorizontalAlignment','left', 'VerticalAlignment','bottom');
        end

        png = fullfile(fileparts(qcfile), 'QC_noise_scatter.png');
        exportgraphics(f, png, 'Resolution', 200);
        fprintf('[PLOT] %s\n', png);
        close(f);
    end
end

% ===== ローカル関数 =====
function rgb = hex2rgb(hex)
    % hex: "#RRGGBB" または "RRGGBB"
    hex = char(erase(string(hex), "#"));
    assert(numel(hex)==6, 'hex2rgb:BadHex','Invalid hex color: %s',hex);
    r = hex2dec(hex(1:2)); g = hex2dec(hex(3:4)); b = hex2dec(hex(5:6));
    rgb = [r g b] / 255;
end