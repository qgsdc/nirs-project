# nirs-project
**MATLAB-based fNIRS + HRV analysis pipeline (HOT-2000 / Hb133 / Check My Heart)**  
**Version:** 2026-01-18  
**Author:** Kei Saruwatari

---

## Overview / 概要
本リポジトリは、創造性課題（DT/CT）中に取得した **fNIRS（前頭前野）** と **自律神経（HRV）** データを、
MATLABで **再現可能** に解析するためのパイプラインです。

対象機器：
- **NeU HOT-2000**（HbT、SD1/SD3）
- **Astem Hb133**（HbO/HbR/HbT）
- **Check My Heart**（心拍・HRV）

設計思想：
- QCは **透明で再現可能**（Zスコアに基づく）
- 前処理は **最小限**（原則 band-pass のみ）
- 主要アウトカムは **Δ / ΔΔ（Task−Control差）**
- 解析の自由度を抑えるため、主要解析と探索的解析を明確に区別する

---

## Folder structure / ディレクトリ構成
<a id="folder-structure"></a>

nirs-project/
├── scripts/                 # 解析スクリプト
│   ├── analysis/            # 統計・図（DT/CT, Step Dなど）
│   ├── qc/                  # QCメトリクス算出と除外
│   ├── io/                  # 読み込み・stim再構築
│   ├── pipelines/           # バッチ実行
│   ├── plots/               # 図の共通関数
│   ├── hrv/                 # HRV解析・同期
│   └── utils/               # 汎用ユーティリティ
│
├── data/ (ignored)          # 実験データ（個人情報保護のためgit管理外）
│   ├── group_a/
│   ├── group_d/
│   └── merged/
│       └── figures/         # 解析図・統計CSV（スライド用）
│
├── reports/                 # レポート出力（QCなど）
└── .gitignore

⚠️ data/ is excluded from version control for privacy reasons.


## 🚀 Quickstart
<a id="quickstart"></a>

---

```matlab
addpath(genpath('scripts'));
rehash; clear functions;
```
## 🧠 Analysis Flow

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

QCは Zスコア（±3） により外れ値セッションを除外する。

対象メトリクス：
	•	AccelRMS：体動（Virtanen et al., 2011）
	•	BandPowerSum（0.01–0.2 Hz）：異常振動（Montgomery, 2019）

run_qc_group("data/group_a");
run_qc_group("data/group_d");

qc_classify_noise("data/group_a/QC_hot2000_metrics.csv");
qc_classify_noise("data/group_d/QC_hot2000_metrics.csv");

qc_filter_keep_normal_signal("data/group_a/QC_hot2000_metrics_classified.csv");
qc_filter_keep_normal_signal("data/group_d/QC_hot2000_metrics_classified.csv");

make_stats_table_merged("data/group_a","data/group_d", ...
  'SaveTxt',true,'SaveCsv',true,'OutName','QC_merged');

  
実行：
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

Core outcome: Δ / ΔΔ Analysis (Task − Control, DT vs CT)

Definitions

Baseline（各Task直前のRest末尾15秒）：
	•	目的：carry-over と slow drift を最小化

定義：
	•	ΔHbT = mean(Task) − mean(Rest_tail15s)
	•	ΔΔHbT = ΔHbT_test − ΔHbT_control
	•	HOT-2000 HbT：HbT = SD3 − SD1（左右別→必要に応じて平均）

Subject-level aggregation（rep平均）：
	•	ΔDT_subj = mean(ΔΔHbT_DT across repetitions)
	•	ΔCT_subj = mean(ΔΔHbT_CT across repetitions)

出力：
	•	data/merged/deltadelta_subject_mean.csv

⸻

Group-level: DT vs CT（rep平均 → paired t-test）

実行：
```matlab
out = run_DTvsCT_repMean_stats_boxplot( ...
  "PairedCsv","data/merged/paired_deltadelta_312.csv", ...
  "OutDir","data/merged/figures", ...
  "ShowPoints",true);
```

