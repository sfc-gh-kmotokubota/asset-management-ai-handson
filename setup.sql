/*
================================================================================
資産運用向け Snowflake AI ハンズオン - 環境セットアップスクリプト
================================================================================

【概要】
架空の資産運用会社「スノーアセットマネジメント」のマーケットインテリジェンス基盤を構築します。

【処理内容】
  Step 1: 環境設定（ロール・クロスリージョン推論・ウェアハウス）
  Step 2: データベース・スキーマ・ステージの作成
  Step 3: GitHub 連携（API統合と Git リポジトリ）
  Step 4: GitHub からファイルをステージへ搬入（PDF・CSV・Agent skills）
  Step 5: Marketplace データの前提チェック（データベース名の自動検出を含む）
  Step 6: Marketplace データのキュレーション（縦持ち → 横持ち）
  Step 7: 自社ファンドのダミーデータ生成
  Step 8: Snowflake CoWork オブジェクトの作成

【データソース】
  Marketplace: SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA
               （Snowflake Public Data (Paid) / (Free) のいずれでも動作します）
  GitHub:      https://github.com/sfc-gh-kmotokubota/asset-management-ai-handson

【前提条件】
  ・ACCOUNTADMIN ロールが使えること
  ・Marketplace リスティング「Snowflake Public Data」を取得済みであること
    データベース名は SNOWFLAKE_PUBLIC_DATA_PAID / _FREE のままでも構いません。
    Step 5 が自動で SNOWFLAKE_PUBLIC_DATA にリネームします。

【実行方法】
  Snowsight の Workspaces に SQL ファイルとして貼り付け、Run All で全文を実行してください。

【所要時間】
  約3〜5分（Step 6 のキュレーションに1〜2分かかります）

【次のステップ】
  part1_ai_functions.ipynb を開いてハンズオンを開始してください。
================================================================================
*/


-- ============================================================================
-- Step 1: 環境設定
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- クロスリージョン推論を有効化する
-- 東京リージョンなど、一部のモデルがローカルに存在しないリージョンでも Cortex を使えるようにします
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- ハンズオン用ウェアハウスを作成する
CREATE WAREHOUSE IF NOT EXISTS SNOW_AM_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND   = 60
    AUTO_RESUME    = TRUE
    COMMENT        = '資産運用向け AI ハンズオン用ウェアハウス';

USE WAREHOUSE SNOW_AM_WH;

SELECT '【Step 1】環境設定が完了しました' AS status;


-- ============================================================================
-- Step 2: データベース・スキーマ・ステージの作成
-- ============================================================================

CREATE DATABASE IF NOT EXISTS SNOW_AM_DB
    COMMENT = 'スノーアセットマネジメント（架空）のマーケットインテリジェンス基盤';

USE DATABASE SNOW_AM_DB;

CREATE SCHEMA IF NOT EXISTS MARKET_INTELLIGENCE
    COMMENT = '市場データ・決算コール・ニュースを統合した分析スキーマ';

USE SCHEMA MARKET_INTELLIGENCE;

-- 決算コール PDF とニュース CSV を格納するステージ
CREATE OR REPLACE STAGE DOC_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY  = (ENABLE = TRUE)
    COMMENT    = '決算カンファレンスコール PDF・ニュース CSV を格納する内部ステージ';

-- Cortex Agent の skills を格納するステージ
-- 注意: SKILL.md は各スキルフォルダの直下に置く必要があります（サブディレクトリは探索されません）
CREATE OR REPLACE STAGE SKILL_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY  = (ENABLE = TRUE)
    COMMENT    = 'Cortex Agent skills（SKILL.md）を格納する内部ステージ';

SELECT '【Step 2】データベース・スキーマ・ステージの作成が完了しました' AS status;


-- ============================================================================
-- Step 3: GitHub 連携の設定
-- ============================================================================

CREATE OR REPLACE API INTEGRATION git_api_integration_snow_am
    API_PROVIDER         = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-kmotokubota/')
    ENABLED              = TRUE
    COMMENT              = '資産運用向け AI ハンズオン用の GitHub API 統合';

