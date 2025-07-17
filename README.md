# Rails Application Template (app_base)

このリポジトリは、デュアル認証システムを持つ現代的なRailsアプリケーションを素早く構築するためのテンプレートです。
clone後に`.git`を削除して、新規アプリケーションのベースとして利用してください。

## 特徴

- **デュアル認証システム**: ユーザーと管理者の完全に分離された認証
- **モダンフロントエンド**: Hotwire (Turbo + Stimulus) による SPA風のUX
- **コンポーネントベース**: ViewComponent による再利用可能なUI
- **バックグラウンド処理**: Solid Queue によるジョブ処理
- **リアルタイム機能**: Action Cable による WebSocket サポート
- **包括的なテスト**: RSpec + FactoryBot + Capybara
- **開発者体験**: Docker + VS Code DevContainer + デバッグ環境

## 技術スタック

### コア技術

- **Ruby 3.4.4** / **Rails 8.0.2**
- **PostgreSQL 16** - 全環境統一のデータベース
- **Solid Suite** - Redis/Sidekiqの代替となるデータベースベースソリューション
  - Solid Cache - キャッシュレイヤー
  - Solid Queue - バックグラウンドジョブ処理
  - Solid Cable - WebSocket接続管理

### フロントエンドスタック

- **Hotwire** - モダンなSPA風体験
  - Turbo Drive - 高速ページナビゲーション
  - Turbo Frames - 部分ページ更新
  - Turbo Streams - リアルタイム更新
  - Stimulus - 軽量JavaScriptフレームワーク
- **Tailwind CSS** - ユーティリティファーストCSSフレームワーク
- **ViewComponent** - コンポーネントベースビュー構築
- **ImportMap** - node_modules不要のJavaScriptモジュール管理
- **Haml** - クリーンなマークアップのためのテンプレートエンジン

## クイックスタート

```bash
# リポジトリのクローン
git clone <repository-url>
cd <project-name>

# Gitの設定をリセット
rm -rf .git
git init
git add .
git commit -m "Initial commit"

# 開発環境の起動
bin/setup
bin/dev
```

## 開発環境

- Ruby 3.4.4 / Rails 8.0.2
- Docker Compose
- VS Code の DevContainer 対応

初回起動時は次のコマンドで環境を準備します。

```bash
bin/setup
bin/dev
```

## 設定の概要

### Database

