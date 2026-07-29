# 資産運用向け Snowflake AI ハンズオン

Snowflake Marketplace の公開証券データと非構造化データ（決算カンファレンスコール、企業ニュース）を
組み合わせ、**ゼロから Snowflake CoWork まで2時間で構築する**ハンズオンです。

## 概要

あなたは架空の資産運用会社 **スノーアセットマネジメント** のデータ活用担当者です。
運用部門とフロント部門から、こんな要望が来ています。

> 「保有銘柄の決算コールを全部読む時間がない。実績数値と経営陣のコメントを突き合わせたレビューを
> すぐに出してほしい」
>
> 「朝会の前に、保有銘柄のニュースと株価変動をまとめた資料が自動で欲しい」

このハンズオンでは、これを **自然言語で質問すれば返ってくる状態** まで作り上げます。

### 到達点

2時間後には、Snowflake CoWork でこんな質問ができるようになります。

- 「当社ファンドのAUM上位5銘柄とセクター構成を教えて」
- 「NVDAの直近決算コールで経営陣が語ったデータセンター需要の見通しと、実績売上の推移を突き合わせて」
- 「朝会用のブリーフィングメモを作って」← Agent skill が自動で発火します

### 扱うデータ

| 種別 | データ | 取得元 |
|---|---|---|
| 構造化 | 米国株の日次株価（10銘柄・3年分） | Marketplace |
| 構造化 | SEC提出書類ベースの四半期財務諸表 | Marketplace |
| 構造化 | 為替（USD/JPY）・米国債イールド | Marketplace |
| 構造化 | 自社ファンドの保有明細（架空） | `setup.sql` で生成 |
| 非構造化 | NVIDIA Q1 FY2027 決算カンファレンスコール（PDF・16ページ） | リポジトリ同梱 |
| 非構造化 | 米国企業ニュース 50件（ダミー） | リポジトリ同梱 |

### 使う Snowflake 機能

`AI_PARSE_DOCUMENT` / `AI_SENTIMENT` / `AI_CLASSIFY` / `AI_EXTRACT` / `AI_AGG` /
`SPLIT_TEXT_MARKDOWN_HEADER` / `AI_GENERATE_TABLE_DESC` / Semantic View / Cortex Analyst /
Cortex Search / Cortex Agent（skills 付き）/ Snowflake CoWork

---

## アジェンダ（合計 2時間）

| # | ファイル | 内容 | 目安 |
|---|---|---|---|
| 事前準備 | （Snowsight 操作） | Marketplace からデータを取得 | ⏱️ 5分 |
| Step 0 | `setup.sql` | 環境構築・データキュレーション | ⏱️ 10分 |
| Part 1 | `part1_ai_functions.ipynb` | AI Functions で非構造化データを構造化する | ⏱️ 35分 |
| Part 2 | `part2_cortex_analyst.ipynb` | Semantic View と Cortex Analyst | ⏱️ 30分 |
| — | 休憩 | | ⏱️ 10分 |
| Part 3 | `part3_cortex_agent.ipynb` | Cortex Search / Agent / Snowflake CoWork | ⏱️ 30分 |

---

## 前提条件

- Snowflake アカウント（`ACCOUNTADMIN` ロールが使えること）
- Snowsight にアクセスできること

これだけです。ローカルへのツールインストールは不要です。

---

## Step 0: Marketplace データの取得

### 0-1. リージョンとアカウントを確認する

Snowsight のワークシートで `account_info.sql` の内容を実行し、リージョンを控えておきます。

```sql
USE ROLE ACCOUNTADMIN;
SELECT CURRENT_REGION() AS region, CURRENT_ACCOUNT() AS locator;
```

### 0-2. リスティングを取得する

1. Snowsight のナビゲーションメニューから **Data Products** » **Marketplace** を開く
2. 検索窓に `Snowflake Public Data` と入力
3. **`Snowflake Public Data (Paid)`** を選択（60日間の無料トライアルが付いています）
4. **Get** をクリックし、以下を設定する

| 設定項目 | 値 |
|---|---|
| Database name | `SNOWFLAKE_PUBLIC_DATA`（推奨。デフォルトのままでも可） |
| Roles that can access this database | `ACCOUNTADMIN` |

> ### 💡 データベース名はデフォルトのままでも問題ありません
>
> `setup.sql` の Step 5 が、`SNOWFLAKE_PUBLIC_DATA_PAID` / `SNOWFLAKE_PUBLIC_DATA_FREE` など
> よくある名前を自動で検出し、`SNOWFLAKE_PUBLIC_DATA` にリネームします。
> すでに `SNOWFLAKE_PUBLIC_DATA` という名前になっている場合は何もしません。
>
> 自動リネームをさせたくない（他の用途で既存のデータベース名を使っている）場合は、
> 取得時に Database name を `SNOWFLAKE_PUBLIC_DATA` にしてください。