CREATE OR REPLACE GIT REPOSITORY SNOW_AM_HANDSON_REPO
    API_INTEGRATION = git_api_integration_snow_am
    ORIGIN          = 'https://github.com/sfc-gh-kmotokubota/asset-management-ai-handson.git'
    COMMENT         = 'ハンズオン教材リポジトリ';

-- リポジトリの内容を取得する
ALTER GIT REPOSITORY SNOW_AM_HANDSON_REPO FETCH;

-- 中身を確認する
LS @SNOW_AM_HANDSON_REPO/branches/main;

SELECT '【Step 3】GitHub 連携の設定が完了しました' AS status;


-- ============================================================================
-- Step 4: GitHub からファイルをステージへ搬入
-- ============================================================================

-- 4-1. 決算コール PDF とニュース CSV を DOC_STAGE へ
--      COPY FILES はサブフォルダ構造を保持したままコピーします
COPY FILES
    INTO @DOC_STAGE
    FROM @SNOW_AM_HANDSON_REPO/branches/main/data/;

ALTER STAGE DOC_STAGE REFRESH;

-- 4-2. Agent skills を SKILL_STAGE へ
--      結果として @SKILL_STAGE/skills/<スキル名>/SKILL.md の階層になります
COPY FILES
    INTO @SKILL_STAGE/skills/
    FROM @SNOW_AM_HANDSON_REPO/branches/main/skills/;

ALTER STAGE SKILL_STAGE REFRESH;

-- 4-3. 搬入結果を確認する
LS @DOC_STAGE;
LS @SKILL_STAGE/ PATTERN = '.*SKILL\.md';

SELECT '【Step 4】ファイルのステージ搬入が完了しました' AS status;


-- ============================================================================
-- Step 5: Marketplace データの前提チェック
-- ============================================================================
-- Marketplace リスティングを取得したときのデータベース名は、選んだリスティングや
-- 取得時の設定によって異なります（SNOWFLAKE_PUBLIC_DATA_PAID など）。
-- 以下のブロックが、よくある別名を自動で検出して SNOWFLAKE_PUBLIC_DATA に
-- リネームします。既に目的の名前になっている場合は何もしません。
-- ============================================================================

-- 5-1. Marketplace データベース名を自動で揃える
EXECUTE IMMEDIATE $$
DECLARE
    target_db     STRING  DEFAULT 'SNOWFLAKE_PUBLIC_DATA';
    candidates    ARRAY   DEFAULT ARRAY_CONSTRUCT(
                              'SNOWFLAKE_PUBLIC_DATA_PAID',
                              'SNOWFLAKE_PUBLIC_DATA_FREE',
                              'SNOWFLAKE_PUBLIC_DATA_PRODUCTS');
    found_count   INTEGER DEFAULT 0;
    candidate_db  STRING;
    i             INTEGER DEFAULT 0;
BEGIN
    -- 目的の名前で既に存在するか確認する
    SELECT COUNT(*) INTO :found_count
    FROM SNOWFLAKE.INFORMATION_SCHEMA.DATABASES
    WHERE DATABASE_NAME = :target_db;

    IF (found_count > 0) THEN
        RETURN 'OK: ' || target_db || ' は既に存在します。リネームは不要です。';
    END IF;

    -- よくある別名を順に探し、見つかったらリネームする
    FOR i IN 0 TO ARRAY_SIZE(:candidates) - 1 DO
        candidate_db := GET(:candidates, :i)::STRING;

        SELECT COUNT(*) INTO :found_count
        FROM SNOWFLAKE.INFORMATION_SCHEMA.DATABASES
        WHERE DATABASE_NAME = :candidate_db;

        IF (found_count > 0) THEN
            EXECUTE IMMEDIATE 'ALTER DATABASE ' || :candidate_db
                              || ' RENAME TO ' || :target_db;
            RETURN 'リネームしました: ' || candidate_db || ' -> ' || target_db;
        END IF;
    END FOR;

    RETURN 'NG: Marketplace のデータベースが見つかりません。'
           || 'Snowsight の Data Products » Marketplace から '
           || '「Snowflake Public Data (Paid)」を取得し、'
           || 'データベース名を SNOWFLAKE_PUBLIC_DATA にしてください。';