PostgreSQL を使用し、マイグレーション管理には
[ridgepole](https://github.com/ridgepole/ridgepole) を採用しています。
`db/schema/` 以下に `.schema` ファイルを置くとスキーマが適用されます。

開発環境・テスト環境ともにPostgreSQLが必要です。
Docker環境では自動的に設定されます。

### 非同期処理

Rails 8 標準の `solid_queue` を利用します。
ジョブの状態は MissionControl の UI から確認できます。
コンテナ上では `bin/jobs` を別プロセスで起動してください。

### ページネーション・検索

[kaminari](https://github.com/kaminari/kaminari) と
[ransack](https://github.com/activerecord-hackery/ransack) を同梱しています。

### CSS

[tailwindcss-rails](https://github.com/rails/tailwindcss-rails) により
ファイル変更時は自動で再ビルドされます。

### JavaScript

Hotwire(Turbo/Stimulus) と importmap を利用しているため
`node_modules` は不要です。

### View

テンプレートエンジンは Haml を採用し、
[ViewComponent](https://github.com/ViewComponent/view_component) も利用できます。

### メール

開発環境では [letter_opener_web](https://github.com/fgrehm/letter_opener_web)
でメール内容をブラウザ確認できます。

### 例外通知

[exception_notification](https://github.com/smartinez87/exception_notification)
と `slack-notifier` により Slack へエラーを通知できます。

### 環境変数

`rails credentials` を利用します。`config/master.key` を取得して配置してください。

### N+1クエリ検出

開発環境では [Bullet](https://github.com/flyerhzm/bullet) が有効になっており、
N+1クエリや不要なeager loadingを自動検出します。

- ブラウザでアラート表示
- コンソールログに出力
- `log/bullet.log` にログ記録
- ページ下部にサマリー表示

問題が検出された場合は、適切な `includes` を追加してください。

## Debug

Docker環境でのデバッグ方法については [docs/DEBUGGING.md](docs/DEBUGGING.md) を参照してください。

### デバッグ手順

```bash
# サーバー起動
docker compose up

# VS Codeでブレークポイントを設定後、F5でデバッグ開始
# または別ターミナルで
bin/debug attach
```

主要なデバッグコマンド：

- `bin/debug attach` - 実行中のサーバーにアタッチ
- `bin/debug console` - コンソールでのデバッグ
- `bin/debug test [ファイル]` - テストのデバッグ
- `bin/debug logs` - ログのリアルタイム表示

## サンプル実装

`users` と `admins` のリソースを簡易的に実装しています。
ログインやメール送信の仕組みなどを確認するサンプルとして利用してください。

### サンプルデータ

開発環境では以下のコマンドでサンプルデータを投入できます：

```bash
bin/rails db:seed
```

デフォルトのログイン情報：

- 管理者: `admin@example.com` / `password123`
- ユーザー: `user@example.com` / `password123`

## ヘルスチェック

```bash
GET /up
```

Rails標準のヘルスチェックエンドポイント：

- アプリケーションが正常に動作している場合、200 OKを返す
- レスポンスは緑背景のシンプルなHTML
- ロードバランサーやモニタリングツールでの使用に最適

## エラーテスト（管理者権限必須）

アラート通知のテスト用に、意図的にエラーを発生させるエンドポイントを提供：

```bash
GET /admins/errors/trigger?type=TYPE
```

利用可能なエラータイプ：

- `standard` (デフォルト): StandardError
- `runtime`: RuntimeError
- `argument`: ArgumentError
- `not_found`: ActiveRecord::RecordNotFound
- `timeout`: Timeout::Error
- `database`: データベース接続エラー
- `zero_division`: ゼロ除算エラー
- `nil`: NoMethodError

例：
```bash
# 標準エラーを発生させる
curl -H "Cookie: session_id=your_admin_session" http://localhost:3000/admins/errors/trigger

# タイムアウトエラーを発生させる
curl -H "Cookie: session_id=your_admin_session" http://localhost:3000/admins/errors/trigger?type=timeout
```

**注意**:

- このエンドポイントは全環境で利用可能ですが、管理者権限が必要です
- 本番環境では特に慎重に使用してください

## CI/CD

GitHub Actionsによる2つのワークフローが設定されています：

### 1. Test Workflow (`.github/workflows/test.yml`)

- **実行条件**: 全ブランチのプッシュ・PR時に実行
- **実行内容**: 
  - RSpec、RuboCop、Brakemanの実行
  - Dockerイメージのビルドテスト

### 2. Deploy Workflow (`.github/workflows/deploy.yml`)

- **実行条件**: mainブランチへのプッシュ時のみ実行
- **実行内容**: 
  - テストワークフローの完了を待機
  - テスト成功後にECRへDockerイメージをプッシュ

### ECR自動デプロイ

mainブランチにプッシュした際、テストが成功すると自動的にDockerイメージをAmazon ECRにプッシュします。

#### 必要なGitHub Secrets

```bash
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/github-actions-role
AWS_REGION=ap-northeast-1
ECR_REPOSITORY=your-app-repository
```

#### IAMロールの権限設定例

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": [
        "arn:aws:ecr:ap-northeast-1:123456789012:repository/your-app-repository"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    }
  ]
}
```

#### 信頼関係の設定例

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

### Slack通知（オプション）

CI実行結果をSlackに通知する場合は、以下のSecretsを設定してください：

- `SLACK_BOT_TOKEN`: Slack Bot User OAuth Token
- `SLACK_CHANNEL_ID`: 通知先のチャンネルID

Secretsが設定されていない場合、Slack通知はスキップされます。

## コントリビューション

[CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

## 行動規範

[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) を参照してください。

## アーキテクチャ

詳細な技術設計については [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) を参照してください。
