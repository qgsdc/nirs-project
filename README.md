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

## 🧠 Analysis Flow


# fNIRS Data Analysis: Step 1 (Data Structuring)

HOT-2000から出力された生データを読み込み、解析に適した構造体に変換して保存する工程です。

## 1. 使用ファイル (MATLAB Scripts)

| ファイル名 | 役割 | 主な処理内容 |
|:---|:---|:---|
| `load_raw_hot2000_v2.m` | **読み込み関数** | ・生CSVのヘッダー（14行目付近）を自動特定<br>・$HbT = SD3 - SD1$ による皮膚血流除去（SD減算）を実施<br>・5列目 `Estimated pulse rate`（心拍データ）の抽出 |
| `run_step1_load_and_save.m` | **実行スクリプト** | ・全26名の個別フォルダを自動スキャン<br>・全312セッション（12セッション/人）を特定<br>・被験者ごとに構造化し一括保存 |

## 2. 実行コマンド

再現性を確保するため、以下の手順で実行しました。

```matlab
% フォルダ構成の更新とパスの追加
addpath(genpath('script')); 
rehash;
```

% Step 1 の実行（データの読み込み・加工・保存）
run_step1_load_and_save;

3. 入力と出力 (I/O)
Input (Raw Data)
場所: ../raw_data/group_a/ および ../raw_data/group_b/

形式: 被験者別フォルダ（例: 20250331_nakashima/）内に格納されたCSVファイル群。

Output (Master Data)
場所: ../processed/

ファイル名: raw_all_312_sessions.mat

ログ: analysis_log_step1.txt （読み込み詳細を記録）

4. データ構造の定義 (Data Hierarchy)
保存された raw_all_312_sessions.mat および filtered_all_312_sessions.mat は、以下の階層構造を持つ構造体 raw_all として格納されています。

レベル,変数名 / フィールド,内容,型・サイズ
第1階層,raw_all,全体構造体,・全26名のデータを保持する構造体
第2階層,.[subject_id],被験者ID,・個別被験者（例：nakashima）のフィールド
第3階層,.[session_id],セッションID,"・各試行（例：dt1, dt_ctrl1）のデータ群"
第4階層,.data,HbT 変化量,・[Time x 2] 行列 (1:左 / 2:右)・HbT=SD3−SD1 済み
第4階層,.pulse,心拍データ,・[Time x 1] 列ベクトル・推定心拍数（Estimated pulse rate）
第4階層,.time,時間軸,・[Time x 1] 列ベクトル・ヘッドセット内部の経過時間（秒）
第4階層,.mark,マーカー,・[Time x 1] 列ベクトル・Event Marker（課題の開始・終了合図）

セッション名の対応表 (Total: 12 Sessions per Subject)
各被験者フォルダ内のCSVファイルは、読み込み時に以下のIDへマッピングされます。
課題区分,セッションID (構造体内の名称),内容,試行回数
二重課題 (DT),"dt1, dt2, dt3",創造性課題 (DT) 実行中,3回
,"dt_ctrl1, dt_ctrl2, dt_ctrl3",DTの対照条件 (Control),3回
単一課題 (CT),"ct1, ct2, ct3",創造性課題 (CT) 実行中,3回
,"ct_ctrl1, ct_ctrl2, ct_ctrl3",CTの対照条件 (Control),3回

行列データの詳細 (.data)
Column 1: 左チャネルの HbT 変化量 (Left Channel)

Column 2: 右チャネルの HbT 変化量 (Right Channel)

※ raw_all_312_sessions.mat では生データ、filtered_all_312_sessions.mat ではバンドパスフィルタ適用後の値が格納されています。

## Processed Data & Quality Control

`processed/step1/` フォルダには、解析の核となる以下の2つのデータセットが格納されています。

| ファイル名 | ステップ | 内容 | 役割 |
|:---|:---|:---|:---|
| `raw_all_312_sessions.mat` | Step 1 | **生データ統合版** | 全312セッションの統合データ。皮膚血流補正(SD3-SD1)済み。 |
| `filtered_all_312_sessions.mat` | Step 2 | **フィルタ適用版** | 0.01-0.20Hzのバンドパスフィルタ適用後。統計解析に使用。 |

### Visual Quality Control (QC)
Step 3 (`run_save_all_plots.m`) を実行することで、`filtered_all_312_sessions.mat` に基づく可視化プロットが生成されます。

- **保存先**: `qc/plots/`
- **画像枚数**: 312枚 (26被験者 × 12セッション)
- **確認項目**: 
  - 異常なスパイクノイズ（体動）の有無
  - 信号の消失（接触不良）
  - 左右チャネルの極端な不一致

Current Status: 2026-01-31 時点で全312セッションの読み込み・フィルタリング・プロット生成が正常終了。qc/plots/ に全数出力済みであることを確認。
	


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

