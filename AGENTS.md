# AGENTS.md

## プロジェクト概要

資産運用・財務企画部門向けの Snowflake AI ハンズオン教材です。Snowflake Marketplace から取得した
米国証券データ（株価・SEC財務諸表）と、非構造化データ（決算カンファレンスコール PDF、企業ニュース）を
組み合わせ、Cortex AI Functions → Cortex Analyst → Cortex Agent → Snowflake CoWork までを
2時間で体験します。

## 絶対に守るルール

### 1. 顧客企業名を出さない

このリポジトリは複数の金融機関・資産運用会社に展開します。**特定のお客様の企業名・部署名・
担当者名を一切記載しないでください。**

- 舞台となる会社は架空の **スノーアセットマネジメント（SNOW ASSET MANAGEMENT）** で統一する
- ファンド名・顧客名も架空のものを使う
- 「〇〇生命様向け」「〇〇銀行様」のような記述は禁止

### 2. 言語はすべて日本語

- **会話・応答はすべて日本語**で行う
- **コード内のコメントは日本語**で記述する
- **処理ログ・ステータスメッセージは日本語**で出力する（例: `'【Step 1】環境設定が完了しました'`）
- **マークダウンセルの説明文は日本語**で記述する
- **エラーの説明やトラブルシューティングも日本語**で行う
- SQL文やPythonコードのキーワード・関数名はそのままで構わないが、**説明やコメントは日本語**にする
- 結果セットの列名は日本語のクォート付き別名を使う（例: `AS "銘柄"`, `AS "センチメント"`）

### 3. 2時間という制約を常に意識する

各パートには目安時間が設定されています。内容を追加する場合は、どこを削るかを併せて検討してください。
重いAI処理は「休憩前に実行」パターン（コメントアウト＋講師向けメモ）で吸収します。

## プロジェクト構成

```
.
├── README.md                    参加者向けガイド（アジェンダ・前提条件・セットアップ手順）
├── AGENTS.md                    このファイル
├── account_info.sql             リージョン/アカウント確認
├── setup.sql                    環境セットアップ（Step 1-8）
├── cleanup.sql                  後片付け
├── part1_ai_functions.ipynb     AI Functions / AI_PARSE_DOCUMENT（35分）
├── part2_cortex_analyst.ipynb   Semantic View / Cortex Analyst（30分）
├── part3_cortex_agent.ipynb     Cortex Search / Agent / CoWork（30分）
├── data/
│   ├── earnings_calls/          決算カンファレンスコール PDF
│   └── us_company_news.csv      米国企業ニュース（ダミー、50件）
└── skills/                      Cortex Agent skills
    ├── morning-brief/SKILL.md
    └── earnings-review/SKILL.md
```

## Snowflake オブジェクト命名規約

| 種別 | 名称 |
|---|---|
| Database | `SNOW_AM_DB` |
| Schema | `MARKET_INTELLIGENCE` |
| Warehouse | `SNOW_AM_WH` |
| API Integration | `git_api_integration_snow_am` |
| Git Repository | `SNOW_AM_HANDSON_REPO` |
| Stage | `DOC_STAGE`（PDF/CSV）, `SKILL_STAGE`（Agent skills） |
| Semantic View | `PORTFOLIO_MARKET_SEMANTIC_VIEW` |
| Cortex Search | `SEARCH_EARNINGS_CALL`, `SEARCH_COMPANY_NEWS` |
| Cortex Agent | `MARKET_INTELLIGENCE_AGENT` |
| ディメンション | `DIM_SECURITY`, `DIM_FUND` |
| ファクト | `FACT_STOCK_PRICE_DAILY`, `FACT_FINANCIAL_METRICS`, `FACT_FX_RATE`, `FACT_TREASURY_YIELD`, `FACT_FUND_HOLDING` |
| RAW / GOLD | `RAW_*` / `GOLD_*` |
| Marketplace 参照元 | `SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA`（固定） |

銘柄ユニバース（10銘柄）: `NVDA`, `MSFT`, `AAPL`, `GOOGL`, `AMZN`, `META`, `AVGO`, `TSLA`, `JPM`, `XOM`

## Notebook（.ipynb）の記述規約

### セル形式

Snowflake Notebook のセルは以下の形式です。`%%sql` マジックは不要で、
metadata の `resultVariableName` が結果変数名になります。

```json
{"metadata": {"kernelspec": {"display_name": "Streamlit Notebook", "name": "streamlit"},
              "language_info": {"name": "python"}}}
```

| セル種別 | metadata |
|---|---|
| SQL | `{"language": "sql", "resultVariableName": "result_xxx"}` |
| Python | `{"language": "python"}` |
| Markdown | `{"codeCollapsed": true, "collapsed": false}` |

### Markdown の書き方