> **💡 有料版と無料版について**
>
> 有料版には60日間の無料トライアルが付いており、データにラグがありません。
> 無料版（`Snowflake Public Data (Free)`）でも同じデータベース名を付ければ `setup.sql` は
> そのまま動作しますが、**データが3ヶ月ラグ・四半期更新**になります。
> 本ハンズオンの中核である「NVIDIA Q1 FY2027 決算コール（2026年5月20日）と実績財務数値の突合」は
> 有料版でないと成立しない可能性があるため、有料版のトライアルを推奨します。

### 0-3. 取得できたか確認する

```sql
SHOW DATABASES LIKE 'SNOWFLAKE_PUBLIC_DATA%';
```

`SNOWFLAKE_PUBLIC_DATA` または `SNOWFLAKE_PUBLIC_DATA_PAID` などが一覧に出ていれば成功です。

---

## Step 1: setup.sql の実行

1. Snowsight のナビゲーションメニューから **Projects** » **Workspaces** を開く
2. **+ Add new** » **SQL File** を選び、名前を付ける
3. このリポジトリの `setup.sql` の内容を全部コピーして貼り付ける
4. **Run All** で全ステートメントを順に実行する

各ステップの完了時に `【Step N】... が完了しました` というメッセージが出ます。
最後に完了バナーが表示されれば成功です。

所要時間は約 3〜5分です（Step 6 のデータキュレーションに1〜2分かかります）。

---

## Step 2: Workspace に Git リポジトリを追加する

Notebook を実行するために、このリポジトリを Workspace に追加します。

1. **Projects** » **Workspaces** を開く
2. **+ Add new** » **From Git repository** を選ぶ
3. 以下を入力する

| 設定項目 | 値 |
|---|---|
| Repository URL | `https://github.com/sfc-gh-kmotokubota/asset-management-ai-handson.git` |
| Workspace name | `asset-management-ai-handson` |
| API integration | `git_api_integration_snow_am`（`setup.sql` で作成済み） |
| Authentication | Public repository |

4. **Create** をクリック

---

## Step 3: Notebook を順番に実行する

Workspace 内の Notebook を **Part 1 → Part 2 → Part 3 の順に**実行します。

```
setup.sql
    │
    ├──> part1_ai_functions.ipynb
    │       GOLD_EARNINGS_CALL_CHUNKS / GOLD_COMPANY_NEWS_ANALYZED を作成
    │
    ├──> part2_cortex_analyst.ipynb
    │       PORTFOLIO_MARKET_SEMANTIC_VIEW を作成（Part 1 の Gold テーブルが必要）
    │
    └──> part3_cortex_agent.ipynb
            Cortex Search と Agent を作成（Part 1・Part 2 の成果物が必要）
```

> ### ⚠️ 順序は厳守してください
>
> 各 Part は前の Part の成果物に依存しています。Part 2 だけを単独で実行することはできません。

Notebook を開いたら、右上のウェアハウス選択で **`SNOW_AM_WH`** を指定してください。

---

## アーキテクチャ

```
                     Snowflake Marketplace
                              │
        ┌─────────────────────┴──────────────────────┐
        │   SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA        │
        │   ・STOCK_PRICE_TIMESERIES（縦持ち）        │
        │   ・SEC_REPORT_ATTRIBUTES（XBRL全項目）     │
        │   ・COMPANY_INDEX / FX / TREASURY           │
        └─────────────────────┬──────────────────────┘
                              │ setup.sql Step 6
                              │ 縦持ち → 横持ちにピボット
                              ▼
   ┌──────────────────────────────────────────────────────────┐
   │  SNOW_AM_DB.MARKET_INTELLIGENCE                          │
   │                                                          │
   │  【構造化】                    【非構造化】                │
   │  DIM_SECURITY                  DOC_STAGE                 │
   │  DIM_FUND                        ├ 決算コール PDF        │
   │  FACT_FUND_HOLDING               └ ニュース CSV          │
   │  FACT_STOCK_PRICE_DAILY               │                  │
   │  FACT_FINANCIAL_METRICS               │ Part 1           │
   │  FACT_FX_RATE                         ▼                  │
   │  FACT_TREASURY_YIELD          GOLD_EARNINGS_CALL_CHUNKS  │
   │        │                      GOLD_COMPANY_NEWS_ANALYZED │
   │        │                              │                  │
   │        │ Part 2                       │ Part 3           │
   │        ▼                              ▼                  │
   │  PORTFOLIO_MARKET_             SEARCH_EARNINGS_CALL      │
   │  SEMANTIC_VIEW                 SEARCH_COMPANY_NEWS       │
   │  （Cortex Analyst）            （Cortex Search）          │
   │        │                              │                  │
   │        └──────────┬───────────────────┘                  │
   │                   ▼                                      │
   │        MARKET_INTELLIGENCE_AGENT                         │
   │            + SKILL_STAGE                                 │
   │              ├ morning-brief                             │
   │              └ earnings-review                           │
   └───────────────────┬──────────────────────────────────────┘
                       ▼
              Snowflake CoWork
```

