# ログ基盤ドキュメント

## 概要

このドキュメントでは、Rails アプリケーションに実装された包括的なログ基盤について説明します。この基盤は構造化ログ、パフォーマンス監視、エラートラッキング、Google Cloud Logging 統合を提供します。

## 主要機能

### 1. 構造化ログ

すべてのログは JSON 形式で出力され、以下の情報を含みます：

- タイムスタンプ
- ログレベル（debug, info, warn, error, fatal）
- 相関 ID
- ユーザーコンテキスト
- リクエスト情報
- パフォーマンスメトリクス

### 2. 相関 ID 追跡

各リクエストに一意の相関 ID が割り当てられ、リクエスト処理全体を通じて追跡できます。

### 3. パフォーマンス監視

- データベースクエリの実行時間
- キャッシュ操作のヒット率
- 外部 API 呼び出しの応答時間
- メモリ使用量

### 4. エラーハンドリング

- 例外の自動ログ記録
- 重要度に基づく分類
- Slack 通知
- セキュリティイベントの記録

### 5. Google Cloud Logging 統合

- Cloud Logging への自動転送（STDOUTベース）
- ログバケットによる保持期間管理
- Cloud Monitoring でのアラート
- ログエクスプローラーでの高度な検索

## 使用方法

### 基本的なログ出力

```ruby
# Rails.logger は自動的に構造化ロガーとして設定されます
Rails.logger.info("User logged in", user_id: user.id, ip: request.remote_ip)
Rails.logger.error("Payment failed", error: e.message, amount: 1000)
```

### コントローラーでの使用

```ruby
class UsersController < ApplicationController
  def create
    # ログコンテキストは自動的に設定されます
    @user = User.new(user_params)
    
    if @user.save
      Rails.logger.info("User created", user_id: @user.id)
      redirect_to @user
    else
      Rails.logger.warn("User creation failed", errors: @user.errors.full_messages)
      render :new
    end
  end
end
```

### バックグラウンドジョブでの使用

```ruby
class ProcessPaymentJob < ApplicationJob
  # JobLogger が自動的に含まれます
  
  def perform(payment_id)
    payment = Payment.find(payment_id)
    # 相関 ID は自動的に継承されます
    
    Rails.logger.info("Processing payment", payment_id: payment.id)
    
    # ジョブの実行は自動的にログに記録されます
    payment.process!
  end
end
```

### パフォーマンス監視

```ruby
# データベースクエリは自動的に追跡されます
User.where(active: true).each do |user|
  # N+1 クエリは警告としてログに記録されます
end

# 外部 API 呼び出しの追跡
LoggingInfrastructure::PerformanceMonitor.track_external_api_call(
  "https://api.example.com/users",
  :post,
  response_time_ms,
  response.code
)
```

### エラーハンドリング

```ruby
begin
  dangerous_operation
rescue => e
  # 例外は自動的にログに記録され、必要に応じて Slack 通知が送信されます
  LoggingInfrastructure::ErrorHandler.handle_exception(e, {
    user_id: current_user.id,
    operation: 'dangerous_operation'
  })
  
  # または、通常の raise でも自動的に捕捉されます
  raise
end
```

### セキュリティイベント

```ruby
# 認証失敗の記録
LoggingInfrastructure::ErrorHandler.log_security_event(
  :authentication_failure,
  { username: params[:username], ip: request.remote_ip }
)

# 疑わしいアクティビティの記録
LoggingInfrastructure::ErrorHandler.log_suspicious_activity(
  user.id,
  :multiple_failed_logins,
  { attempts: 5, duration: '5 minutes' }
)
```

## 設定

### 環境変数

```bash
# ログレベル（production 環境のみ）
LOG_LEVEL=info

# ログ出力先
LOG_TO_FILE=true        # 開発環境のみ有効
LOG_TO_STDOUT=true      # 本番環境はデフォルトでSTDOUT

# 本番環境（Cloud Run）
# STDOUTへの出力のみ使用し、Google Cloud Loggingが自動収集
RAILS_ENV=production
```

### Rails 設定

設定は `config/initializers/logging_infrastructure.rb` で自動的に読み込まれます。

### Cloud Run 環境での動作

本番環境（Cloud Run）では以下の仕組みでログを管理します:

```
Rails App → STDOUT → Cloud Run Runtime → Google Cloud Logging
```

**特徴**:
- ログローテーション不要（Cloud Loggingで自動管理）
- ファイルシステムへの書き込み不要（コンテナは一時的）
- ログ保持期間はCloud Loggingのログバケット設定で管理
- ログ検索・分析はCloud Consoleで実施

## ログフォーマット

### 標準ログエントリ

```json
{
  "timestamp": "2025-01-08T10:30:00.123Z",
  "level": "info",
  "message": "Request completed",
  "correlation_id": "req_abc123def456",
  "user_id": 12345,
  "session_id": "sess_xyz789",
  "request": {
    "method": "POST",
    "path": "/api/users",
    "ip": "192.168.1.100"
  },
  "response": {
    "status": 201,
    "duration_ms": 245.67
  },
  "environment": "production",
  "service": "rails-app",
  "hostname": "web-001"
}
```

