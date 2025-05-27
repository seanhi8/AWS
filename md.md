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


9. AWSリソース一覧（参考）

区分	サービス	用途	備考

サイト	CloudFront	Web表示のCDN配信	WAFと連携
サイト	WAF	セキュリティ制御	OWASP対応ルール適用
サイト	ALB	EC2ルーティング	HTTP/HTTPS対応
サイト	EC2	アプリケーションサーバ	Auto Scaling可能
サイト	S3	ログ保存	アクセスログ、404ログ
API	API Gateway	REST API公開	Lambda統合
API	Lambda	バックエンド処理	Node.js/Python想定
API	S3	コンテンツ保存	画像・ドキュメント等
API	DynamoDB	メタデータ管理	単一テーブル設計も可


AWS要件定義書（詳細版）

1. プロジェクト概要

目的：現行のWebサイトは静的/動的コンテンツが混在し、可用性・拡張性・セキュリティ面で課題が多いため、AWSを用いたモダンアーキテクチャへ再構築を行う。

開発対象：以下の3システムに分割し、役割ごとに最適なAWSサービスを選定する。

フロントエンドサイト配信（Webサイト閲覧部分）

API・コンテンツ提供システム

管理ツール（バックオフィス）


提供方式：サーバレスアーキテクチャと一部EC2により、可用性と運用性を両立。


2. サイト構成（Web閲覧）

2.1 要件定義

項目	内容

利用者	一般ユーザー（不特定多数）
想定トラフィック	月間100万PV、同時アクセス500ユーザー程度
可用性要件	99.9%以上の稼働率
応答時間	初期表示 1秒以内（CloudFrontキャッシュ利用時）
障害対策	AZ冗長構成（EC2はAutoScaling・Multi-AZ配置）
セキュリティ	WAFによる不正アクセス対策、HTTPS（ACM）必須


2.2 システム構成

CloudFront：静的コンテンツをキャッシュ配信。S3とALBをオリジンとして併用。

WAF：OWASP対応マネージドルール＋独自IPブラックリスト適用。