END;
$$;

-- 5-2. 株価データのカバレッジを確認する
SELECT '株価（STOCK_PRICE_TIMESERIES）' AS "データ種別",
       COUNT(*)                        AS "レコード数",
       MIN(DATE)                       AS "最古日付",
       MAX(DATE)                       AS "最新日付"
FROM SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA.STOCK_PRICE_TIMESERIES
WHERE TICKER IN ('NVDA','MSFT','AAPL','GOOGL','AMZN','META','AVGO','TSLA','JPM','XOM');

-- 5-3. SEC 財務データのカバレッジを確認する（NVDA）
--      2026-04-26（Q1 FY2027）が含まれていれば、決算コールとの突合シナリオが成立します
SELECT 'SEC財務（NVDA）'   AS "データ種別",
       COUNT(*)            AS "レコード数",
       MAX(PERIOD_END_DATE) AS "最新期末日"
FROM SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA.SEC_REPORT_ATTRIBUTES
WHERE CIK = '0001045810' AND COVERED_QTRS = 1;

SELECT '【Step 5】Marketplace データの前提チェックが完了しました' AS status;


-- ============================================================================
-- Step 6: Marketplace データのキュレーション
-- ============================================================================
-- Marketplace の主要ビューは縦持ち（VARIABLE / VALUE）です。
-- そのまま Cortex Analyst に渡すと精度が出ないため、横持ちの分析用テーブルに整形します。
--
-- ⚠️ 実行に1〜2分かかります。
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 6-1. 銘柄マスタ（DIM_SECURITY）- 米国大型株10銘柄
-- ----------------------------------------------------------------------------
-- COMPANY_CHARACTERISTICS は縦持ちなので、必要な属性だけをピボットして取り出します。
-- RELATIONSHIP_END_DATE IS NULL で「現在有効な属性」に絞ります。
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_SECURITY AS
WITH base AS (
    SELECT ci.COMPANY_ID,
           ci.CIK,
           ci.PRIMARY_TICKER        AS TICKER,
           ci.COMPANY_NAME,
           ci.PRIMARY_EXCHANGE_NAME AS EXCHANGE,
           MAX(CASE WHEN cc.RELATIONSHIP_TYPE = 'sic_description' THEN cc.VALUE END) AS SIC_DESCRIPTION
    FROM SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA.COMPANY_INDEX ci
    LEFT JOIN SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA.COMPANY_CHARACTERISTICS cc
           ON ci.COMPANY_ID = cc.COMPANY_ID
          AND cc.RELATIONSHIP_END_DATE IS NULL
    WHERE ci.PRIMARY_TICKER IN ('NVDA','MSFT','AAPL','GOOGL','AMZN','META','AVGO','TSLA','JPM','XOM')
      AND ci.ENTITY_LEVEL = 'Corporate'
    GROUP BY 1, 2, 3, 4, 5
),
-- 日本語のセクター名とわかりやすい企業名は、ハンズオンの可読性のために付与します
sector_ja AS (
    SELECT * FROM VALUES
        ('NVDA',  '半導体',           'エヌビディア'),
        ('AVGO',  '半導体',           'ブロードコム'),
        ('MSFT',  'ソフトウェア',     'マイクロソフト'),
        ('AAPL',  'ハードウェア',     'アップル'),
        ('GOOGL', 'インターネット',   'アルファベット'),
        ('META',  'インターネット',   'メタ・プラットフォームズ'),
        ('AMZN',  'Eコマース',        'アマゾン・ドット・コム'),
        ('TSLA',  '自動車',           'テスラ'),
        ('JPM',   '金融',             'JPモルガン・チェース'),
        ('XOM',   'エネルギー',       'エクソンモービル')
    AS t(TICKER, SECTOR, COMPANY_NAME_JA)
)
SELECT b.COMPANY_ID,
       b.CIK,
       b.TICKER,
       b.COMPANY_NAME,
       s.COMPANY_NAME_JA,
       s.SECTOR,
       b.SIC_DESCRIPTION,
       b.EXCHANGE
FROM base b
JOIN sector_ja s ON b.TICKER = s.TICKER;

