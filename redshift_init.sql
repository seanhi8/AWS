-- ============================================
-- Redshift 初期化スクリプト
-- 不正ログイン監査基盤用
-- ============================================

-- スキーマ作成
CREATE SCHEMA IF NOT EXISTS audit;

-- ============================================
-- 1. Stageテーブル（S3 COPY先）
-- ============================================
CREATE TABLE IF NOT EXISTS audit.console_login_stage (
    audit_date          DATE,
    account_id          VARCHAR(12),
    username            VARCHAR(256),
    identity_type       VARCHAR(32),
    source_ip           VARCHAR(45),
    useragent           VARCHAR(512),
    awsregion           VARCHAR(20),
    login_result        VARCHAR(10),
    errorcode           VARCHAR(128),
    mfa_authenticated   VARCHAR(10),
    is_nighttime_access BOOLEAN,
    is_overseas_access  BOOLEAN,
    is_mfa_missing      BOOLEAN,
    is_brute_force      BOOLEAN,
    is_rare_login       BOOLEAN,
    risk_score          INT,
    created_at          TIMESTAMP
)
DISTSTYLE KEY
DISTKEY (username)
SORTKEY (audit_date, risk_score);

-- ============================================
-- 2. 本番テーブル（履歴保持）
-- ============================================
CREATE TABLE IF NOT EXISTS audit.console_login_audit (
    audit_date          DATE,
    account_id          VARCHAR(12),
    username            VARCHAR(256),
    identity_type       VARCHAR(32),
    source_ip           VARCHAR(45),
    useragent           VARCHAR(512),
    awsregion           VARCHAR(20),
    login_result        VARCHAR(10),
    errorcode           VARCHAR(128),
    mfa_authenticated   VARCHAR(10),
    is_nighttime_access BOOLEAN,
    is_overseas_access  BOOLEAN,
    is_mfa_missing      BOOLEAN,
    is_brute_force      BOOLEAN,
    is_rare_login       BOOLEAN,
    risk_score          INT,
    created_at          TIMESTAMP,
    loaded_at           TIMESTAMP DEFAULT GETDATE(),
    etl_job_id          VARCHAR(64)
)
DISTSTYLE KEY
DISTKEY (username)
SORTKEY (audit_date, risk_score)
ENCODE AUTO;

-- ============================================
-- 3. 日次集計テーブル（Dashboard用）
-- ============================================
CREATE TABLE IF NOT EXISTS audit.daily_login_summary (
    audit_date          DATE,
    account_id          VARCHAR(12),
    total_logins        INT,
    success_count       INT,
    failure_count       INT,
    mfa_missing_count   INT,
    nighttime_count     INT,
    overseas_count      INT,
    high_risk_count     INT,
    avg_risk_score      DECIMAL(5,2),
    created_at          TIMESTAMP DEFAULT GETDATE()
)
DISTSTYLE EVEN
SORTKEY (audit_date);

-- ============================================
-- 4. 異常検知履歴テーブル
-- ============================================
CREATE TABLE IF NOT EXISTS audit.anomaly_history (
    anomaly_id          BIGINT IDENTITY(1,1),
    audit_date          DATE,
    username            VARCHAR(256),
    anomaly_type        VARCHAR(32),
    risk_score          INT,
    details             VARCHAR(MAX),
    detected_at         TIMESTAMP DEFAULT GETDATE(),
    acknowledged        BOOLEAN DEFAULT FALSE,
    acknowledged_by     VARCHAR(128),
    acknowledged_at     TIMESTAMP,
    PRIMARY KEY (anomaly_id)
)
DISTSTYLE KEY
DISTKEY (username)
SORTKEY (detected_at);

-- ============================================
-- 5. ETL実行履歴テーブル
-- ============================================
CREATE TABLE IF NOT EXISTS audit.etl_job_history (
    job_id              VARCHAR(64),
    job_name            VARCHAR(128),
    start_time          TIMESTAMP,
    end_time            TIMESTAMP,
    status              VARCHAR(20),
    records_processed   INT,
    error_message       VARCHAR(MAX),
    created_at          TIMESTAMP DEFAULT GETDATE()
)
DISTSTYLE EVEN
SORTKEY (start_time);

-- ============================================
-- 6. ユーザー別統計テーブル
-- ============================================
CREATE TABLE IF NOT EXISTS audit.user_login_stats (
    username            VARCHAR(256),
    account_id          VARCHAR(12),
    first_login_date    DATE,
    last_login_date     DATE,
    total_logins        INT DEFAULT 0,
    success_count       INT DEFAULT 0,
    failure_count       INT DEFAULT 0,
    avg_risk_score      DECIMAL(5,2) DEFAULT 0,
    max_risk_score      INT DEFAULT 0,
    anomaly_count       INT DEFAULT 0,
    updated_at          TIMESTAMP DEFAULT GETDATE()
)
DISTSTYLE KEY
DISTKEY (username)
SORTKEY (username);

