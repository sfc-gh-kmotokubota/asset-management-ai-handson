/*
================================================================================
資産運用向け Snowflake AI ハンズオン - 後片付けスクリプト
================================================================================

【概要】
ハンズオンで作成したオブジェクトを削除します。

【処理内容】
  Step 1: Cortex Agent の削除
  Step 2: Cortex Search Service の削除
  Step 3: セマンティックビューの削除
  Step 4: データベースの削除（テーブル・ステージ・Git リポジトリを含む）
  Step 5: ウェアハウスの削除

【注意点】
  以下のオブジェクトはアカウント全体で共有される可能性があるため、
  意図的にコメントアウトしています。他の用途で使っていないことを確認したうえで、
  必要な場合だけコメントを外して実行してください。

  ・API INTEGRATION git_api_integration_snow_am
  ・ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION
  ・SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
  ・Marketplace から取得したデータベース SNOWFLAKE_PUBLIC_DATA

【実行方法】
  Snowsight の Workspaces に貼り付け、Run All で実行してください。
================================================================================
*/


-- ============================================================================
-- Step 1: Cortex Agent の削除
-- ============================================================================

USE ROLE ACCOUNTADMIN;

DROP AGENT IF EXISTS SNOW_AM_DB.MARKET_INTELLIGENCE.MARKET_INTELLIGENCE_AGENT;

SELECT '【Step 1】Cortex Agent を削除しました' AS status;


-- ============================================================================
-- Step 2: Cortex Search Service の削除
-- ============================================================================

DROP CORTEX SEARCH SERVICE IF EXISTS SNOW_AM_DB.MARKET_INTELLIGENCE.SEARCH_EARNINGS_CALL;
DROP CORTEX SEARCH SERVICE IF EXISTS SNOW_AM_DB.MARKET_INTELLIGENCE.SEARCH_COMPANY_NEWS;

SELECT '【Step 2】Cortex Search Service を削除しました' AS status;


-- ============================================================================
-- Step 3: セマンティックビューの削除
-- ============================================================================

DROP SEMANTIC VIEW IF EXISTS SNOW_AM_DB.MARKET_INTELLIGENCE.PORTFOLIO_MARKET_SEMANTIC_VIEW;

SELECT '【Step 3】セマンティックビューを削除しました' AS status;


-- ============================================================================
-- Step 4: データベースの削除
-- ============================================================================
-- テーブル・ステージ・Git リポジトリ・ファイルフォーマットもまとめて削除されます
-- ============================================================================

DROP DATABASE IF EXISTS SNOW_AM_DB;

SELECT '【Step 4】データベース SNOW_AM_DB を削除しました' AS status;


-- ============================================================================
-- Step 5: ウェアハウスの削除
-- ============================================================================

DROP WAREHOUSE IF EXISTS SNOW_AM_WH;

SELECT '【Step 5】ウェアハウス SNOW_AM_WH を削除しました' AS status;


-- ============================================================================
-- （任意）アカウントレベルのオブジェクト
-- ============================================================================
-- ⚠️ 以下はアカウント全体で共有される可能性があります。
--    他の用途で使っていないことを確認したうえでコメントを外してください。
-- ============================================================================

-- API 統合（他のハンズオンやデモでも使われている可能性があります）
-- DROP INTEGRATION IF EXISTS git_api_integration_snow_am;

-- クロスリージョン推論の設定（他の Cortex 利用に影響します）
-- ALTER ACCOUNT UNSET CORTEX_ENABLED_CROSS_REGION;

-- Snowflake CoWork オブジェクト（アカウントで1つだけ存在します）
-- DROP SNOWFLAKE INTELLIGENCE IF EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

-- Marketplace から取得したデータベース
-- 削除すると再取得が必要になります。データ自体は共有なのでストレージ費用はかかりません
-- DROP DATABASE IF EXISTS SNOWFLAKE_PUBLIC_DATA;


-- ============================================================================
-- 削除結果の確認
-- ============================================================================

SHOW DATABASES LIKE 'SNOW_AM_DB';
SHOW WAREHOUSES LIKE 'SNOW_AM_WH';

SELECT '
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 後片付けが完了しました
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 上の SHOW コマンドの結果が両方とも0行であれば、削除は成功しています。

 【残っているもの】
 ・API 統合 git_api_integration_snow_am
 ・クロスリージョン推論の設定
 ・Snowflake CoWork オブジェクト
 ・Marketplace のデータベース

 これらはアカウント共有物のため意図的に残しています。
 削除が必要な場合は、本スクリプト末尾のコメントを外して実行してください。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
' AS "後片付け完了";
