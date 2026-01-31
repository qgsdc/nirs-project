# nirs-project
**MATLAB-based fNIRS + HRV analysis pipeline (HOT-2000 / Hb133 / Check My Heart)**  
**Version:** 2026-01-18  
**Author:** Kei Saruwatari

---

## Overview / 概要
本リポジトリは、創造性課題（Divergent Thinking: DT / Convergent Thinking: CT）中に取得した
fNIRS（前頭前野） および 自律神経（HRV） データを、
再現可能かつ保守的 に解析するための MATLAB パイプラインである。

対象機器：
	•	NeU HOT-2000（HbT、SD1/SD3）
	•	Astem Hb133（HbO / HbR / HbT）
	•	Check My Heart（心拍数・HRV）

設計思想：
	•	QC は Z スコア（±3σ）に基づく透明な基準
	•	前処理は 最小限（原則 band-pass のみ）
	•	主要アウトカムは Δ / ΔΔ（Task − Control 差）
	•	Primary（事前定義）解析 と Exploratory（探索的）解析 を明確に区別

---

## Folder structure / ディレクトリ構成
<a id="folder-structure"></a>

nirs-project/
├── scripts/                 # 解析スクリプト
│   ├── analysis/            # 統計解析・図（DT/CT, Step D）
│   ├── qc/                  # QCメトリクス算出・除外
│   ├── io/                  # 読み込み・stim再構築
│   ├── pipelines/           # バッチ実行
│   ├── plots/               # 図の共通関数
│   ├── hrv/                 # HRV解析・同期
│   └── utils/               # 汎用ユーティリティ
│
├── data/ (ignored)          # 実験データ（個人情報保護のため git 管理外）
│   ├── group_a/
│   ├── group_d/
│   └── merged/
│       └── figures/         # スライド用 図・統計CSV
│
├── reports/                 # QC 等のレポート出力
└── .gitignore

⚠️ data/ is excluded from version control for privacy reasons.


## 🚀 Quickstart
<a id="quickstart"></a>

```matlab
addpath(genpath('scripts'));
rehash; clear functions;
```

## 🧠 Analysis Flow (fNIRS Pre-processing)

## Phase 1: Basic Processing & Visual QC (基本処理と目視検品)
解析の土台作りと、人の目による波形チェックを行います。

### Step 1: Data Structuring (生データの統合)
HOT-2000から出力された生CSVを読み込み、解析用構造体へ変換します。

| ファイル名 | 役割 | 主な処理内容 |
|:---|:---|:---|
| `load_raw_hot2000_v2.m` | 読み込み関数 | ・$HbT = SD3 - SD1$ による皮膚血流除去（SD減算）<br>・心拍データ（Estimated pulse rate）の抽出 |
| `run_step1_load_and_save.m` | 実行スクリプト | ・全26名×12セッション（計312ファイル）を自動スキャン<br>・`raw_all_312_sessions.mat` として一括保存 |

### Step 2: Artifact Filtering (フィルタリング)
生理的ノイズ（呼吸・血圧変動等）を除去するための前処理を行います。

| ファイル名 | 役割 | 主な処理内容 |
|:---|:---|:---|
| `run_step2_apply_filter.m` | フィルタ適用 | ・Band-pass filter (0.01 - 0.20 Hz) の適用<br>・`filtered_all_312_sessions.mat` の作成 |

### Step 3: Visual Inspection (目視QC)
全データの波形を画像化し、品質を確認します。

| ファイル名 | 役割 | 主な処理内容 |
|:---|:---|:---|
| `run_save_all_plots.m` | プロット生成 | ・全312セッションの波形図をPNG出力<br>・出力先: `qc/plots/` |

## Phase 2: Quantitative Quality Control (数値指標による品質管理)

Step 2で前処理（フィルタリング）されたデータに対し、客観的な統計指標を用いてセッションごとの品質を評価します。

### Step 4: 指標算出 (`run_step4_compute_qc_metrics.m`)

全312セッションのデータをスキャンし、各チャンネルのノイズ混入率や信号強度を算出してCSVに集計します。

#### 算出される主要指標
| 指標 | 説明 |
| :--- | :--- |
| **NoiseFraction** | Z-scoreが ±3.0 を超える異常値の割合 |
| **Std_L / R** | 左右チャンネルの標準偏差（信号の安定性） |
| **PulsePower_L / R** | 心拍帯域 (0.5-2.0Hz) のパワー（プローブの接触品質） |

