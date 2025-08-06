# ログ基盤ドキュメント

## 概要

このドキュメントでは、Rails アプリケーションに実装された包括的なログ基盤について説明します。この基盤は構造化ログ、パフォーマンス監視、エラートラッキング、AWS 統合を提供します。

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

### 5. AWS 統合

- CloudWatch Logs への自動転送
- X-Ray による分散トレーシング
- CloudWatch Alarms でのアラート

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
LOG_TO_FILE=true
LOG_TO_STDOUT=true

# AWS CloudWatch（production 環境）
AWS_REGION=ap-northeast-1
CLOUDWATCH_LOG_GROUP=/aws/rails/myapp-production
CLOUDWATCH_LOG_STREAM=rails-app-hostname

# AWS X-Ray
XRAY_ENABLED=true
XRAY_DAEMON_ADDRESS=127.0.0.1:2000
XRAY_SAMPLING_RATE=0.1
```

### Rails 設定

設定は `config/initializers/logging_infrastructure.rb` で自動的に読み込まれます。

### AWS 設定

AWS 関連の設定は `config/aws_logging.yml` で管理されます：

```yaml
production:
  cloudwatch:
    enabled: true
    log_group: /aws/rails/myapp-production
    retention_days: 30
  xray:
    enabled: true
    sampling_rate: 0.1
```

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

## CloudWatch での分析

### ログの検索

CloudWatch Logs Insights で以下のクエリを使用：

```sql
-- エラーログの検索
fields @timestamp, message, error.class, error.message
| filter level = "error"
| sort @timestamp desc

-- 特定ユーザーの活動
fields @timestamp, message, request.path, response.status
| filter user_id = 12345
| sort @timestamp desc

-- 遅いリクエストの検索
fields @timestamp, request.path, response.duration_ms
| filter response.duration_ms > 1000
| sort response.duration_ms desc

-- 相関 ID での追跡
fields @timestamp, level, message
| filter correlation_id = "req_abc123def456"
| sort @timestamp asc
```

### メトリクスフィルター

以下のメトリクスが自動的に抽出されます：

- エラー率
- 平均応答時間
- メモリ使用量
- スロークエリ数
- ジョブ失敗数

## セキュリティ考慮事項

1. **機密データの自動フィルタリング**: パスワード、トークン、クレジットカード番号などは自動的に除外
2. **アクセス制限**: CloudWatch Logs へのアクセスは IAM で制限
3. **ログの保持期間**: 本番環境では 30 日、ステージング環境では 14 日
4. **暗号化**: CloudWatch Logs は保管時に暗号化

## パフォーマンス最適化

1. **非同期ログ出力**: 高負荷時は非同期ログ出力を検討
2. **バッチング**: CloudWatch への送信はバッチ処理
3. **サンプリング**: X-Ray トレーシングは 10% サンプリング
4. **ログレベル調整**: 本番環境では info レベル以上のみ

## 今後の拡張

- Elasticsearch 統合
- カスタムダッシュボード
- 機械学習による異常検知
- ログの長期アーカイブ