COMMENT ON TABLE DIM_SECURITY IS '銘柄マスタ。米国大型株10銘柄のティッカー・企業名・セクター・上場市場を管理';


-- ----------------------------------------------------------------------------
-- 6-2. 日次株価（FACT_STOCK_PRICE_DAILY）- 縦持ちから横持ちへピボット
-- ----------------------------------------------------------------------------
-- STOCK_PRICE_TIMESERIES の VARIABLE には以下の値が入っています。
--   pre-market_open / all-day_high / all-day_low / post-market_close / nasdaq_volume
-- 1銘柄1日あたり9行に分かれているため、CASE 式でピボットして1行にまとめます。
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_STOCK_PRICE_DAILY AS
SELECT TICKER,
       DATE AS TRADE_DATE,
       MAX(CASE WHEN VARIABLE = 'pre-market_open'   THEN VALUE END) AS OPEN_PRICE,
       MAX(CASE WHEN VARIABLE = 'all-day_high'      THEN VALUE END) AS HIGH_PRICE,
       MAX(CASE WHEN VARIABLE = 'all-day_low'       THEN VALUE END) AS LOW_PRICE,
       MAX(CASE WHEN VARIABLE = 'post-market_close' THEN VALUE END) AS CLOSE_PRICE,
       MAX(CASE WHEN VARIABLE = 'nasdaq_volume'     THEN VALUE END) AS VOLUME
FROM SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA.STOCK_PRICE_TIMESERIES
WHERE TICKER IN (SELECT TICKER FROM DIM_SECURITY)
  AND DATE >= DATEADD('year', -3, CURRENT_DATE())
GROUP BY ALL;

COMMENT ON TABLE FACT_STOCK_PRICE_DAILY IS '日次株価。始値・高値・安値・終値・出来高を銘柄×取引日で保持（直近3年分）';


-- ----------------------------------------------------------------------------
-- 6-3. 四半期財務諸表（FACT_FINANCIAL_METRICS）
-- ----------------------------------------------------------------------------
-- ⚠️ ここが最も注意が必要な処理です。
--
-- SEC_REPORT_ATTRIBUTES は SEC 提出書類の XBRL 全項目を保持しており、
-- セグメント別・地域別のファクトも同じテーブルに混在しています。
-- 以下の3つのフィルタを1つでも外すと数値が壊れます（営業利益が売上を超えるなど）。
--
--   COVERED_QTRS = 1              単四半期のみ（累計値を除外）
--   METADATA IS NULL              ★連結（非セグメント）ファクトのみ。これが最重要
--   STATEMENT = 'Income Statement' 損益計算書の項目のみ
--
-- さらに、修正再提出により同一期に複数の ADSH が存在するため、
-- FILED_DATE の降順で最新のものを採用します。
--
-- また、売上の XBRL タグは企業によって異なります。
--   Revenues                                            → NVDA, GOOGL, XOM
--   RevenueFromContractWithCustomerExcludingAssessedTax  → AAPL, AMZN, AVGO, META, MSFT, TSLA
--   （JPM は両方とも使用しておらず、売上は NULL になります。金融業は売上概念が異なるためです）
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_FINANCIAL_METRICS AS
WITH attr AS (
    SELECT s.TICKER,
           a.PERIOD_END_DATE,
           a.TAG,
           TRY_TO_DOUBLE(a.VALUE) AS VAL,
           i.FILED_DATE,
           ROW_NUMBER() OVER (PARTITION BY s.TICKER, a.PERIOD_END_DATE, a.TAG
                              ORDER BY i.FILED_DATE DESC) AS RN
    FROM SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA.SEC_REPORT_ATTRIBUTES a
    JOIN SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA.SEC_REPORT_INDEX i ON a.ADSH = i.ADSH
    JOIN DIM_SECURITY s                                       ON a.CIK  = s.CIK
    WHERE a.COVERED_QTRS = 1              -- 単四半期のみ
      AND a.METADATA IS NULL              -- 連結（非セグメント）ファクトのみ
      AND a.STATEMENT = 'Income Statement'
      AND a.PERIOD_END_DATE >= DATEADD('year', -3, CURRENT_DATE())
      AND a.TAG IN ('Revenues',
                    'RevenueFromContractWithCustomerExcludingAssessedTax',
                    'GrossProfit',
                    'OperatingIncomeLoss',
                    'NetIncomeLoss',
                    'ProfitLoss',
                    'EarningsPerShareDiluted',
                    'ResearchAndDevelopmentExpense')
)
SELECT TICKER,
       PERIOD_END_DATE,
       YEAR(PERIOD_END_DATE) || '-Q' || QUARTER(PERIOD_END_DATE) AS FISCAL_QUARTER_LABEL,
       MAX(FILED_DATE) AS FILED_DATE,
       COALESCE(MAX(CASE WHEN TAG = 'Revenues' THEN VAL END),
                MAX(CASE WHEN TAG = 'RevenueFromContractWithCustomerExcludingAssessedTax' THEN VAL END)
       ) AS REVENUE,
       MAX(CASE WHEN TAG = 'GrossProfit'         THEN VAL END) AS GROSS_PROFIT,
       MAX(CASE WHEN TAG = 'OperatingIncomeLoss' THEN VAL END) AS OPERATING_INCOME,
       COALESCE(MAX(CASE WHEN TAG = 'NetIncomeLoss' THEN VAL END),
                MAX(CASE WHEN TAG = 'ProfitLoss'    THEN VAL END)
       ) AS NET_INCOME,
       MAX(CASE WHEN TAG = 'EarningsPerShareDiluted'       THEN VAL END) AS EPS_DILUTED,
       MAX(CASE WHEN TAG = 'ResearchAndDevelopmentExpense' THEN VAL END) AS RND_EXPENSE
