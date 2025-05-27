AWS要件定義書（草案）

1. プロジェクト概要

目的：既存Webサイトにおける課題（パフォーマンス・セキュリティ・保守性）を解消するため、AWSを基盤とした再構築を行う。

システム構成：システムは以下の3つの構成要素に分かれる：

1. サイト（Web表示）


2. APIコンテンツ配信


3. 管理ツール（管理画面）




2. システム構成詳細

2.1 サイト

項目	内容

CloudFront	静的ファイルのキャッシュ配信により表示速度向上・オリジン負荷削減を実現
WAF	OWASP Top10対応、IP制限、不正アクセス対策
ALB	EC2へのリクエスト振り分け、ヘルスチェック実施
EC2	Webアプリケーションのホスティング（例：Node.js、PHP、Apacheなど）
S3	404エラー時のログ保存、アクセスログの保管等に使用


2.2 APIコンテンツ配信

コンテンツ構成

項目	内容

S3	画像、音声、ドキュメントなどの静的ファイル保存
DynamoDB	コンテンツメタデータ管理（例：ID、公開日時、カテゴリ等）


API構成

項目	内容

API Gateway	REST APIの提供、スロットリング・認証・ログ管理等対応
Lambda	APIバックエンド処理（DynamoDB検索、S3署名付きURL生成等）をサーバレスで実装


2.3 管理ツール

項目	内容

CloudFront	管理画面のキャッシュと高速化
S3	SPA（ReactやVue等）の静的ファイルホスティング


3. ネットワーク設計

東京リージョンに統一して構築

VPC配下にPublic/Privateサブネットを分離

ALBはPublic、EC2・LambdaはPrivateサブネットで構成

NAT Gateway経由でインターネットアクセス制御

各種Security Group、NACLで通信制限設定


4. セキュリティ要件

IAMロールとポリシーによるアクセス制御

Lambdaに最低限のIAM権限を付与（DynamoDB・S3アクセス）

S3バケットポリシーにより外部アクセス制御

CloudFront + WAF構成でDDoSやBot対策

必要に応じてAWS Shield導入検討


5. 監視・運用要件

CloudWatch Logs：Lambda、API Gateway、ALBのログ収集

CloudWatch Metrics：CPU、Memory、リクエスト数などをモニタリング

アラート通知：SNSを通じて障害や高負荷を即時通知

運用フロー：デプロイ、ログ調査、障害対応手順を明文化


6. バックアップ・復旧

DynamoDB：オンデマンドバックアップ有効化

S3：バージョニング＋ライフサイクルポリシー設定

EC2：EBSスナップショットによる自動バックアップ


7. コスト試算

サービス	主なコスト項目

CloudFront	リクエスト数、アウトバウンド転送量
API Gateway	API呼び出し回数
Lambda	実行時間と回数
EC2	インスタンスタイプ、起動時間
DynamoDB	読み書き容量ユニット、ストレージ容量


8. リスクと制約事項

Lambdaの最大実行時間は15分

API Gatewayのスループット制限（1秒間あたり1万RPS、上限引き上げ申請可）

DynamoDBのリードキャパシティ調整が必要なケースあり

CloudFrontのキャッシュ更新タイミングに注意