-- ============================================
-- 7. ビュー作成
-- ============================================

-- 7.1 高リスクログインビュー
CREATE OR REPLACE VIEW audit.v_high_risk_logins AS
SELECT
    audit_date,
    username,
    source_ip,
    awsregion,
    risk_score,
    CONCAT(
        CASE WHEN is_nighttime_access THEN '深夜帯 ' ELSE '' END,
        CASE WHEN is_overseas_access THEN '海外IP ' ELSE '' END,
        CASE WHEN is_mfa_missing THEN 'MFA未使用 ' ELSE '' END,
        CASE WHEN is_brute_force THEN 'ブルートフォース ' ELSE '' END,
        CASE WHEN is_rare_login THEN '久しぶり ' ELSE '' END
    ) AS risk_factors,
    created_at
FROM audit.console_login_audit
WHERE risk_score >= 50;

-- 7.2 日次サマリービュー
CREATE OR REPLACE VIEW audit.v_daily_summary AS
SELECT
    audit_date,
    COUNT(*) AS total_logins,
    SUM(CASE WHEN login_result = 'SUCCESS' THEN 1 ELSE 0 END) AS success_count,
    SUM(CASE WHEN login_result = 'FAILURE' THEN 1 ELSE 0 END) AS failure_count,
    SUM(CASE WHEN is_mfa_missing THEN 1 ELSE 0 END) AS mfa_missing_count,
    SUM(CASE WHEN is_nighttime_access THEN 1 ELSE 0 END) AS nighttime_count,
    SUM(CASE WHEN is_overseas_access THEN 1 ELSE 0 END) AS overseas_count,
    SUM(CASE WHEN risk_score >= 50 THEN 1 ELSE 0 END) AS high_risk_count,
    AVG(risk_score) AS avg_risk_score,
    MAX(risk_score) AS max_risk_score
FROM audit.console_login_audit
GROUP BY audit_date
ORDER BY audit_date DESC;

-- 7.3 未対応異常ビュー
CREATE OR REPLACE VIEW audit.v_unacknowledged_anomalies AS
SELECT
    anomaly_id,
    audit_date,
    username,
    anomaly_type,
    risk_score,
    details,
    detected_at,
    DATEDIFF(day, detected_at, GETDATE()) AS days_since_detected
FROM audit.anomaly_history
WHERE acknowledged = FALSE
ORDER BY detected_at DESC;

-- ============================================
-- 8. ストアドプロシージャ
-- ============================================