FROM attr
WHERE RN = 1
GROUP BY 1, 2, 3;

COMMENT ON TABLE FACT_FINANCIAL_METRICS IS 'SEC提出書類ベースの四半期財務諸表。売上・粗利・営業利益・純利益・希薄化後EPS・研究開発費を保持';


-- ----------------------------------------------------------------------------
-- 6-4. 為替レート（FACT_FX_RATE）- USD/JPY
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_FX_RATE AS
SELECT DATE  AS RATE_DATE,
       'USDJPY' AS CURRENCY_PAIR,
       VALUE AS FX_RATE
FROM SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA.FX_RATES_TIMESERIES
WHERE VARIABLE = 'usd_jpy'
  AND DATE >= DATEADD('year', -3, CURRENT_DATE());

COMMENT ON TABLE FACT_FX_RATE IS '為替レート。USD/JPY の日次レート（直近3年分）';


-- ----------------------------------------------------------------------------
-- 6-5. 米国債イールド（FACT_TREASURY_YIELD）- 10年債
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_TREASURY_YIELD AS
SELECT DATE  AS YIELD_DATE,
       '10Y' AS MATURITY,
       VALUE AS YIELD_PCT
FROM SNOWFLAKE_PUBLIC_DATA.PUBLIC_DATA.US_TREASURY_TIMESERIES
WHERE VARIABLE = 'treasury_par_yield_curve_rate_10_yr_maturity'
  AND DATE >= DATEADD('year', -3, CURRENT_DATE());

COMMENT ON TABLE FACT_TREASURY_YIELD IS '米国債イールド。10年債の日次パーイールドカーブレート（直近3年分）';


-- ----------------------------------------------------------------------------
-- 6-6. キュレーション結果の健全性チェック
-- ----------------------------------------------------------------------------
-- 「粗利 > 売上」「営業利益 > 売上」の行が存在しないことを確認します。
-- ここで行が返ってきた場合は、6-3 の METADATA IS NULL フィルタが効いていません。
-- ----------------------------------------------------------------------------
SELECT COUNT(*) AS "異常行数（0件であれば正常）"
FROM FACT_FINANCIAL_METRICS
WHERE GROSS_PROFIT > REVENUE
   OR OPERATING_INCOME > REVENUE;

