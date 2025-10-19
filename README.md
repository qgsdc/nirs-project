# nirs-project  
**MATLAB-based fNIRS + HRV analysis pipeline (HOT-2000 / Hb133 / Check My Heart)**  
*Ver. 2025-10-19 – Kei Saruwatari*

---

## 📘 Overview 概要
このリポジトリは、**NeU社 HOT-2000 / Astem社 Hb133** を用いた  
fNIRS信号と心拍変動（HRV）データの解析をMATLAB上で自動化するプロジェクトです。  
主な目的は、創造性課題中の**前頭前野活動（HbT/HbO/HbR）**および  
**自律神経反応（推定脈拍・HRV指標）**を統合的に解析することです。

---

## 🧩 Folder structure ディレクトリ構成
nirs-project/
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

---

## ⚙️ Main QC pipeline 主要QCパイプライン

### 1️⃣ 個別セッションQC
```matlab
run_qc_group("data/group_a");
run_qc_group("data/group_d");

2️⃣ ノイズ分類（自動）
qc_classify_noise("data/group_a/QC_hot2000_metrics.csv");
qc_classify_noise("data/group_d/QC_hot2000_metrics.csv");

3️⃣ 外れ値除去とフィルタ済み保存
qc_filter_keep_normal_signal("data/group_a/QC_hot2000_metrics_classified.csv");
qc_filter_keep_normal_signal("data/group_d/QC_hot2000_metrics_classified.csv");

4️⃣ 両群統合と統計出力
make_stats_table_merged("data/group_a","data/group_d", ...
    'SaveTxt',true,'SaveCsv',true,'OutName','QC_merged');

🧠 Analysis flow 解析フロー概要
	1.	Load raw HOT-2000 CSV → load_raw_hot2000.m
	2.	Preprocess (0.01–0.2 Hz BandPass) → BandPassFilter
	3.	Hampel off / PCA off
	4.	Compute QC metrics → qc_hot2000_metrics.m
	5.	Noise classification → qc_classify_noise.m
	6.	Filter & merge → make_stats_table_merged.m
	7.	GLM estimation → run_glm_each_session.m
	8.	Summary plots & stats → /reports/

🚀 Next steps
	•	GLM 解析パートの README セクション追加
	•	HRV 同期モジュール (sync_hrv_nirs_markers.m) のドキュメント化
	•	論文用図表テンプレートの統合