#### 実行方法
MATLABのコマンドウィンドウで以下を実行してください。実行するとファイル選択画面が開くので、`processed/step2/filtered_all_312_sessions.mat` を選択します。

```matlab
% script/step4 フォルダに移動して実行
cd('script/step4');
run_step4_compute_qc_metrics
```

### Step 5: 自動ノイズ判定 (`run_step5_classify_noise.m`)

Step 4で算出された指標に基づき、全データから統計的な外れ値（Z-score ±3.0）を抽出して「Bad」判定を行います。

#### 判定基準
以下の指標のいずれかで Z-score > 3.0 を記録したセッションを自動除外対象とします。
- **NoiseFraction**: 突発的なスパイクノイズの頻度
- **Std_L/R**: 異常な信号振幅（プローブの浮き等）
- **PulsePower_L/R**: 心拍成分の欠如（接触不良）

#### 実行方法
```matlab
% script/step5 フォルダに移動して実行
cd('script/step5');
run_step5_classify_noise
```
---

出力結果
processed/step4/qc_classification_results.csv: 各セッションの判定結果（Normal/Bad）と除外理由

qc/qc_scatter_plot/qc_scatter_plot.png: 判定結果を可視化した散布図

Note: 現在のデータセットでは 312 セッション中 19 セッション が除外対象として特定されています。

---

## 📂 データ構造の定義 (Data Hierarchy)

解析に使用する `.mat` ファイルは以下の階層構造を持ちます。

| レベル | 変数名 / フィールド | 内容 | 型・サイズ |
|:---|:---|:---|:---|
| 第1階層 | `raw_all` | **全体構造体** | ・全26名のデータを保持する構造体 |
| 第2階層 | `.[subject_id]` | **被験者ID** | ・個別被験者（例：`nakashima`）のフィールド |
| 第3階層 | `.[session_id]` | **セッションID** | ・各試行（例：`dt1, dt_ctrl1`）のデータ群 |
| 第4階層 | `.data` | **HbT 変化量** | ・[Time x 2] 行列 (1:左 / 2:右) |
| 第4階層 | `.pulse` | **心拍データ** | ・[Time x 1] 列ベクトル |
| 第4階層 | `.time` | **時間軸** | ・[Time x 1] 列ベクトル |
| 第4階層 | `.mark` | **マーカー** | ・[Time x 1] 列ベクトル |

#### セッション名のマッピング規則 (12 Sessions / Subject)

| 課題区分 | セッション名 | 内容 | 試行数 |
|:---|:---|:---|:---|
| **二重課題 (DT)** | `dt1, 2, 3` | 創造性課題（DT）実行中 | 3回 |
| | `dt_ctrl1, 2, 3` | DT対照条件（Control） | 3回 |
| **単一課題 (CT)** | `ct1, 2, 3` | 創造性課題（CT）実行中 | 3回 |
| | `ct_ctrl1, 2, 3` | CT対照条件（Control） | 3回 |

---


## ✅ Current Status
- **Last Updated:** 2026-01-31
- **Completion:** Step 1, 2, 3 完了
- **Records:** 全312セッションの処理済みデータおよびプロット（`qc/plots/`）の生成を確認。
	


| Step | Script / Module | Description (English) | 内容（日本語） |
|:---:|:----------------|:----------------------|:---------------|
| **1** | `load_raw_hot2000.m` | Load and structure raw HOT-2000 CSV files | HOT-2000の生CSVを読み込み、時系列構造を作成 |
| **2** | `BandPassFilter` | Apply band-pass filter (0.01–0.20 Hz) | 0.01–0.20 Hz 帯域通過フィルタでドリフト・生理ノイズ除去 |
| **3** | *(Hampel / PCA off)* | Skip aggressive denoising | 外れ値除去・PCAは実施せず（最小前処理） |
| **4** | `qc_hot2000_metrics.m` | Compute QC metrics | 加速度RMS・Band power等のQC指標を算出 |
| **5** | `qc_classify_noise.m` | Automatic noise classification | Z-score（±3σ）に基づくノイズ自動分類 |
| **6** | `qc_filter_keep_normal_signal.m` | Remove outlier sessions | 外れ値セッションを除外 |
| **7** | `make_stats_table_merged.m` | Merge groups and export QC stats | グループA/D統合とQC統計出力 |
| **8** | `build_stim_from_marks.m` | Reconstruct stimuli from Mark column | Mark列から刺激タイミングを再構成 |
| **9** | `run_make_deltas_from_manifest.m` | Compute Δ and ΔΔ values | ΔHbT・ΔΔHbTを算出（Task−Control） |
| **10** | `run_DTvsCT_repMean_stats.m` | DT vs CT comparison | DTとCTのΔΔHbTを被験者内比較 |
| **11** | `run_onesample_deltadelta_vs0.m` | One-sample test vs baseline | ΔΔHbTがbaselineから変化したか検定 |
| **12** | `run_DTvsCT_LeftRight_barSE_stats.m` | Exploratory laterality analysis | 左右別（Fp1/Fp2）の探索的比較 |
| **13** | `run_stepD1_CT_rep6_trials1to3_vs_4to6.m` | CT difficulty (early vs late) | CT前半 vs 後半（難易度操作）の比較 |
| **14** | `run_stepD2_CTscore_x_deltadelta_scatter.m` | CT score × ΔΔHbT correlation | CT成績とΔΔHbTの探索的相関解析 |
| **15** | `/reports/` | Export figures and statistics | 図・統計結果を自動保存 |