-- NVDA の直近四半期を確認する（決算コール PDF の記述と突き合わせます）
SELECT TICKER            AS "銘柄",
       PERIOD_END_DATE   AS "期末日",
       ROUND(REVENUE          / 1e6) AS "売上（百万ドル）",
       ROUND(GROSS_PROFIT     / 1e6) AS "粗利（百万ドル）",
       ROUND(OPERATING_INCOME / 1e6) AS "営業利益（百万ドル）",
       ROUND(NET_INCOME       / 1e6) AS "純利益（百万ドル）",
       EPS_DILUTED                   AS "希薄化後EPS"
FROM FACT_FINANCIAL_METRICS
WHERE TICKER = 'NVDA'
ORDER BY PERIOD_END_DATE DESC
LIMIT 4;

SELECT '【Step 6】Marketplace データのキュレーションが完了しました' AS status;


-- ============================================================================
-- Step 7: 自社ファンドのダミーデータ生成
-- ============================================================================
-- スノーアセットマネジメントが運用する3ファンドの保有明細を作成します。
-- 保有時価は FACT_STOCK_PRICE_DAILY の最新終値から算出するため、
-- 実際の株価と整合したデータになります。
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 7-1. ファンドマスタ（DIM_FUND）
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_FUND (
    FUND_ID         VARCHAR(10) PRIMARY KEY,
    FUND_NAME       VARCHAR(100),
    FUND_TYPE       VARCHAR(50),
    INVESTMENT_STYLE VARCHAR(50),
    BASE_CURRENCY   VARCHAR(3),
    INCEPTION_DATE  DATE
);

INSERT INTO DIM_FUND (FUND_ID, FUND_NAME, FUND_TYPE, INVESTMENT_STYLE, BASE_CURRENCY, INCEPTION_DATE)
VALUES
    ('F001', 'スノー・グローバルAI成長株ファンド', '株式投信', 'グロース',   'USD', '2021-04-01'),
    ('F002', 'スノー・米国テクノロジー・フォーカス', '株式投信', 'グロース',   'USD', '2022-10-01'),
    ('F003', 'スノー・バランス型世界株ファンド',   '株式投信', 'コア',       'USD', '2020-01-15');

COMMENT ON TABLE DIM_FUND IS 'ファンドマスタ。スノーアセットマネジメント（架空）が運用する3ファンドの属性情報';


-- ----------------------------------------------------------------------------
-- 7-2. ファンド保有明細（FACT_FUND_HOLDING）
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_FUND_HOLDING AS
WITH shares AS (
    SELECT * FROM VALUES
        -- F001: グローバルAI成長株ファンド（AI関連に集中）
        ('F001', 'NVDA',  185000),
        ('F001', 'MSFT',  120000),
        ('F001', 'GOOGL',  95000),
        ('F001', 'AVGO',   68000),
        ('F001', 'META',   52000),
        ('F001', 'AMZN',   88000),
        -- F002: 米国テクノロジー・フォーカス
        ('F002', 'NVDA',  142000),
        ('F002', 'AAPL',  160000),
        ('F002', 'MSFT',   74000),
        ('F002', 'AVGO',   41000),
        ('F002', 'TSLA',   58000),
        -- F003: バランス型世界株ファンド（10銘柄に分散）
        ('F003', 'NVDA',   64000),
        ('F003', 'MSFT',   58000),
        ('F003', 'AAPL',   72000),
        ('F003', 'GOOGL',  46000),
        ('F003', 'AMZN',   51000),
        ('F003', 'META',   28000),
        ('F003', 'AVGO',   22000),
        ('F003', 'TSLA',   31000),
        ('F003', 'JPM',    84000),
        ('F003', 'XOM',    97000)
    AS t(FUND_ID, TICKER, SHARES)
),
-- 銘柄ごとの最新の有効な終値を取得する
latest_price AS (
    SELECT TICKER, TRADE_DATE, CLOSE_PRICE
    FROM FACT_STOCK_PRICE_DAILY
    WHERE CLOSE_PRICE IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY TICKER ORDER BY TRADE_DATE DESC) = 1
),
valued AS (
    SELECT s.FUND_ID,
           s.TICKER,
           s.SHARES,
           p.TRADE_DATE                        AS VALUATION_DATE,
           p.CLOSE_PRICE,
           ROUND(s.SHARES * p.CLOSE_PRICE, 2)  AS MARKET_VALUE
    FROM shares s
    JOIN latest_price p ON s.TICKER = p.TICKER
)
SELECT FUND_ID,
       TICKER,
       SHARES,
       VALUATION_DATE,
       CLOSE_PRICE,
       MARKET_VALUE,
       ROUND(100.0 * MARKET_VALUE / SUM(MARKET_VALUE) OVER (PARTITION BY FUND_ID), 2) AS WEIGHT_PCT