結果（現データ）：
	•	paired t-test：t(25)=0.928, p=0.362
	•	effect size：Cohen’s dz=0.182（small）

⸻

One-sample: ΔΔHbT vs 0（baselineとの差の確認）

「Task−Control差（ΔΔHbT）が0から有意にズレるか」をDT/CTそれぞれで検定。

実行：
```matlab
out = run_onesample_deltadelta_vs0_barSE( ...
  "Csv","data/merged/deltadelta_subject_mean.csv", ...
  "OutDir","data/merged/figures");
```

結果（現データ）：
	•	DT：t(25)=0.499, p=0.622, dz=0.098
	•	CT：t(25)=-0.413, p=0.683, dz=-0.081

⸻

Exploratory: Laterality (Left / Right) — DT vs CT

左右別（Fp1/Fp2相当）の DT vs CT を探索的に確認。

実行：
```matlab
out = run_DTvsCT_LeftRight_barSE_stats( ...
  "PairedCsv","data/merged/paired_deltadelta_312.csv", ...
  "OutDir","data/merged/figures", ...
  "FigName","stepB_like_DTvsCT_LeftRight.png", ...
  "ShowPoints",true);
```

結果（現データ）：
	•	Left：t(25)=0.977, p=0.338, dz=0.192
	•	Right：t(25)=0.707, p=0.486, dz=0.139

※左右差は 探索的解析（hypothesis-generating） として報告する。

⸻

Step D: Within-task Difficulty Manipulation (CT)

CT内で難易度が上がるにつれて ΔΔHbT が変化するかを検討する（探索的）。

Difficulty ordering (Orita et al., 2018)

CT項目は先行研究の正答率に基づき易→難の順に配置：
	•	CT1: 69.7%
	•	CT2: 66.7%
	•	CT3: 60.6%
	•	CT4: 57.6%
	•	CT5: 51.5%
	•	CT6: 48.5%

⸻

Step D1: Trials 1–3 vs 4–6（前半 vs 後半）

実行：
```matlab
out = run_stepD1_CT_rep6_trials1to3_vs_4to6( ...
  "PairedRep6Csv","data/merged/paired_deltadelta_312_rep6.csv", ...
  "OutDir","data/merged/figures");
```

結果（現データ）：
	•	t(25)=1.857, p=0.075, dz=0.364

解釈：
	•	有意水準には達しないが 増加傾向
	•	効果量は 中程度（medium）
	•	パイロット研究としては「負荷上昇に反応する可能性」を示す探索的所見

Outputs：
	•	stepD1_CT_rep6_trials1to3_vs_4to6_deltadeltaLR.png
	•	stepD1_CT_rep6_trials1to3_vs_4to6_deltadeltaLR_stats.csv
	•	stepD1_CT_rep6_trials1to3_vs_4to6_deltadeltaLR_subject.csv

⸻

Step D2: CT score × ΔΔHbT（探索的相関）

実行：
```matlab
out = run_stepD2_CTscore_x_deltadelta_scatter( ...
  "MasterXlsx","data/master_subject_table_n26_202503.xlsx", ...
  "DeltaDeltaCsv","data/merged/deltadelta_subject_mean.csv", ...
  "OutDir","data/merged/figures");
```

結果（現データ）：
	•	Pearson r=0.11, p=0.591, N=26（有意な相関なし）

Outputs：
	•	stepD2_CTscore_x_deltadeltaLR_scatter.png
	•	stepD2_CTscore_x_deltadeltaLR_stats.csv
	•	stepD2_CTscore_x_deltadeltaLR_merged.csv

⸻

Noise correction & GLM (optional)

GLM解析は Δ/ΔΔ 解析と独立に実施可能。
（本READMEでは最小限の説明に留める）

⸻

References
	•	Virtanen et al. (2011) J. Biomed. Opt. (ABAMAR)
	•	Montgomery (2019) Introduction to Statistical Quality Control
	•	Bergmann et al. (2024) Bioengineering (review)
	•	Orita et al. (2018) (CT difficulty ordering)