Quality Control (Z-score Based)

指標
	•	AccelRMS（体動）：Virtanen et al., 2011
	•	BandPowerSum（0.01–0.2 Hz）：Montgomery, 2019

基準
    •	QCは Zスコア（±3） により外れ値セッションを除外する。

```matlab
run_qc_group("data/group_a");
run_qc_group("data/group_d");

qc_classify_noise("data/group_a/QC_hot2000_metrics.csv");
qc_classify_noise("data/group_d/QC_hot2000_metrics.csv");

qc_filter_keep_normal_signal("data/group_a/QC_hot2000_metrics_classified.csv");
qc_filter_keep_normal_signal("data/group_d/QC_hot2000_metrics_classified.csv");

make_stats_table_merged("data/group_a","data/group_d", ...
  'SaveTxt',true,'SaveCsv',true,'OutName','QC_merged');
```

🧠 Core Outcome: Δ / ΔΔ Analysis（Primary）

Baseline
	•	各 Task 直前 Rest の末尾 15 秒

定義
	•	ΔHbT = mean(Task) − mean(Rest_tail15s)
	•	ΔΔHbT = ΔHbT_test − ΔHbT_control
	•	HbT = SD3 − SD1（左右別 → 必要に応じ平均）

Subject-level（rep平均）
	•	ΔDT_subj = mean(ΔΔHbT_DT)
	•	ΔCT_subj = mean(ΔΔHbT_CT)

出力：
data/merged/deltadelta_subject_mean.csv

DT vs CT（paired t-test）

```matlab
run_DTvsCT_repMean_stats_boxplot( ...
  "PairedCsv","data/merged/paired_deltadelta_312.csv", ...
  "OutDir","data/merged/figures", ...
  "ShowPoints",true);
```

結果
	•	t(25)=0.928, p=0.362
	•	Cohen’s dz = 0.182（small）

ΔΔ vs 0（one-sample）

```matlab
run_onesample_deltadelta_vs0_barSE( ...
  "Csv","data/merged/deltadelta_subject_mean.csv", ...
  "OutDir","data/merged/figures");
```

結果
	•	DT: t(25)=0.499, p=0.622
	•	CT: t(25)=-0.413, p=0.683

⸻

🧠 Exploratory Analyses

Laterality（Left / Right）

```matlab
run_DTvsCT_LeftRight_barSE_stats( ...
  "PairedCsv","data/merged/paired_deltadelta_312.csv", ...
  "OutDir","data/merged/figures", ...
  "FigName","stepB_like_DTvsCT_LeftRight.png", ...
  "ShowPoints",true);
```

	•	Left: t(25)=0.977, p=0.338
	•	Right: t(25)=0.707, p=0.486

※ 仮説生成的解析として報告。

⸻

🧠 Step D: Within-task Difficulty Manipulation (CT)

難易度順（Orita et al., 2018）
	•	CT1: 69.7%
	•	CT2: 66.7%
	•	CT3: 60.6%
	•	CT4: 57.6%
	•	CT5: 51.5%
	•	CT6: 48.5%

Step D1：前半 vs 後半

```matlab
run_stepD1_CT_rep6_trials1to3_vs_4to6( ...
  "PairedRep6Csv","data/merged/paired_deltadelta_312_rep6.csv", ...
  "OutDir","data/merged/figures");
```

	•	t(25)=1.857, p=0.075
	•	dz=0.364（medium, trend-level）

