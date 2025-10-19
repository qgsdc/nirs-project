# nirs-project / scripts README

このディレクトリは、役割ごとのサブフォルダに整理されています。  
**基本的な実行入口は `pipelines/`** 内のスクリプトです。

---

## フォルダ構成と主なスクリプト

### `io/`（入出力）
- `load_raw_hot2000.m` … HOT-2000 の CSV/TXT を読み込み。列名を自動検出し **HbT = SD3 − SD1** を生成、`Task1/Task2` を刺激に登録。
- `load_and_prepare_raw.m` / `load_and_create_raw.m` … 旧来の raw 生成ユーティリティ。
- `save_nirs.m` / `save_nirs_file.m` … NIRS オブジェクトの保存ユーティリティ。

### `preprocess/`（前処理）
- `preprocess_hot2000.m` … **ハイパス/ローパス/デスパイク(Hampel)/PCA**（Name-Value 指定可）。
- `baseline_correction.m` … ブロック前の基線を用いた補正。
- `baseline_correction_rest_average.m` … Rest 区間の平均で補正。
- `calc_Fs_from_time.m` … time ベクトルからサンプリング周波数を推定。

### `hrv/`（HRV & 同期）
- `hrv_from_rr.m` … RR(ms)1列テキストから **時間領域/周波数領域** 指標を一括算出（オプションで可視化/CSV）。
- `sync_hrv_nirs_markers.m` … HRV 側マーカーと NIRS 刺激の時刻合わせ（オフセット推定）。
- `sync_bpm_to_nirs_time.m` … 推定脈拍（BPM）系列を NIRS 時間軸へ補間・同期。
- `summarize_hrv_blocks.m` … Block 単位で HRV 指標を集計。

### `qc/`（品質確認）
- `qc_plot_channels_and_stims.m` … **左/右チャンネル**と `Task1/Task2` を背景シェードで可視化（区間と本数も表示）。
- `qc_hot2000_metrics.m` … 収録長・欠損率など軽い QC 指標を出力。

### `plots/`（図作成）
- `plot_hot2000_per_subject.m` / `plot_hot2000_per_subject_outdir.m` … 被験者単位の代表図を作成・保存。
- `make_group_table_and_plots.m` … グループ比較用テーブル作成＋代表図。

### `pipelines/`（解析パイプライン）
- `demo_run_glm_hot2000.m` / `demo_run_glm_hot2000_sep.m` / `demo_run_glm_hot2000_twofits.m`  
  最小構成の **GLM デモ**（単ファイル想定）。
- `run_hot2000_full_batch*.m`（`dt/ct` & `test/control`）  
  条件別の **バッチ処理**。前処理→GLM→出力まで。
- `run_sync_hrv_hot2000.m` … HRV と NIRS の同期〜併合。
- `run_glm*.m` / `run_hot2000_extract_beta.m` / `group_aggregate_and_stats_split.m` ほか  
  GLM 実行とベータ抽出、群集計・統計。

### `models/`（プローブ・座標）
- `setup_probe.m` … 2ch 仮想プローブ定義（必要に応じて拡張）。
- `load_okamoto_coords.m` … 岡本座標の読み込み（標準座標の参照用）。

### `utils/`（ユーティリティ）
- `organize_scripts.m` … このフォルダの**自動仕分け**スクリプト。
- `rename_subject_folders.m` / `update_link_distance.m` / `rebuild_stats1_missing.m`  
  メンテ小物。
- `startup_project.m` … プロジェクト用 startup（`scripts/` 配下にパスを通す）。

### `legacy/`（旧版・互換）
- `preprocess_nirs_manual.m` / `preprocess_nirs_hot2000.m` など旧フロー。新規解析では非推奨。

---

## クイックスタート（単被験者）

```matlab
% プロジェクト直下に居る前提
run('scripts/utils/startup_project.m');     % パスを通す

% 1) ファイルを読み込み（HbT = SD3−SD1、刺激 = task*_start）
csvf = '/path/to/HOT-2000.csv';
raw0 = load_raw_hot2000(csvf, 60, struct('apply_outlier',true,'apply_bandpass',false));

% 2) 前処理（HP/LP/Hampel/PCA）
raw_prep = preprocess_hot2000(raw0, ...
    'DETREND_HP',true,'HP_HZ',0.01, ...
    'LOWPASS',true,'LP_HZ',0.2, ...
    'DESPIKE',true,'HampelW',11,'HampelThr',3, ...
    'PCA',true,'PCA_NCOMP',0.8);

% 3) QC プロット
qc_plot_channels_and_stims(raw0,   'Before preprocess');
qc_plot_channels_and_stims(raw_prep,'After preprocess');

% 4) GLM（デモ）
res = nirs.modules.GLM().run(raw_prep);
disp(res.stats);
```

---

## 命名/運用のミニルール
- **ファイルは目的別のサブフォルダに置く**（`pipelines/` に実行入口、`io/` に入出力、…）。
- **新規スクリプトを追加したら README を更新**（1 行でも可）。
- **旧版は `legacy/` へ移動**（可能なら置き換え先をコメントで明記）。
- **プロジェクト開始時は `startup_project.m` を実行**（Path 問題を避ける）。

---

## 既知の前提
- nirs-toolbox が `nirs-project/nirs-toolbox/` にあり、`startup_project.m` で `genpath` 追加。
- HOT-2000 の列名は基本仕様に沿うが、`load_raw_hot2000.m` 側で軽い表記ゆれに耐性あり。