ALB：ルーティング（例：/api/* → API Gateway、/app/* → EC2）

EC2：Node.jsアプリケーションをホスト。Amazon Linux 2023 + NGINX。

S3：静的ファイル配置。404エラー時のログ記録を有効化。

ログ連携：CloudFront/ALBログはAthena分析を想定しParquet変換へ対応。


3. APIコンテンツ配信

3.1 要件定義

項目	内容

対象データ	JSON形式のコンテンツ、画像、音声データなど
想定API数	約20種類（GET/POST/PUT/DELETE）
応答時間	300ms以内（API Gateway+Lambda実行時間）
可用性要件	サーバレス構成による99.99%以上
スケーラビリティ	オートスケール（Lambdaによる自動処理）
データ整合性	DynamoDBのトランザクションAPIを活用


3.2 システム構成

S3：バケットはコンテンツタイプ別に分離（例：images、audio、docs）

DynamoDB：主キー構成は「PK（コンテンツID）＋SK（バージョン）」形式。GSIでカテゴリ・タグ検索対応。

Lambda：APIごとに関数を分離（1エンドポイント＝1関数）。Node.js 20実装。ステージ分離（dev/stg/prod）。

API Gateway：OpenAPI定義ベースでREST APIを構築。APIキー認証とIPレート制限を導入。

認証：内部向けAPIはIAM認証、外部向けはCognitoまたは署名付きURL利用。


4. 管理ツール

4.1 要件定義

項目	内容

利用者	社内ユーザー（最大50名）
アクセス制限	IP制限（社内固定IP）＋ID/パスワード（Cognito）
表示内容	コンテンツ管理、ユーザー管理、API実行履歴確認等
可用性要件	99%以上（業務時間内のみ）
バージョン管理	GitHub Actionsで自動デプロイ（S3）対応


4.2 システム構成

CloudFront：キャッシュ最短、Cookieベースのアクセス制限を使用

S3：React/ViteによるSPAをホスト。ルーティングはindex.html fallback対応。

認証：Cognito+CloudFront Signed URLで制限。


5. ネットワーク・セキュリティ構成

VPC構成：Publicサブネット（ALB/NAT）、Privateサブネット（EC2/Lambda）

VPCエンドポイント：S3、DynamoDBへプライベートアクセス

IAM：ロール分離（Lambda、EC2、CI/CD用）、CloudFormationスタック単位に制限

KMS：S3、DynamoDB、CloudWatch Logs暗号化用に利用

CloudTrail：すべての操作ログをS3へ保存（7年保持）


6. 運用・監視設計

CloudWatch

Lambdaメトリクス（エラー数、最大実行時間）

API Gatewayステータスコード割合（4xx/5xx）

EC2 CPU、メモリ（CW Agent）


アラーム例：

Lambdaエラー数 > 10/5分 → SNS通知

API 5xx割合 > 1% → Slack通知

EC2 CPU > 80% → AutoScalingトリガー


バックアップ：

DynamoDB：PITR + 定期オンデマンドバックアップ（毎日）

S3：バージョニング + ライフサイクル管理

EC2：EBSスナップショット（週次）



7. CI/CD・デプロイ戦略

CodeCommit/CodePipelineでGit連携

CodeBuildでSPA/Node.jsアプリをビルドしS3またはLambdaへデプロイ

CloudFormation/CDKによるIaC導入（環境別Stack管理）

ステージ分離：dev、stg、prodに分けてLambda/API/S3を個別運用


8. 非機能要件一覧

区分	要件	内容

可用性	ALB+AutoScaling、Lambda冗長構成	
拡張性	Lambda/API Gatewayにより無限スケール対応	
セキュリティ	IAM最小権限設計、WAF+IP制限	
運用性	CloudWatch + SNSによる監視通知	
保守性	CDKによる構成管理とGitによるバージョン管理	
パフォーマンス	CloudFront、DynamoDBにより高速レスポンス	


9. AWSリソース一覧（更新）

区分	サービス	用途	台数/数	備考

サイト	CloudFront	静的配信CDN	1	ALB/S3オリジン
サイト	WAF	セキュリティ	1	マネージドルール使用
サイト	ALB	負荷分散	1	パスベースルーティング
サイト	EC2	Webアプリ実行	最小2、最大10	AutoScaling設定済み
サイト	S3（ログ）	ログ保存	1	CloudFront/ALBログ保存先
API	API Gateway	API管理	1（ステージごとに分離）	OpenAPI定義管理
API	Lambda	処理関数	約20本	各エンドポイント用関数
API	S3（コンテンツ）	静的ファイル保存	3バケット	種別別（画像/音声/PDF）
API	DynamoDB	コンテンツ情報DB	1	GSI対応、PITR有効
管理	CloudFront	管理ツール配信	1	IP制限＋署名Cookie
管理	S3	管理画面ホスティング	1	SPA構成、index.html fallback
共通	IAM	権限制御	ロール6種	Lambda/EC2/CDK/CI/CD分離
共通	CloudWatch	監視・ログ管理	全体	メトリクス＋ログ収集
共通	SNS	通知	1	CloudWatchアラーム連携
共通	VPC	ネットワーク基盤	1	Public/Private分離構成
共通	KMS	暗号鍵管理	必要数	S3/DynamoDB暗号化用



---

今後は、個別機能の設計書（API定義書、画面設計書、Lambdaフロー図）等の詳細設計書を整備していく予定。必要に応じてアーキテクチャ図や通信シーケンス図も作成します。


管理	CloudFront	管理画面配信	S3オリジンSPA対応
管理	S3	管理ツールホスティング	React/Vueベース
共通	IAM	権限管理	最小権限原則で設計
共通	CloudWatch	ログとメトリクス監視	アラート含む
共通	SNS	障害通知	メール/Slack通知可能
共通	VPC/NAT GW	ネットワーク構成	セキュアアクセス分離



| リソース種別          | パラメータ設定           | 単価 (USD)            | 使用量・設定値                  | 推定日額コスト          |
| --------------- | ----------------- | ------------------- | ------------------------ | ---------------- |
| S3 ストレージ        | \$0.023 / GB / 月  | 3 バケット × 10 GB      | \$0.69 / 月 ≒ \$0.023 / 日 |                  |
| S3 リクエスト        | PUT / GET リクエスト料金 | 1000 PUT + 9000 GET | 約 \$0.0086 / 日           |                  |
| S3 転送（アウト）      | \$0.09 / GB       | 1日あたり 300 MB        | 約 \$0.027 / 日            |                  |
| Lambda 関数       | 無料枠内              | 10,000 回実行 × 512MB  | 無料 → \$0.00              |                  |
| ALB 基本料金        | \$0.0225 / 時間     | 24 時間 / 日           | 約 \$0.54 / 日             |                  |
| ALB LCU         | \$0.008 / LCU-時間  | 1 LCU × 24 時間       | 約 \$0.08 / 日             |                  |
| EC2（t2.micro）   | \$0.0116 / 時間     | 24 時間稼働             | 約 \$0.28 / 日             |                  |
| EBS（ストレージ）      | \$0.08 / GB / 月   | 30 GB               | 約 \$0.08 / 日             |                  |
| API Gateway     | \$3.5 / 100万リクエスト | 1日あたり 10,000 回      | 約 \$0.035 / 日            |                  |
| CloudFront（CDN） | \$0.085 / GB      | 1 GB / 日            | 約 \$0.085 / 日            |                  |
|                 |                   |                     |                          |                  |
| **合計（推定）**      |                   |                     |                          | **約 \$1.16 / 日** |