---

## 作成される Snowflake オブジェクト一覧

### 環境

| 種別 | 名称 |
|---|---|
| Database | `SNOW_AM_DB` |
| Schema | `MARKET_INTELLIGENCE` |
| Warehouse | `SNOW_AM_WH`（XSMALL） |
| API Integration | `git_api_integration_snow_am` |
| Git Repository | `SNOW_AM_HANDSON_REPO` |
| Stage | `DOC_STAGE`, `SKILL_STAGE` |

### テーブル（`setup.sql` で作成）

| テーブル | 内容 |
|---|---|
| `DIM_SECURITY` | 銘柄マスタ（10銘柄） |
| `DIM_FUND` | ファンドマスタ（架空・3ファンド） |
| `FACT_FUND_HOLDING` | ファンド保有明細 |
| `FACT_STOCK_PRICE_DAILY` | 日次株価（3年分・横持ち） |
| `FACT_FINANCIAL_METRICS` | 四半期財務諸表（横持ち） |
| `FACT_FX_RATE` | USD/JPY |
| `FACT_TREASURY_YIELD` | 米国債イールド |

### テーブル（Notebook で作成）

| テーブル | 作成場所 |
|---|---|
| `RAW_EARNINGS_CALLS` | Part 1 |
| `GOLD_EARNINGS_CALL_CHUNKS` | Part 1 |
| `RAW_COMPANY_NEWS` | Part 1 |
| `GOLD_COMPANY_NEWS_ANALYZED` | Part 1 |

### AI オブジェクト

| 種別 | 名称 | 作成場所 |
|---|---|---|
| Semantic View | `PORTFOLIO_MARKET_SEMANTIC_VIEW` | Part 2 |
| Cortex Search | `SEARCH_EARNINGS_CALL` | Part 3（AI Studio GUI） |
| Cortex Search | `SEARCH_COMPANY_NEWS` | Part 3（Notebook） |
| Cortex Agent | `MARKET_INTELLIGENCE_AGENT` | Part 3 |

---

## トラブルシューティング

### `Database 'SNOWFLAKE_PUBLIC_DATA' does not exist`

`setup.sql` の Step 5 の自動検出が失敗しています。Step 5-1 の出力メッセージを確認してください。
`NG:` で始まるメッセージが出ている場合は Marketplace リスティングが取得できていません。

手動で対応する場合は、実際の名前を確認してリネームしてください。

```sql
SHOW DATABASES LIKE 'SNOWFLAKE_PUBLIC_DATA%';
ALTER DATABASE <実際の名前> RENAME TO SNOWFLAKE_PUBLIC_DATA;
```

### `Cortex ... is not available in region`

クロスリージョン推論が有効になっていません。`setup.sql` の Step 1 に含まれていますが、
単独で実行する場合は以下を実行してください。

```sql
USE ROLE ACCOUNTADMIN;
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
```

### Cortex Search の作成で `Warehouse 'COMPUTE_WH' does not exist`

本ハンズオンは `SNOW_AM_WH` を使うため通常は発生しませんが、AI Studio の GUI から作成する場合は
ウェアハウス選択で `SNOW_AM_WH` を指定してください。

### `FACT_FINANCIAL_METRICS` の数値がおかしい（営業利益が売上を超えている）

`setup.sql` Step 6-3 の `METADATA IS NULL` フィルタが抜けています。このフィルタがないと
セグメント別のXBRLファクトが混入します。以下で確認できます。

```sql
SELECT * FROM FACT_FINANCIAL_METRICS
WHERE GROSS_PROFIT > REVENUE OR OPERATING_INCOME > REVENUE;
-- 0件であれば正常
```

### JPM（JPMorgan Chase）の売上が NULL になっている

これは仕様です。金融業は「売上（Revenues）」の XBRL タグを使わず、純利益と EPS のみが
取得できます。業種によって開示項目が異なることを示す教材として、あえて残しています。

### Snowflake CoWork で Agent skill が発火しない

1. `DESCRIBE AGENT SNOW_AM_DB.MARKET_INTELLIGENCE.MARKET_INTELLIGENCE_AGENT;` の出力に
   `skills` が2件含まれているか確認する
2. `LS @SNOW_AM_DB.MARKET_INTELLIGENCE.SKILL_STAGE/ PATTERN='.*SKILL\.md';` で
   `skills/morning-brief/SKILL.md` の階層になっているか確認する（`SKILL.md` はフォルダ直下必須）
3. それでも発火しない場合は、CoWork のチャット入力欄の **+** ボタンから skill を明示的に選択する

---

## 後片付け

ハンズオン終了後、`cleanup.sql` を実行するとこのハンズオンで作成したデータベースと
ウェアハウスを削除できます。API Integration などのアカウントレベルのオブジェクトは
他の用途と共有される可能性があるため、意図的にコメントアウトしてあります。