FROM valued;

COMMENT ON TABLE FACT_FUND_HOLDING IS 'ファンド保有明細。ファンド×銘柄の保有株数・評価日・終値・保有時価・ファンド内構成比を保持';


-- ----------------------------------------------------------------------------
-- 7-3. 生成結果を確認する
-- ----------------------------------------------------------------------------
SELECT f.FUND_NAME                          AS "ファンド名",
       COUNT(*)                             AS "保有銘柄数",
       ROUND(SUM(h.MARKET_VALUE))           AS "保有時価合計（ドル）",
       MAX(h.VALUATION_DATE)                AS "評価日"
FROM FACT_FUND_HOLDING h
JOIN DIM_FUND f ON h.FUND_ID = f.FUND_ID
GROUP BY f.FUND_NAME
ORDER BY 3 DESC;

SELECT '【Step 7】自社ファンドのダミーデータ生成が完了しました' AS status;


-- ============================================================================
-- Step 8: Snowflake CoWork オブジェクトの作成
-- ============================================================================
-- Snowflake CoWork から Agent を利用するために必要なオブジェクトを作成します。
-- 既に存在する場合はそのまま利用されます。
-- ============================================================================

CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

SELECT '【Step 8】Snowflake CoWork オブジェクトの作成が完了しました' AS status;


-- ============================================================================
-- 全テーブルの件数確認
-- ============================================================================

SELECT 'DIM_SECURITY'            AS "テーブル", COUNT(*) AS "件数", '銘柄マスタ'               AS "内容" FROM DIM_SECURITY
UNION ALL SELECT 'DIM_FUND',                COUNT(*), 'ファンドマスタ'                          FROM DIM_FUND
UNION ALL SELECT 'FACT_FUND_HOLDING',       COUNT(*), 'ファンド保有明細'                        FROM FACT_FUND_HOLDING
UNION ALL SELECT 'FACT_STOCK_PRICE_DAILY',  COUNT(*), '日次株価（3年分）'                       FROM FACT_STOCK_PRICE_DAILY
UNION ALL SELECT 'FACT_FINANCIAL_METRICS',  COUNT(*), '四半期財務諸表'                          FROM FACT_FINANCIAL_METRICS
UNION ALL SELECT 'FACT_FX_RATE',            COUNT(*), '為替（USD/JPY）'                         FROM FACT_FX_RATE
UNION ALL SELECT 'FACT_TREASURY_YIELD',     COUNT(*), '米国債イールド（10年）'                  FROM FACT_TREASURY_YIELD
ORDER BY 1;


-- ============================================================================
-- セットアップ完了
-- ============================================================================

SELECT '
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 環境セットアップが完了しました
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 [完了] データベース      : SNOW_AM_DB
 [完了] スキーマ          : MARKET_INTELLIGENCE
 [完了] ウェアハウス      : SNOW_AM_WH
 [完了] ステージ          : DOC_STAGE（PDF・CSV）/ SKILL_STAGE（Agent skills）
 [完了] GitHub 連携       : SNOW_AM_HANDSON_REPO
 [完了] キュレーション    : 銘柄・株価・財務・為替・金利
 [完了] ダミーデータ      : ファンド3本・保有明細21件
 [完了] Snowflake CoWork  : SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT

【次のステップ】
 1. Workspaces に Git リポジトリを追加する
    URL: https://github.com/sfc-gh-kmotokubota/asset-management-ai-handson.git
    API integration: git_api_integration_snow_am

 2. part1_ai_functions.ipynb を開く
    ウェアハウスは SNOW_AM_WH を選択してください

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
' AS "セットアップ完了";
