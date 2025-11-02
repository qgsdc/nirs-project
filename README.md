# nirs-project  
**MATLAB-based fNIRS + HRV analysis pipeline (HOT-2000 / Hb133 / Check My Heart)**  
*Ver. 2025-10-19 – Kei Saruwatari*

---

## 📑 Table of Contents
- [📘 Overview 概要](#overview)
- [🧩 Folder structure ディレクトリ構成](#folder-structure)
- [⚙️ Main QC pipeline 主要QCパイプライン](#main-qc-pipeline)
- [🧠 Quality Control (Z-score Based)](#qc)
- [🚀 Quickstart](#quickstart)
- [🧠 Analysis flow 解析フロー概要](#analysis-flow)
- [🧩 Noise Correction and GLM Analysis｜ノイズ補正とGLM解析](#noise-glm)
- [🔬 References](#references)

---

## 📘 Overview 概要
<a id="overview"></a>

このリポジトリは、**NeU社 HOT-2000 / Astem社 Hb133** を用いた  
fNIRS信号と心拍変動（HRV）データの解析をMATLAB上で自動化するプロジェクトです。  

主な目的は、創造性課題中の**前頭前野活動（HbT/HbO/HbR）**および  
**自律神経反応（推定脈拍・HRV指標）**を統合的に解析することです。

---

## 🧩 Folder structure ディレクトリ構成
<a id="folder-structure"></a>

- nirs-project/
+ ```text
+ nirs-project/
   ├── scripts/               # 解析スクリプト類
   │   ├── qc/                # 品質管理（QC）関数
   │   ├── io/                # データ入出力補助
   │   ├── pipelines/         # 一括実行パイプライン
   │   ├── plots/             # 可視化ツール
   │   ├── hrv/               # HRV解析・同期
   │   └── utils/             # 共通ユーティリティ
   │
   ├── data/ (ignored)        # 実験データ（git管理外）
   │   ├── group_a/           # グループA被験者
   │   ├── group_d/           # グループD被験者
   │   └── merged/            # 両群統合サマリー
   │
   ├── reports/               # 出力図・統計レポート
   │
   └── .gitignore             # data/ などを除外
+ ```

## ⚙️ Main QC pipeline 主要QCパイプライン
<a id="main-qc-pipeline"></a>

```matlab
% 1️⃣ 個別セッションQC
run_qc_group("data/group_a");
run_qc_group("data/group_d");

% 2️⃣ ノイズ分類（自動）
qc_classify_noise("data/group_a/QC_hot2000_metrics.csv");
qc_classify_noise("data/group_d/QC_hot2000_metrics.csv");

% 3️⃣ 外れ値除去とフィルタ済み保存
qc_filter_keep_normal_signal("data/group_a/QC_hot2000_metrics_classified.csv");
qc_filter_keep_normal_signal("data/group_d/QC_hot2000_metrics_classified.csv");

% 4️⃣ 両群統合と統計出力
make_stats_table_merged("data/group_a","data/group_d", ...
    'SaveTxt',true,'SaveCsv',true,'OutName','QC_merged');
```
## 🧠 Quality Control (Z-score Based Filtering)
<a id="qc"></a>

### Overview
To ensure data reliability, a Z-score–based QC step was applied to remove sessions with excessive motion or physiological artifacts.

| Metric | Description | Basis | Threshold (|Z| ≥) | Exclusion Type |
|:-------|:-------------|:-------|:-------------:|:----------------|
| **AccelRMS** | Root mean square of accelerometer signals | Motion artifacts (Virtanen et al., *J. Biomed. Opt.*, 2011) | **3.0** | Motion-related outlier |
| **BandPowerSum** | Total band power (0.01–0.2 Hz) of HbT signal | Physiological noise / abnormal oscillation (Montgomery, 2019 ±3σ rule) | **3.0** | Physiological outlier |

Sessions were flagged if either metric exceeded ±3 SD in group-level Z-scores.

### Reference Justification
- **Virtanen et al. (2011)** — Introduced the ABAMAR method; accelerometer-based detection reached *~79% human-level accuracy*.  
- **Montgomery (2019)** — Introduced the *±3σ rule* as a general outlier criterion.  
- **Bergmann et al. (2024)** — Systematic review confirming wavelet and hybrid (spline + SG + wavelet) methods as core strategies for NIRS artifact suppression.

### QC Results Summary

| Group | Total Sessions | Retained | Excluded (Z≥3) | Exclusion Rate |
|:------|:----------------|:----------|:----------------|:----------------:|
| **Group A** | 120 | 117 | 3 | 2.5 % |
| **Group D** | 108 | 104 | 4 | 3.7 % |
| **Total** | 228 | 221 | 7 | **3.1 %** |

### Output Files
- data/
+ ```text
+ data/
 ├── group_a/qc/
 │   ├── QC_hot2000_metrics_classified.csv
 │   ├── QC_hot2000_metrics_withZ.csv
 │   ├── QC_hot2000_metrics_filtered.csv
 │   └── QC_outliers_rows_currentZ.csv
 ├── group_d/qc/ (same structure)
 └── merged/
-├── QC_merged_Zthr3_stats_byGroup.csv
-├── QC_merged_Zthr3_stats_byTaskCond.csv
-└── QC_merged_Zthr3_summary.txt
+   ├── QC_merged_Zthr3_stats_byGroup.csv
+   ├── QC_merged_Zthr3_stats_byTaskCond.csv
+   └── QC_merged_Zthr3_summary.txt
+ ```

### Interpretation
- Outlier detection is purely **distributional (±3σ)**, ensuring reproducibility.
- No additional filtering (e.g., wavelet, PCA) is applied—only band-pass (0.01–0.2 Hz).
- All removed sessions remain archived for transparency.

---

✅ *These QC steps form the foundation for subsequent GLM analysis using filtered datasets.*

## 🚀 Quickstart
<a id="quickstart"></a>

1. Add paths in MATLAB:
```matlab
addpath(genpath('scripts'));
rehash; clear functions;
```

2.	Run QC for each group:
```matlab
run_qc_group("data/group_a");
run_qc_group("data/group_d");
```

3.	Classify noise:
```matlab
qc_classify_noise("data/group_a/QC_hot2000_metrics.csv");
qc_classify_noise("data/group_d/QC_hot2000_metrics.csv");
```

4.	Filter outliers:
```matlab
qc_filter_keep_normal_signal("data/group_a/QC_hot2000_metrics_classified.csv");
qc_filter_keep_normal_signal("data/group_d/QC_hot2000_metrics_classified.csv");
```

5.	Merge & export stats:
```matlab
make_stats_table_merged("data/group_a","data/group_d", ...
'SaveTxt',true,'SaveCsv',true,'OutName','QC_merged');
```
6.	(Optional) GLM per session:
```matlab
run_glm_each_session("data/group_a/participants");
run_glm_each_session("data/group_d/participants");
```

### 🧠 Analysis flow 解析フロー概要
<a id="analysis-flow"></a>  

| 🧩 Step | ⚙️ Function | ✳️ Description (English) | 📝 内容（日本語） |
|:--:|:--|:--|:--|
| **1** | `load_raw_hot2000.m` | Load raw HOT-2000 CSV files | HOT-2000の生CSVファイルを読み込み |
| **2** | `BandPassFilter` | Band-pass 0.01–0.20 Hz to remove physiological noise | 0.01–0.20 Hzの帯域通過フィルタで生理ノイズ除去 |
| **3** | *(Hampel off / PCA off)* | Skip outlier and component removal | 外れ値除去・主成分除去は無効化 |
| **4** | `qc_hot2000_metrics.m` | Compute QC metrics (signal quality, noise ratio, etc.) | 信号品質・ノイズ比などのQCメトリクスを算出 |
| **5** | `qc_classify_noise.m` | Classify noise automatically based on QC thresholds | QC閾値に基づき自動ノイズ分類 |
| **6** | `qc_filter_keep_normal_signal.m` | Remove outliers and keep normal signals only | 外れ値を除去し正常信号のみ保持 |
| **7** | `make_stats_table_merged.m` | Merge A/D groups and export summary statistics | グループA・Dを統合し統計表を出力 |
| **8** | `run_glm_each_session.m` | Run GLM analysis for each session | 各セッションに対してGLM解析を実行 |
| **9** | `/reports/` | Save summary plots and statistical reports | 結果図・統計レポートを保存 |

---

✅ *This end-to-end pipeline ensures reproducibility and transparency from raw HOT-2000 data to GLM-based group statistics.*  
✅ *この一連のパイプラインにより、生データからGLMベースの群統計までを再現性・透明性高く導出します。*


## 🧩 Noise Correction and GLM Analysis｜ノイズ補正とGLM解析
<a id="noise-glm"></a>

🔷 Overview / 概要
This section describes how noise and superficial artifacts were removed from the HOT-2000 fNIRS signals prior to GLM analysis.
本節では、GLM解析の前にHOT-2000で取得したfNIRS信号からノイズおよび浅層（頭皮）由来成分を除去する手順を示します。

This pipeline follows the recommendations of Tachtsidis & Scholkmann (2016) and von Lühmann et al. (2020), combining
band-pass filtering, short-separation regression, and GLM modeling for robust estimation of cortical hemodynamic responses.
本解析パイプラインは、Tachtsidis & Scholkmann (2016) および von Lühmann ら (2020) の推奨に基づき、
バンドパスフィルタ処理、ショートセパレーション回帰（SD3−SD1）、GLMモデル化を統合しています。

1️⃣ Band-pass Filtering
Purpose: Remove low-frequency drift and high-frequency physiological noise (e.g., respiration, heartbeat).
目的： 低周波ドリフトや高周波生理ノイズ（呼吸・心拍など）を除去します。
•	Filter range: 0.01 – 0.20 Hz
（多くのfNIRS研究で採用されているタスク関連帯域）

```matlab
bp = nirs.modules.BandPassFilter();
bp.highpass = 0.01;
bp.lowpass  = 0.20;
raw = bp.run(raw);
```

###2️⃣ Short-separation Regression (SD3 − SD1)
Purpose: Remove scalp and systemic artifacts using paired short-/long-distance channels.
目的： 同一部位の1 cmおよび3 cmチャンネルの差分により、頭皮・全身循環由来のノイズを除去します。

[
HbT_{cortical} = HbT_{SD3} - HbT_{SD1}
]

This difference approximates cortical hemodynamics while attenuating superficial interference,
thus implementing short-separation regression without the need for auxiliary sensors.
この差分は浅層ノイズを抑えつつ皮質由来の血行動態を近似し、外部センサーを用いないショートセパレーション回帰として機能します。

```matlab
HbT_left  = T.("HbT change(left SD3cm)") - T.("HbT change(left SD1cm)");
HbT_right = T.("HbT change(right SD3cm)") - T.("HbT change(right SD1cm)");
```

###3️⃣ General Linear Model (GLM)
Purpose: Estimate task-related hemodynamic responses (β-values) using a design matrix of task conditions.
目的： タスク条件を説明変数とするデザイン行列を用いて、タスク関連β値（脳血流応答）を推定します。

[
Y = X \beta + \varepsilon
]

Contrast values such as Task − Control, DT − CT, and Left − Right
were calculated for statistical comparisons and visualization.
β値を基に Task − Control、DT − CT、Left − Right のコントラストを算出し、統計比較と可視化を行います。

```matlab
stats = nirs.modules.GLM().run(preproc);
export_glm_fit_plot(raw, stats, 'path/to/save_glm_fit.png');
```

###4️⃣ Summary of Processing Steps
| 🧩 Step | 🧠 Module | ✳️ Description (English) | 📝 内容（日本語） |
|:--:|:--|:--|:--|
| **1** | `load_raw_hot2000.m` | Load and structure HOT-2000 CSV files | 生CSVの読み込み・構造化 |
| **2** | `BandPassFilter` | Apply 0.01–0.20 Hz band-pass filter to remove physiological noise | 0.01–0.20 Hzの帯域通過フィルタで生理ノイズ除去 |
| **3** | **SD3 − SD1** | Perform short-separation regression to remove superficial (scalp/systemic) artifacts | 浅層（頭皮・全身循環）由来ノイズの除去（ショートセパレーション回帰） |
| **4** | `GLM` | Estimate β-values for each task condition via General Linear Model | GLMにより各タスク条件のβ値を推定 |
| **5** | `export_glm_fit_plot.m` | Plot observed vs. fitted hemodynamic responses | 観測波形とGLMフィット波形の比較プロットを出力 |
| **6** | `make_stats_table_merged.m` | Summarize and export group-level statistics | 群レベル統計のサマリーを出力 |

---

✅ *This sequence provides a reproducible and transparent pipeline from raw HOT-2000 data to GLM-based cortical activation metrics.*  
✅ *この一連の処理は、生データからGLMベースの皮質活動指標までを再現可能かつ透明性の高い形で導出します。*

---

### 🔬 References
<a id="references"></a>
- **Tachtsidis & Scholkmann (2016).** *Neurophotonics*, 3(3):031405.  
- **von Lühmann et al. (2020).** *Neurophotonics*, 7(3):035002.  
- **Zhang et al. (2007).** *NeuroImage*, 34(2):550–559.