### エラーログエントリ

```json
{
  "timestamp": "2025-01-08T10:30:00.123Z",
  "level": "error",
  "message": "Exception occurred",
  "correlation_id": "req_abc123def456",
  "error": {
    "class": "StandardError",
    "message": "Something went wrong",
    "backtrace": ["app/controllers/users_controller.rb:10"],
    "fingerprint": "abc123..."
  },
  "severity": "high",
  "alert_sent": true
}
```

## トラブルシューティング

### ログが出力されない

1. ログレベルを確認：`Rails.logger.level`
2. 出力先を確認：`Rails.logger.output`
3. ミドルウェアが正しく登録されているか確認

### 相関 ID が設定されない

1. RequestMiddleware が正しく登録されているか確認
2. `rails middleware` コマンドで確認

### Slack 通知が送信されない

1. credentials に Slack webhook URL が設定されているか確認
2. エラーの重要度が通知閾値を超えているか確認
3. レート制限（5 分間の重複制限）に引っかかっていないか確認

### パフォーマンスが低下する

1. ログレベルを上げる（debug → info）
2. 不要なメタデータを減らす
3. ログローテーションを確認

## ベストプラクティス

### 1. 適切なログレベルの使用

- **DEBUG**: 詳細なデバッグ情報
- **INFO**: 通常の処理フロー
- **WARN**: 潜在的な問題
- **ERROR**: エラーだが処理は継続
- **FATAL**: アプリケーションが停止する重大なエラー

### 2. 構造化データの活用

```ruby
# 良い例
Rails.logger.info("Order processed", {
  order_id: order.id,
  user_id: user.id,
  amount: order.total,
  items_count: order.items.count
})

# 悪い例
Rails.logger.info("Order #{order.id} processed for user #{user.id}")
```

### 3. 機密情報の取り扱い

機密情報は自動的にフィルタリングされますが、追加の注意が必要です：

```ruby
# パスワードなどは自動的にフィルタリング
Rails.logger.info("User login", {
  email: user.email,
  password: params[:password] # [FILTERED] として記録される
})
```

### 4. パフォーマンスメトリクスの活用

```ruby
# 重要な処理の前後で測定
start_time = Time.current
expensive_operation
duration = Time.current - start_time

Rails.logger.info("Operation completed", {
  operation: "expensive_operation",
  duration_ms: (duration * 1000).round(2)
})
```

## Google Cloud Logging での分析

### ログの確認

```bash
# 基本的なログ取得
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="app-base"' \
  --limit=100 \
  --format=json

# エラーログのみ
gcloud logging read \
  'resource.type="cloud_run_revision" AND severity>=ERROR' \
  --limit=50

# 時間範囲指定
gcloud logging read \
  'timestamp>="2024-11-01T00:00:00Z" AND timestamp<"2024-11-02T00:00:00Z"' \
  --limit=100

# 特定ユーザーの活動
gcloud logging read \
  'jsonPayload.user_id="12345"' \
  --limit=50
```

### ログエクスプローラーでの検索

Cloud Console > Logging > ログエクスプローラー で以下のクエリを使用:

```
# エラーログの検索
resource.type="cloud_run_revision"
severity>=ERROR

# 特定パスへのリクエスト
resource.type="cloud_run_revision"
jsonPayload.request.path="/api/users"

# 遅いリクエストの検索
resource.type="cloud_run_revision"
jsonPayload.response.duration_ms>1000

# 相関IDでの追跡
resource.type="cloud_run_revision"
jsonPayload.correlation_id="req_abc123def456"
```

### メトリクスの作成

以下のメトリクスをCloud Monitoringで作成できます:

- エラー率: `severity>=ERROR` のカウント
- 平均応答時間: `jsonPayload.response.duration_ms` の平均
- リクエスト数: すべてのログエントリのカウント
- スロークエリ数: `jsonPayload.database.query_duration_ms>100` のカウント

## セキュリティ考慮事項

1. **機密データの自動フィルタリング**: パスワード、トークン、クレジットカード番号などは自動的に除外
2. **アクセス制限**: Cloud Logging へのアクセスは IAM で制限
3. **ログの保持期間**: ログバケット設定で管理（デフォルト30日）
4. **暗号化**: Cloud Logging は保管時・転送時に自動暗号化

## パフォーマンス最適化

1. **STDOUT出力**: 本番環境ではファイルI/Oを削減
2. **構造化ログ**: JSON形式で効率的な検索・分析
3. **ログレベル調整**: 本番環境では info レベル以上のみ
4. **非同期処理**: 高負荷時のログ出力の影響を最小化

## 今後の拡張

- カスタムダッシュボード（Cloud Monitoring）
- アラートポリシーの追加
- ログベースのメトリクス作成
- BigQuery へのログエクスポート（長期保存・分析）
- Error Reporting 統合