- 見出しは `## n. 大項目` / `### n-m. 小項目`（参考レポと同じレベルを維持する）
- **引用ブロックの中で見出し（`> ### X`）を使わない。** 引用枠の中で文字が過大に表示されます。
  `> **X**` と太字にしてください
- **markdown セルを不必要に分割しない。** 見出しだけの3〜4行セルが連続すると
  セルの区切りが不自然に見えます。見出しと本文、大項目と小項目は同じセルにまとめる
- 1セルが40行を超えるようなら分割を検討する
- 結果セットの列名は日本語のクォート付き別名にする（例: `AS "銘柄"`）

### セル構成の確認

セルを追加・編集したあとは、以下の観点で確認してください。

- markdown セルが連続していないか（連続する場合、それぞれが十分な分量を持っているか）
- 引用ブロック内に `#` 見出しが混ざっていないか
- コードフェンス（```）が偶数個で閉じているか

## Marketplace データを扱う際の重大な注意点

### データベース名は `SNOWFLAKE_PUBLIC_DATA` に固定

Marketplace リスティング取得時に、**有料版・無料版どちらを選んでもデータベース名を
`SNOWFLAKE_PUBLIC_DATA` にする**よう README で指示しています。`setup.sql` はこの名前を
ハードコードしているため、名前が違うと全ステップが失敗します。

### 主要ビューは縦持ち（`VARIABLE` / `VALUE`）

`STOCK_PRICE_TIMESERIES`、`FX_RATES_TIMESERIES`、`US_TREASURY_TIMESERIES`、
`COMPANY_CHARACTERISTICS` はすべて縦持ちです。そのまま Cortex Analyst / Semantic View に
渡すと精度が出ないため、`setup.sql` で横持ちにピボットします。

`STOCK_PRICE_TIMESERIES` の `VARIABLE` の値:
`pre-market_open` / `all-day_high` / `all-day_low` / `post-market_close` / `nasdaq_volume`
（それぞれ `_adjusted` 付きも存在）

### 財務指標は `SEC_REPORT_ATTRIBUTES` を使う（`SEC_METRICS_TIMESERIES` ではない）

`SEC_METRICS_TIMESERIES` は当該ユニバースでは実質売上のみで、純利益・EPS が存在しません。
`SEC_REPORT_ATTRIBUTES`（XBRL 全項目）を使いますが、**以下のフィルタを1つでも落とすと
数値が壊れます**（セグメント軸付きファクトを `MAX()` が拾い、営業利益が売上を超えるなど）。

```sql
a.COVERED_QTRS = 1              -- 単四半期のみ（累計値を除外）
AND a.METADATA IS NULL          -- ★連結（非セグメント）ファクトのみ。これが最重要
AND a.STATEMENT = 'Income Statement'
-- 同一期に複数 ADSH（修正再提出）があるため FILED_DATE DESC で最新を採用
```

売上タグは企業により異なるため `COALESCE` が必須:

| 銘柄 | 売上タグ |
|---|---|
| NVDA, GOOGL, XOM | `Revenues` |
| AAPL, AMZN, AVGO, META, MSFT, TSLA | `RevenueFromContractWithCustomerExcludingAssessedTax` |
| JPM | 両方なし（EPS・純利益のみ。金融業は売上概念が異なる） |

`NetIncomeLoss` は AVGO で欠損するため `ProfitLoss` をフォールバックに使用します。

### 会計期の表現

`SEC_REPORT_INDEX.FISCAL_YEAR` / `FISCAL_PERIOD` は提出書類の文脈依存で不整合です
（NVDA 2025-04-27 が FY2027 Q1 と付く例あり）。`PERIOD_END_DATE` から暦四半期ラベル
（`YYYY-Qn`）を導出して使ってください。

## 変更を加えたときの検証

財務テーブルに手を入れた場合は、必ず以下の健全性チェックを通してください。

```sql
-- 粗利・営業利益が売上を超えていないこと（METADATA フィルタが効いている証拠）
SELECT * FROM FACT_FINANCIAL_METRICS
WHERE (GROSS_PROFIT > REVENUE OR OPERATING_INCOME > REVENUE);  -- 0件であること

-- NVDA Q1 FY2027 の実績が決算コールの記述と一致すること
-- 売上 81,615百万ドル（コールでは「$82 billion」と表現）
SELECT * FROM FACT_FINANCIAL_METRICS WHERE TICKER='NVDA' AND PERIOD_END_DATE='2026-04-26';
```

## Cortex Agent skills の注意点

- `SKILL.md` はスキルフォルダの**ルート直下**に置く（サブディレクトリは探索されない）
- 補助スクリプトも `SKILL.md` と同じフォルダに置く
- `setup.sql` の `COPY FILES` はフォルダ構造を保持する形で書く
- `ALTER AGENT` でツールを追加する代わりに `CREATE OR REPLACE AGENT` を使う
- skill が発火しない場合は `description` のトリガーワードを増やす
