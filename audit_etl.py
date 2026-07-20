#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
不正ログイン監査 ETLバッチ
CloudTrailログ → Athenaクエリ → データ整形 → Redshift COPY → 集計更新
実行: 毎日05:00JST (cron)
"""

import boto3
import sys
import logging
import os
import time
from datetime import datetime, timedelta
from io import BytesIO

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import redshift_connector

# ============================================
# 設定読み込み
# ============================================
CONFIG = {
    'project_name': os.environ.get('PROJECT_NAME', 'login-audit'),
    'environment': os.environ.get('ENVIRONMENT', 'audit'),
    'athena_workgroup': os.environ.get('ATHENA_WORKGROUP', ''),
    'athena_database': os.environ.get('ATHENA_DATABASE', ''),
    's3_stage_bucket': os.environ.get('S3_STAGE_BUCKET', ''),
    'cloudtrail_bucket': os.environ.get('CLOUDTRAIL_BUCKET', ''),
    'redshift_endpoint': os.environ.get('REDSHIFT_ENDPOINT', ''),
    'redshift_database': os.environ.get('REDSHIFT_DATABASE', 'audit'),
    'redshift_schema': 'audit',
    'redshift_username': os.environ.get('REDSHIFT_USERNAME', 'audit_admin'),
    'redshift_password': os.environ.get('REDSHIFT_PASSWORD', ''),
    'region': os.environ.get('AWS_REGION', 'ap-northeast-1'),
    # 深夜判定時間範囲(パラメータ化)
    'nighttime_start': int(os.environ.get('NIGHTTIME_START', '22')),
    'nighttime_end': int(os.environ.get('NIGHTTIME_END', '6')),
}

JOB_ID = f"ETL-{datetime.now().strftime('%Y%m%d')}-{os.getpid():06d}"
TARGET_DATE = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
YEAR, MONTH, DAY = TARGET_DATE.split('-')

# ============================================
# ログ設定
# ============================================
LOG_DIR = '/var/log/audit-etl'
os.makedirs(LOG_DIR, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(f'{LOG_DIR}/{JOB_ID}.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('AuditETL')

# ============================================
# Athena クエリ (深夜時間パラメータ化)
# ============================================
ATHENA_QUERY = """
WITH login_events AS (
    SELECT
        eventtime,
        useridentity.accountid AS account_id,
        useridentity.arn AS user_arn,
        COALESCE(useridentity.username, useridentity.principalid) AS username,
        useridentity.type AS identity_type,
        sourceipaddress AS source_ip,
        useragent,
        awsregion,
        CASE WHEN errorcode IS NULL THEN 'SUCCESS' ELSE 'FAILURE' END AS login_result,
        errorcode,
        errormessage,
        useridentity.sessioncontext.attributes.mfaauthenticated AS mfa_authenticated,
        DATE_ADD('hour', 9, FROM_ISO8601_TIMESTAMP(eventtime)) AS eventtime_jst
    FROM {database}.cloudtrail_console_login
    WHERE year = '{year}'
      AND month = '{month}'
      AND day = '{day}'
      AND eventname = 'ConsoleLogin'
),
anomaly_detection AS (
    SELECT *,
        CASE WHEN (
            {nighttime_start} <= {nighttime_end} 
            AND EXTRACT(HOUR FROM eventtime_jst) BETWEEN {nighttime_start} AND {nighttime_end}
        ) OR (
            {nighttime_start} > {nighttime_end}
            AND (
                EXTRACT(HOUR FROM eventtime_jst) >= {nighttime_start}
                OR EXTRACT(HOUR FROM eventtime_jst) <= {nighttime_end}
            )
        ) THEN TRUE ELSE FALSE END AS is_nighttime_access,
        CASE WHEN awsregion != 'ap-northeast-1' THEN TRUE ELSE FALSE END AS is_overseas_access,
        CASE WHEN mfa_authenticated != 'true' THEN TRUE ELSE FALSE END AS is_mfa_missing,
        COUNT(*) OVER (PARTITION BY source_ip, DATE(eventtime_jst)
                       ORDER BY eventtime
                       RANGE BETWEEN INTERVAL '1' HOUR PRECEDING AND CURRENT ROW) AS failure_count_1h,
        DATE_DIFF('day',
            LAG(eventtime_jst) OVER (PARTITION BY username ORDER BY eventtime_jst),
            eventtime_jst) AS days_since_last_login
    FROM login_events
)
SELECT
    DATE(eventtime_jst) AS audit_date,
    account_id,
    username,
    identity_type,
    source_ip,
    useragent,
    awsregion,
    login_result,
    errorcode,
    mfa_authenticated,
    is_nighttime_access,
    is_overseas_access,
    is_mfa_missing,
    CASE WHEN failure_count_1h >= 5 THEN TRUE ELSE FALSE END AS is_brute_force,
    CASE WHEN days_since_last_login IS NULL OR days_since_last_login > 30
         THEN TRUE ELSE FALSE END AS is_rare_login,
    (CASE WHEN is_nighttime_access THEN 25 ELSE 0 END +
     CASE WHEN is_overseas_access THEN 20 ELSE 0 END +
     CASE WHEN is_mfa_missing THEN 25 ELSE 0 END +
     CASE WHEN failure_count_1h >= 5 THEN 20 ELSE 0 END +
     CASE WHEN days_since_last_login IS NULL OR days_since_last_login > 30 THEN 10 ELSE 0 END
    ) AS risk_score,
    eventtime_jst AS created_at
