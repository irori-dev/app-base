# AI Agent Development Guidelines

このファイルは、AI エージェント（ChatGPT、Claude、GitHub Copilot など）がこのRailsアプリケーションテンプレートで作業する際の指示とガイドラインを提供します。

## プロジェクト概要

このテンプレートは、デュアル認証システムを持つ現代的なRailsアプリケーションの基盤です。

### 技術スタック

- **Ruby 3.4.5** / **Rails 8.0.2**
- **PostgreSQL 16** (マルチデータベース構成)
- **Hotwire** (Turbo + Stimulus)
- **ViewComponent** + **Haml**
- **Tailwind CSS**
- **Solid Suite** (Cache/Queue/Cable)
- **RSpec** + **FactoryBot** + **Capybara**

## 必須の開発ルール

### 1. テスト駆動開発

- **必須**: すべてのコード変更には対応するテストが必要
- **実行順序**:
  1. コード変更
  2. `bin/rspec` でテスト実行
  3. 失敗した場合は修正して再実行
  4. すべてのテストが通るまで繰り返し

### 2. コード品質チェック

- **必須**: コード変更後は以下を順次実行
  1. `bin/rubocop` - コーディング規約チェック
  2. `bin/rubocop -a` - 自動修正可能な問題の修正
  3. `bin/brakeman` - セキュリティスキャン
  4. 問題があれば修正して再実行

### 3. データベーススキーマ管理

- **重要**: Railsマイグレーションは使用しない
- **使用ツール**: Ridgepole を使用
- **スキーマファイル**: `db/schema/` 配下の `.schema` ファイル
- **適用コマンド**: `bin/rails db:ridgepole:apply`

### 4. Docker環境での開発

- **必須**: すべてのコマンドはDockerコンテナ内で実行
- **起動**: `docker compose up` または `bin/dev`
- **コンテナ内実行**: `docker compose exec app <command>`

## コーディング規約

### ファイル構成

#### Models

- **名前空間**: `User::Core`, `User::PasswordReset` など
- **Concerns**: `app/models/concerns/` に配置
- **テーブル名**: 名前空間に対応（`user_cores`, `user_password_resets`）

#### Controllers

- **名前空間**: `Admins::`, `Users::` で分離
- **Base Controllers**: 共通処理は `BaseController` に
- **Concerns**: `app/controllers/concerns/` に配置

#### Components

- **配置**: `app/components/[namespace]/[component_name]/`
- **ファイル**: `component.rb` + `component.html.haml`
- **テスト**: `spec/components/` に対応するテストファイル

#### Views

- **テンプレート**: `.html.haml` を使用
- **Turbo Streams**: `.turbo_stream.haml`
- **パーシャル**: アンダースコア接頭辞

### 認証システム

#### デュアル認証の原則

- **完全分離**: ユーザーと管理者は独立したシステム
- **セッション**: 異なるセッションキーを使用
- **共通処理**: `Authenticatable` concern で共通化

#### 実装パターン

```ruby
# ユーザー認証
class Users::BaseController < ApplicationController
  include Authenticatable
  before_action :authenticate_user!
end

# 管理者認証
class Admins::BaseController < ApplicationController
  include Authenticatable
  before_action :authenticate_admin!
end
```

## テスト戦略

### テストの種類と配置

1. **Model Specs** (`spec/models/`)
   - ビジネスロジックのテスト
   - バリデーションのテスト
   - 関連のテスト

2. **Request Specs** (`spec/requests/`)
   - コントローラーのテスト
   - 認証・認可のテスト
   - APIレスポンスのテスト

3. **System Specs** (`spec/system/`)
   - E2Eテスト
   - ユーザーフローのテスト
   - JavaScript動作のテスト

4. **Component Specs** (`spec/components/`)
   - ViewComponentのテスト
   - レンダリング結果のテスト

### テストデータ

- **FactoryBot**: `spec/factories/` でテストデータ定義
- **名前空間対応**: `spec/factories/user/cores.rb` など
- **関連データ**: 適切な関連を設定

## デバッグ

### 開発環境でのデバッグ

- **VS Code統合**: `.vscode/launch.json` 設定済み
- **デバッガー**: Ruby Debug (rdbg) を使用
- **ヘルパーコマンド**: `bin/debug` スクリプト利用可能

### デバッグコマンド

```bash
# サーバーにアタッチ
bin/debug attach

# コンソールデバッグ
bin/debug console

# テストデバッグ
bin/debug test spec/path/to/test_spec.rb
```

## パフォーマンス

### N+1クエリ対策

- **Bullet gem**: 自動検出が有効
- **includes**: 適切な eager loading を実装
- **ログ確認**: `log/bullet.log` でN+1を確認

### キャッシュ戦略

- **Solid Cache**: データベースベースのキャッシュ
- **フラグメントキャッシュ**: ビューの部分キャッシュ
- **ロシアンドール**: ネストしたキャッシュ構造

## セキュリティ

### 必須チェック項目

1. **Strong Parameters**: すべてのパラメータを適切に制限
2. **Ransackable**: 検索可能な属性を明示的に定義
3. **認証・認可**: 適切なbefore_actionを設定
4. **CSRF対策**: Rails標準の対策を維持

### セキュリティスキャン

```bash
# 定期実行必須
bin/brakeman

# 依存関係の脆弱性チェック
bundle audit
```

## CI/CD

### GitHub Actions

- **テストワークフロー**: 全ブランチで実行
- **デプロイワークフロー**: mainブランチのみ
- **ECR自動デプロイ**: テスト成功後に実行

### 必要なSecrets

```
AWS_ROLE_ARN=arn:aws:iam::account:role/github-actions-role
AWS_REGION=ap-northeast-1
ECR_REPOSITORY=your-app-repository
SLACK_BOT_TOKEN=xoxb-your-token (オプション)
SLACK_CHANNEL_ID=C1234567890 (オプション)
```

## エラーハンドリング

### 例外通知

- **Exception Notification**: Slack通知設定済み
- **テスト用エンドポイント**: `/admins/errors/trigger`
- **ログ管理**: 環境別のログレベル設定

## 拡張時の注意点

### 新機能追加時

1. **設計確認**: 既存のアーキテクチャに従う
2. **テスト追加**: 機能に対応するテストを必ず作成
3. **ドキュメント更新**: 必要に応じてREADME等を更新
4. **セキュリティ確認**: 新しいエンドポイントの認証・認可

### データベース変更時

1. **Ridgepole**: `.schema` ファイルを更新
2. **ドライラン**: `bin/rails db:ridgepole:dry-run` で確認
3. **テストデータ**: FactoryBotの更新
4. **マイグレーション**: 本番適用時の手順確認

## 品質保証チェックリスト

コード変更時は以下を必ず実行：

- [ ] `bin/rspec` - すべてのテストが通る
- [ ] `bin/rubocop` - コーディング規約に準拠
- [ ] `bin/brakeman` - セキュリティ問題なし
- [ ] 新機能にはテストが追加されている
- [ ] ドキュメントが更新されている（必要に応じて）
- [ ] N+1クエリが発生していない
- [ ] 認証・認可が適切に設定されている

## 参考ドキュメント

- [docs/DEBUGGING.md](docs/DEBUGGING.md) - デバッグ方法の詳細
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - アーキテクチャの詳細
- [CONTRIBUTING.md](CONTRIBUTING.md) - コントリビューションガイド