-- 8.1 日次ETL処理プロシージャ
CREATE OR REPLACE PROCEDURE audit.sp_daily_etl(p_audit_date DATE, p_job_id VARCHAR(64))
AS $$
BEGIN
    -- ETL履歴に開始記録
    INSERT INTO audit.etl_job_history (job_id, job_name, start_time, status)
    VALUES (p_job_id, 'DAILY_ETL', GETDATE(), 'RUNNING');

    -- 1. 本番テーブルから対象日の重複データ削除
    DELETE FROM audit.console_login_audit
    WHERE audit_date = p_audit_date
      AND username IN (SELECT username FROM audit.console_login_stage);

    -- 2. 本番テーブルへINSERT
    INSERT INTO audit.console_login_audit
    SELECT 
        s.*,
        GETDATE() AS loaded_at,
        p_job_id AS etl_job_id
    FROM audit.console_login_stage s;

    -- 3. 日次集計テーブル更新
    DELETE FROM audit.daily_login_summary WHERE audit_date = p_audit_date;

    INSERT INTO audit.daily_login_summary
    SELECT
        p_audit_date AS audit_date,
        account_id,
        COUNT(*) AS total_logins,
        SUM(CASE WHEN login_result = 'SUCCESS' THEN 1 ELSE 0 END) AS success_count,
        SUM(CASE WHEN login_result = 'FAILURE' THEN 1 ELSE 0 END) AS failure_count,
        SUM(CASE WHEN is_mfa_missing THEN 1 ELSE 0 END) AS mfa_missing_count,
        SUM(CASE WHEN is_nighttime_access THEN 1 ELSE 0 END) AS nighttime_count,
        SUM(CASE WHEN is_overseas_access THEN 1 ELSE 0 END) AS overseas_count,
        SUM(CASE WHEN risk_score >= 50 THEN 1 ELSE 0 END) AS high_risk_count,
        AVG(risk_score) AS avg_risk_score,
        GETDATE()
    FROM audit.console_login_audit
    WHERE audit_date = p_audit_date
    GROUP BY account_id;

    -- 4. 異常検知履歴登録
    INSERT INTO audit.anomaly_history (audit_date, username, anomaly_type, risk_score, details)
    SELECT 
        p_audit_date AS audit_date,
        username,
        CASE 
            WHEN is_nighttime_access THEN 'NIGHTTIME'
            WHEN is_overseas_access THEN 'OVERSEAS'
            WHEN is_mfa_missing THEN 'MFA_MISSING'
            WHEN is_brute_force THEN 'BRUTE_FORCE'
            WHEN is_rare_login THEN 'RARE_LOGIN'
        END,
        risk_score,
        JSON_SERIALIZE(
            OBJECT('source_ip', source_ip, 'awsregion', awsregion, 
                   'useragent', useragent, 'created_at', created_at)
        )
    FROM audit.console_login_audit
    WHERE audit_date = p_audit_date
      AND risk_score >= 50
      AND NOT EXISTS (
          SELECT 1 FROM audit.anomaly_history h
          WHERE h.audit_date = p_audit_date
            AND h.username = audit.console_login_audit.username
            AND h.anomaly_type = CASE 
                WHEN is_nighttime_access THEN 'NIGHTTIME'
                WHEN is_overseas_access THEN 'OVERSEAS'
                WHEN is_mfa_missing THEN 'MFA_MISSING'
                WHEN is_brute_force THEN 'BRUTE_FORCE'
                WHEN is_rare_login THEN 'RARE_LOGIN'
            END
      );

    -- 5. ユーザー統計更新
    MERGE INTO audit.user_login_stats AS target
    USING (
        SELECT
            username,
            account_id,
            MIN(audit_date) AS first_login_date,
            MAX(audit_date) AS last_login_date,
            COUNT(*) AS total_logins,
            SUM(CASE WHEN login_result = 'SUCCESS' THEN 1 ELSE 0 END) AS success_count,
            SUM(CASE WHEN login_result = 'FAILURE' THEN 1 ELSE 0 END) AS failure_count,
            AVG(risk_score) AS avg_risk_score,
            MAX(risk_score) AS max_risk_score,
            SUM(CASE WHEN risk_score >= 50 THEN 1 ELSE 0 END) AS anomaly_count
        FROM audit.console_login_audit
        WHERE audit_date = p_audit_date
        GROUP BY username, account_id
    ) AS source
    ON target.username = source.username
    WHEN MATCHED THEN
        UPDATE SET
            last_login_date = source.last_login_date,
            total_logins = target.total_logins + source.total_logins,
            success_count = target.success_count + source.success_count,
            failure_count = target.failure_count + source.failure_count,
            avg_risk_score = (target.avg_risk_score * target.total_logins + source.avg_risk_score * source.total_logins) 
                           / (target.total_logins + source.total_logins),
            max_risk_score = GREATEST(target.max_risk_score, source.max_risk_score),
            anomaly_count = target.anomaly_count + source.anomaly_count,
            updated_at = GETDATE()
    WHEN NOT MATCHED THEN
        INSERT (username, account_id, first_login_date, last_login_date, total_logins, 
                success_count, failure_count, avg_risk_score, max_risk_score, anomaly_count)
        VALUES (source.username, source.account_id, source.first_login_date, source.last_login_date,
                source.total_logins, source.success_count, source.failure_count,
                source.avg_risk_score, source.max_risk_score, source.anomaly_count);

    -- 6. VACUUM & ANALYZE
    VACUUM DELETE ONLY audit.console_login_audit TO 100;
    ANALYZE audit.console_login_audit;
    ANALYZE audit.daily_login_summary;
    ANALYZE audit.anomaly_history;

    -- ETL履歴に完了記録
    UPDATE audit.etl_job_history
    SET end_time = GETDATE(),
        status = 'SUCCESS',
        records_processed = (SELECT COUNT(*) FROM audit.console_login_audit WHERE audit_date = p_audit_date)
    WHERE job_id = p_job_id;

END;
$$ LANGUAGE plpgsql;

-- 8.2 異常確認プロシージャ
CREATE OR REPLACE PROCEDURE audit.sp_acknowledge_anomaly(
    p_anomaly_id BIGINT,
    p_acknowledged_by VARCHAR(128)
)
AS $$
BEGIN
    UPDATE audit.anomaly_history
    SET acknowledged = TRUE,
        acknowledged_by = p_acknowledged_by,
        acknowledged_at = GETDATE()
    WHERE anomaly_id = p_anomaly_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 9. 統計情報更新
-- ============================================
ANALYZE audit.console_login_stage;
ANALYZE audit.console_login_audit;
ANALYZE audit.daily_login_summary;
ANALYZE audit.anomaly_history;
ANALYZE audit.etl_job_history;
ANALYZE audit.user_login_stats;

-- 完了
SELECT 'Redshift初期化完了' AS status;