FROM anomaly_detection
WHERE login_result = 'SUCCESS' OR failure_count_1h >= 5
"""

# ============================================
# ユーティリティ関数
# ============================================
def run_athena_query(query, output_location):
    """Athenaクエリ実行・完了待ち"""
    client = boto3.client('athena', region_name=CONFIG['region'])

    logger.info(f"Athenaクエリ開始: {CONFIG['athena_workgroup']}")
    response = client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={'Database': CONFIG['athena_database']},
        ResultConfiguration={
            'OutputLocation': output_location,
            'EncryptionConfiguration': {'EncryptionOption': 'SSE_S3'}
        },
        WorkGroup=CONFIG['athena_workgroup']
    )

    execution_id = response['QueryExecutionId']
    logger.info(f"Execution ID: {execution_id}")

    for _ in range(360):
        status = client.get_query_execution(QueryExecutionId=execution_id)
        state = status['QueryExecution']['Status']['State']

        if state == 'SUCCEEDED':
            bytes_scanned = status['QueryExecution']['Statistics'].get('DataScannedInBytes', 0)
            logger.info(f"Athena成功: {bytes_scanned/1024/1024:.2f} MB scanned")
            return execution_id
        elif state in ['FAILED', 'CANCELLED']:
            reason = status['QueryExecution']['Status'].get('StateChangeReason', 'Unknown')
            raise Exception(f"Athena失敗: {reason}")

        time.sleep(5)

    client.stop_query_execution(QueryExecutionId=execution_id)
    raise Exception("Athenaタイムアウト(30分)")


def csv_to_parquet(s3_csv_path, s3_parquet_path):
    """Athena結果CSVをParquetに変換"""
    s3 = boto3.client('s3', region_name=CONFIG['region'])

    logger.info(f"CSV→Parquet変換: {s3_csv_path}")

    bucket, key = s3_csv_path.replace('s3://', '').split('/', 1)
    response = s3.get_object(Bucket=bucket, Key=key)
    df = pd.read_csv(response['Body'])

    record_count = len(df)
    logger.info(f"CSVレコード数: {record_count}")

    if record_count == 0:
        logger.warning("レコード0件、処理スキップ")
        return 0

    df['audit_date'] = pd.to_datetime(df['audit_date']).dt.date
    df['created_at'] = pd.to_datetime(df['created_at'])
    for col in ['is_nighttime_access', 'is_overseas_access', 'is_mfa_missing',
                'is_brute_force', 'is_rare_login']:
        df[col] = df[col].astype(bool)
    df['risk_score'] = df['risk_score'].astype(int)

    table = pa.Table.from_pandas(df)
    buf = BytesIO()
    pq.write_table(table, buf, compression='zstd')

    stage_bucket, stage_key = s3_parquet_path.replace('s3://', '').split('/', 1)
    s3.put_object(Bucket=stage_bucket, Key=stage_key, Body=buf.getvalue(),
                  ServerSideEncryption='AES256')

    logger.info(f"Parquetアップロード完了: {len(buf.getvalue())/1024:.1f} KB")
    return record_count


def redshift_copy_and_merge(stage_count):
    """Redshift COPY + ストアドプロシージャ実行"""
    logger.info("Redshift接続開始")

    conn = redshift_connector.connect(
        host=CONFIG['redshift_endpoint'],
        database=CONFIG['redshift_database'],
        user=CONFIG['redshift_username'],
        password=CONFIG['redshift_password'],
        port=5439
    )

    try:
        cursor = conn.cursor()

        logger.info("StageテーブルTruncate")
        cursor.execute(f"TRUNCATE TABLE {CONFIG['redshift_schema']}.console_login_stage")

        parquet_path = f"s3://{CONFIG['s3_stage_bucket']}/redshift-copy/{TARGET_DATE.replace('-','')}/data.parquet"
        account_id = boto3.client('sts').get_caller_identity()['Account']

        copy_sql = f"""
        COPY {CONFIG['redshift_schema']}.console_login_stage
        FROM '{parquet_path}'
        IAM_ROLE 'arn:aws:iam::{account_id}:role/{CONFIG['project_name']}-{CONFIG['environment']}-redshift-service-role'
        FORMAT AS PARQUET
        """

        logger.info("COPY実行")
        cursor.execute(copy_sql)

        cursor.execute(f"SELECT COUNT(*) FROM {CONFIG['redshift_schema']}.console_login_stage")
        loaded = cursor.fetchone()[0]
        logger.info(f"Stageロード完了: {loaded}件")

        logger.info(f"プロシージャ実行: sp_daily_etl('{TARGET_DATE}', '{JOB_ID}')")
        cursor.execute(f"CALL {CONFIG['redshift_schema']}.sp_daily_etl(%s, %s)", 
                      (TARGET_DATE, JOB_ID))

        conn.commit()
        logger.info("Redshift処理完了")
        return loaded

    except Exception as e:
        conn.rollback()
        logger.error(f"Redshiftエラー: {e}")
        raise
    finally:
        conn.close()


# ============================================
# メイン処理
# ============================================
def main():
    start_time = datetime.now()
    logger.info(f"=== ETL開始: {JOB_ID} ===")
    logger.info(f"対象日: {TARGET_DATE}")
    logger.info(f"深夜判定: {CONFIG['nighttime_start']}時～{CONFIG['nighttime_end']}時")

    try:
        # Step 1: Athenaクエリ
        logger.info("[STEP 1] Athenaクエリ実行")
        query = ATHENA_QUERY.format(
            database=CONFIG['athena_database'],
            year=YEAR, month=MONTH, day=DAY,
            nighttime_start=CONFIG['nighttime_start'],
            nighttime_end=CONFIG['nighttime_end']
        )
        athena_output = f"s3://{CONFIG['s3_stage_bucket']}/athena-results/{TARGET_DATE}/"
        execution_id = run_athena_query(query, athena_output)

        # Step 2: CSV→Parquet変換
        logger.info("[STEP 2] データ整形")
        csv_path = f"{athena_output}{execution_id}.csv"
        parquet_path = f"s3://{CONFIG['s3_stage_bucket']}/redshift-copy/{TARGET_DATE.replace('-','')}/data.parquet"
        record_count = csv_to_parquet(csv_path, parquet_path)

        if record_count == 0:
            logger.info("処理対象0件、正常終了")
            sys.exit(0)

        # Step 3: Redshift COPY + MERGE
        logger.info("[STEP 3] Redshiftロード")
        loaded = redshift_copy_and_merge(record_count)

        elapsed = (datetime.now() - start_time).total_seconds()
        logger.info(f"=== ETL完了: {record_count}件, {elapsed:.1f}秒 ===")
        sys.exit(0)

    except Exception as e:
        elapsed = (datetime.now() - start_time).total_seconds()
        logger.error(f"=== ETL失敗: {e}, {elapsed:.1f}秒 ===")
        sys.exit(1)


if __name__ == '__main__':
    main()