Step D2：CT score × ΔΔHbT

```matlab
run_stepD2_CTscore_x_deltadelta_scatter( ...
  "MasterXlsx","data/master_subject_table_n26_202503.xlsx", ...
  "DeltaDeltaCsv","data/merged/deltadelta_subject_mean.csv", ...
  "OutDir","data/merged/figures");
```

	•	r=0.11, p=0.591（ns）


---

## 🧠 CT score × WAIS (Core indices)
<a id="ct-wais"></a>

### Overview
CT成績（CT score）と WAIS の主要指標（FSIQ / VCI / PRI / WMI / PSI）の関連を、
Pearson の相関（two-tailed）で検討した（N=26）。

**重要：CT_score の定義（現データ仕様）**
本データの `ct_test1-3` は「CT1〜CT6の個別得点」ではなく、
**2問ずつまとめたブロック得点**を表す：

- `ct_test1` = CT1 + CT2  
- `ct_test2` = CT3 + CT4  
- `ct_test3` = CT5 + CT6  
- `CT_score` = `ct_test1 + ct_test2 + ct_test3`（最大 6 点）

※ 将来的に CT1〜CT6 を個別列として追記し、難易度別解析も拡張予定。

---

### Method
- Test: Pearson correlation (two-tailed)
- Multiple comparisons: Benjamini–Hochberg FDR（5指標）
- Effect size: r と r²（説明率）を併記
- 欠損は pairwise deletion（各相関で利用可能な被験者のみ）
- `include==1` の被験者のみを解析対象

---

### Reproducibility (script)

```matlab
out = run_CT_x_WAIS_core_indices( ...
  "MasterXlsx","data/master_subject_table_n26_202503.xlsx", ...
  "CTcol","CT_score_sum3", ...
  "WAIScols",["FSIQ","VCI","PRI","WMI","PSI"], ...
  "IncludeCol","include", ...
  "OutDir","data/merged/figures");
```

Results (current dataset)

| WAIS index | n | r | r² | p (two-tailed) | q (FDR) |
|-----------:|--:|---:|---:|--------------:|--------:|
| FSIQ | 26 | 0.439 | 0.19 | 0.024 | 0.061 |
| VCI  | 26 | 0.374 | 0.14 | 0.059 | 0.099 |
| PRI  | 26 | 0.327 | 0.11 | 0.102 | 0.128 |
| WMI  | 26 | 0.491 | 0.24 | 0.011 | 0.054 |
| PSI  | 26 | 0.061 | <0.01 | 0.767 | 0.767 |

Interpretation (for README / manuscript)
- FSIQ および WMI は CT score と中程度の正の相関を示した（r ≈ 0.44–0.49）。
- ただし 5 指標に対する多重比較補正（FDR）後は、FSIQ/WMI ともに q 値が 0.05 をわずかに上回り、
  統計的には trend-level / suggestive（補正後有意には達しないが、効果量と未補正 p 値を考慮すると
  将来の検証に値する可能性を示す）な関連と解釈される。
- VCI および PRI も正の相関方向を示したが、統計的優位性には達しなかった。
- PSI と CT score の間には有意な関連は認められなかった。
⸻

Outputs
	•	Figures (scatter):
	•	data/merged/figures/CT_x_WAIS_FSIQ_scatter.png
	•	data/merged/figures/CT_x_WAIS_VCI_scatter.png
	•	data/merged/figures/CT_x_WAIS_PRI_scatter.png
	•	data/merged/figures/CT_x_WAIS_WMI_scatter.png
	•	data/merged/figures/CT_x_WAIS_PSI_scatter.png
	•	Tables:
	•	data/merged/figures/CT_x_WAIS_correlations_core.csv
	•	data/merged/figures/CT_x_WAIS_merged.csv

### Notes
- 本解析は CT score（6 問合計）を用いた被験者間相関である。
- 今後、CT1–CT6 を個別列として追加し、
  難易度別（early vs late / item-wise）解析を実施予定である。
  
⸻

References
	•	Virtanen et al. (2011) J. Biomed. Opt.
	•	Montgomery (2019) Introduction to Statistical Quality Control
	•	Bergmann et al. (2024) Bioengineering
	•	Orita et al. (2018)

⸻

Summary

本リポジトリは、生データから
QC → Δ/ΔΔ → 群統計 → 探索的解析 までを
一貫して再現可能に実行できる解析基盤を提供する。

