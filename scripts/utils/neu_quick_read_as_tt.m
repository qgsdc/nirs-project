function TT = neu_quick_read_as_tt(fpath)
% neu_quick_read_as_tt
%   HOT-2000 NeU CSV を timetable として素早く読むユーティリティ。
%   - "Headset time" を含むヘッダ行を自動特定
%   - detectImportOptions で可変長CSVに対応
%   - 列名の表記ゆれを正規化
%   - Time(秒) を数値列と RowTimes(duration) の両方で付与
%
% 返り値:
%   TT : timetable（RowTimes=duration 秒）

    arguments
        fpath (1,1) string
    end
    if ~isfile(fpath)
        error('neu_quick_read_as_tt:FileNotFound','ファイルが見つかりません: %s',fpath);
    end

    % 1) "Headset time" 行を探す
    lines = readlines(fpath);
    idx = find(contains(lines,"Headset time",'IgnoreCase',true),1,'first');
    if isempty(idx)
        error('neu_quick_read_as_tt:NoHeadsetHeader',...
              'Headset time を含むヘッダ行が見つかりません: %s',fpath);
    end

    % 2) 読み取りオプション
    %    detectImportOptions の Name-Value では指定せず、作成後にプロパティで設定
    opts = detectImportOptions(fpath, ...
        'NumHeaderLines', idx-1, ...
        'VariableNamesLine', idx, ...
        'Delimiter', ',', ...
        'TextType', 'string', ...
        'PreserveVariableNames', true, ...
        'ExtraColumnsRule', 'ignore', ...
        'EmptyLineRule', 'read');

    % DataLines は作成後にプロパティへ代入（←バージョン差で安全）
    try
        opts.DataLines = [idx+1, Inf];
    catch
        % 古いリリースだと DataLines が無いことがあるので黙ってスキップ
    end

    % 3) 読み込み
    T = readtable(fpath, opts);
    if height(T)==0
        error('neu_quick_read_as_tt:EmptyData','データ行が空です: %s',fpath);
    end

    % 4) 列名の正規化
    VNraw = string(T.Properties.VariableNames);
    VN = VNraw;
    VN = regexprep(VN,'\s+','');         % 空白除去
    VN = regexprep(VN,'[()\-\s]','_');   % ()- → _
    VN = regexprep(VN,'_+','_');         % 連続 _
    VN = regexprep(VN,'^_+|_+$','');     % 端の _
    VN = strrep(VN,'HbTchange','HbTChange');
    VN = strrep(VN,'saturation','Saturation');
    VN = strrep(VN,'Accerelo_','Accel'); % 加速度の揺れ
    VN = strrep(VN,'Accerelo','Accel');
    VN = strrep(VN,'Gyro_','Gyro');
    VN = strrep(VN,'Battery_Volt','BatteryVolt');
    VN = strrep(VN,'Battery_Remain','BatteryRemain');
    VN = string(matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(VN)));
    T.Properties.VariableNames = cellstr(VN);

    % 5) Headset time 列を特定（正規化前後どちらでも拾う）
    candRaw = ["Headset time","Headset_time","Headsettime"];
    headCol = "";
    for c = candRaw
        m = strcmpi(VNraw,c);
        if any(m)
            headCol = string(T.Properties.VariableNames{find(m,1)});
            break;
        end
    end
    if headCol==""
        m = find(contains(lower(T.Properties.VariableNames),"headset"),1);
        if ~isempty(m), headCol = string(T.Properties.VariableNames{m}); end
    end
    if headCol==""
        error('neu_quick_read_as_tt:NoHeadsetColumn','Headset time 列が見つかりません: %s',fpath);
    end

    % 6) 秒ベクトルを作成
    tvec = T.(headCol);
    if isstring(tvec) || ischar(tvec)
        tnum = str2double(tvec);
    else
        tnum = double(tvec);
    end
    if any(isnan(tnum))
        warning('[NeU] Headset time に NaN。線形補間します。');
        id = ~isnan(tnum);
        tnum(~id) = interp1(find(id), tnum(id), find(~id),'linear','extrap');
    end

    % 7) timetable 化（RowTimes: duration秒、数値列 Time も保持）
    if ~ismember("Time", string(T.Properties.VariableNames))
        T = addvars(T, tnum, 'Before', 1, 'NewVariableNames','Time');
    else
        T.Time = tnum;
    end
    TT = table2timetable(T,'RowTimes',seconds(tnum));
end