# nirs-project  
**MATLAB-based fNIRS + HRV analysis pipeline (HOT-2000 / Hb133 / Check My Heart)**  
*Ver. 2026-1-11 – Kei Saruwatari*

---

## 📑 Table of Contents
- [📘 Overview 概要](#overview)
- [🧩 Folder structure ディレクトリ構成](#folder-structure)
- [⚙️ Main QC pipeline 主要QCパイプライン](#main-qc-pipeline)
- [🧠 Quality Control (Z-score Based)](#qc)
- [🚀 Quickstart](#quickstart)
- [🧠 Analysis flow 解析フロー概要](#analysis-flow)
- [🧠 Δ / ΔΔ Analysis (Task − Control, DT vs CT)](#delta-deltadelta)
- [🧠 Step D: Within-task Difficulty Manipulation (CT)](#step-d-ct)
- [🧩 Noise Correction and GLM Analysis｜ノイズ補正とGLM解析](#noise-glm)
- [🔬 References](#references)

---

## 📘 Overview 概要
<a id="overview"></a>

This repository provides a fully reproducible MATLAB pipeline for analyzing
functional near-infrared spectroscopy (fNIRS) and autonomic nervous system (HRV) data
collected during creative thinking tasks.

The primary focus is on prefrontal hemodynamic responses measured using:
	•	NeU HOT-2000 (HbT-only, SD1/SD3)
	•	Astem Hb133 (HbO/HbR/HbT)
	•	Check My Heart (pulse rate / HRV indices)

The pipeline emphasizes:
	•	transparent quality control (QC)
	•	minimal preprocessing assumptions
	•	reproducible Δ / ΔΔ task-contrast analyses
	•	conservative statistical interpretation suitable for pilot studies

---

## 🧩 Folder structure ディレクトリ構成
<a id="folder-structure"></a>

nirs-project/
├── scripts/
│   ├── analysis/          # Statistical analyses (ΔΔ, t-tests, plots)
│   ├── qc/                # Quality control metrics and filtering
│   ├── io/                # Data loading and stimulus reconstruction
│   ├── pipelines/         # Batch execution scripts
│   ├── plots/             # Visualization utilities
│   ├── hrv/               # HRV processing and synchronization
│   └── utils/             # Shared helper functions
│
├── data/                  # Experimental data (ignored by git)
│   ├── group_a/
│   ├── group_d/
│   └── merged/
│
├── reports/               # Exported figures and statistics
├── figures/               # Presentation-ready figures
└── .gitignore

⚠️ data/ is excluded from version control for privacy reasons.


## 🚀 Quickstart
<a id="quickstart"></a>

```matlab
addpath(genpath('scripts'));
rehash; clear functions;
```

Quality Control
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

## 🧠 Analysis Flow

| Step | Script / Module | Description (English) | 内容（日本語） |
|:--:|:--|:--|:--|
| **1** | `load_raw_hot2000.m` | Load HOT-2000 CSV files and structure time series | HOT-2000 の生 CSV ファイルを読み込み、時系列データとして構造化 |
| **2** | `BandPassFilter` | Apply band-pass filter (0.01–0.20 Hz) | 0.01–0.20 Hz の帯域通過フィルタを適用 |
| **3** | *(Hampel / PCA off)* | Skip aggressive denoising | 外れ値除去・PCA などの強い前処理は実施しない |
| **4** | `qc_hot2000_metrics.m` | Compute QC metrics | 信号品質・ノイズ指標などの QC メトリクスを算出 |
| **5** | `qc_classify_noise.m` | Automatic noise classification | QC 閾値に基づく自動ノイズ分類 |
| **6** | `qc_filter_keep_normal_signal.m` | Exclude outlier sessions | 外れ値セッションを除外し、正常信号のみ保持 |
| **7** | `run_make_deltas_from_manifest.m` | Compute Δ and ΔΔ values | Δ（Task−Baseline）および ΔΔ（Test−Control）を算出 |
| **8** | Statistical analysis scripts | Group-level statistical inference | 被験者内・群レベル統計解析（t検定・効果量） |
| **9** | `/reports/` | Export figures and statistics | 図表・統計結果を自動保存 |


## 🧠 Δ / ΔΔ Analysis (Core Outcome)
Definitions

Baseline was defined as the last 15 seconds of the Rest period immediately preceding each task,
to minimize carry-over effects and slow drift.

ΔHbT  = mean(Task) − mean(Rest_tail_15s)
ΔΔHbT = ΔHbT_test − ΔHbT_control

HbT was computed using short-separation regression:

HbT = HbT_SD3 − HbT_SD1

Left and right channels were processed separately and averaged when required.

Subject-level aggregation

For each subject:

ΔDT_subj = mean(ΔΔHbT_DT across repetitions)
ΔCT_subj = mean(ΔΔHbT_CT across repetitions)

Output:

data/merged/deltadelta_subject_mean.csv

Group-level comparison (DT vs CT)
	•	Test: paired t-test
	•	Effect size: Cohen’s dz

Results:
	•	t(25) = 0.928
	•	p = 0.362
	•	dz = 0.182 (small effect)

Scripts:

```matlab
run_DTvsCT_repMean_stats.m
run_DTvsCT_repMean_stats_boxplot.m
```

Outputs:

data/merged/group_stats_DT_CT.csv
data/merged/figures/DT_vs_CT_repMean.png

One-sample test vs baseline (ΔΔHbT vs 0)

To verify whether Task–Control contrasts deviated from baseline:
	•	Test: one-sample t-test
	•	Null hypothesis: mean ΔΔHbT = 0

Results:
	•	DT: t(25)=0.499, p=0.622, dz=0.098
	•	CT: t(25)=-0.413, p=0.683, dz=-0.081

Scripts:

```matlab
run_onesample_deltadelta_vs0.m
run_onesample_deltadelta_vs0_barSE.m
```

Outputs:

data/merged/onesample_deltadelta_vs0_stats.csv
data/merged/figures/onesample_deltadelta_vs0.png

## 🧠 Exploratory Laterality Analysis (Left / Right)

Laterality analyses were conducted exploratorily
and were not part of the primary hypothesis.
	•	Comparison: DT vs CT within Left (Fp1) and Right (Fp2)
	•	Test: paired t-test
	•	Effect size: Cohen’s dz

Results:
	•	Left: t(25)=0.977, p=0.338, dz=0.192
	•	Right: t(25)=0.707, p=0.486, dz=0.139

Script:

```matlab
run_DTvsCT_LeftRight_barSE_stats.m
```

These results are reported conservatively and interpreted as hypothesis-generating only.

## 🧠 Step D: Within-task Difficulty Manipulation (CT)

This analysis examines within-task cognitive load progression in CT.
	•	Trials 1–3: easier
	•	Trials 4–6: harder

Key result:
	•	t(25)=1.857, p=0.075, dz=0.364 (trend-level, medium effect)

Scripts:

```matlab
run_stepD_CT_rep6.m
```

Outputs include subject tables, statistics, and figures.

🔬 Design Philosophy
	•	Δ / ΔΔ framework defined a priori
	•	Minimal preprocessing (band-pass only)
	•	Clear separation between:
	•	confirmatory analyses
	•	exploratory analyses
	•	Effect sizes always reported
	•	Suitable for pilot-scale fNIRS studies

⸻

🔬 References
	•	Tachtsidis & Scholkmann (2016), Neurophotonics
	•	von Lühmann et al. (2020), Neurophotonics
	•	Virtanen et al. (2011), J. Biomed. Opt.
	•	Montgomery (2019), Introduction to Statistical Quality Control
	•	Bergmann et al. (2024), Bioengineering

⸻

✅ Summary

This repository provides a transparent, reproducible pipeline
from raw HOT-2000 CSV files to group-level hemodynamic statistics.

It is designed to support:
	•	pilot studies
	•	preregistered follow-up experiments
	•	integration with behavioral and HRV measures
