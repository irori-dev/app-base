# デバッグガイド

このドキュメントでは、Docker環境でのRailsアプリケーションのデバッグ方法について説明します。

## 概要

このプロジェクトでは、Ruby Debug（rdbg）を使用したデバッグ環境が構築されています。VS Codeとの統合により、ブレークポイントの設定や変数の確認を視覚的に行うことができます。

## デバッグ環境の構成

### Docker設定

`docker-compose.yml`では以下の設定でデバッガーが有効になっています：

```yaml
services:
  app:
    command: rdbg --open --host=0.0.0.0 --port=12345 --nonstop -c -- bin/rails s -p 3000 -b '0.0.0.0'
    ports:
      - "3000:3000"
      - "12345:12345"  # デバッガーポート
```

### VS Code設定

`.vscode/launch.json`にデバッグ設定が含まれています：

- **Rails Server Debug (Docker)**: 実行中のサーバーにアタッチ
- **Rails Console Debug**: コンソールでのデバッグ
- **RSpec Debug**: テストのデバッグ

## デバッグ方法

### 1. `docker compose up`でのデバッグ

最も一般的な開発フローでのデバッグ方法です。

#### ステップ1: サービス起動

```bash
docker compose up
```

#### ステップ2: デバッグ開始

#### A. VS Codeでのビジュアルデバッグ（推奨）

1. VS Codeでコードを開く
2. デバッグしたい行の左側をクリックしてブレークポイントを設定
3. `F5`キーを押すか、デバッグパネルから「Rails Server Debug (Docker)」を選択
4. ブラウザでアプリケーションを操作
5. ブレークポイントで実行が停止し、変数の値などを確認可能

#### B. ターミナルでのデバッグ

```bash
# 別ターミナルで実行
bin/debug attach
```

#### C. コード内でのデバッグポイント

```ruby
def create
  @user = User::Core.new(permitted_params)
  debugger  # ここで実行停止
  # ...
end
```

### 2. DevContainerでのデバッグ

VS CodeのDevContainer機能を使用する場合：

1. VS Codeで「Dev Containers: Reopen in Container」を実行
2. コンテナ内でVS Codeが開かれる
3. 通常のVS Codeデバッグと同様に使用可能

### 3. 個別サービスのデバッグ

#### コンソールでのデバッグ

```bash
bin/debug console
```

#### テストのデバッグ

```bash
# 全テストのデバッグ
bin/debug test

# 特定ファイルのデバッグ
bin/debug test spec/controllers/users_controller_spec.rb

# 特定のテストのデバッグ
bin/debug test spec/controllers/users_controller_spec.rb:10
```

## デバッグ用ヘルパーコマンド

プロジェクトには`bin/debug`スクリプトが用意されています：

```bash
# サーバー起動（デバッガー付き）
bin/debug server

# 実行中のサーバーにアタッチ
bin/debug attach

# コンテナ内からアタッチ
bin/debug attach-container

# ログをリアルタイム表示
bin/debug logs

# コンソールでのデバッグ
bin/debug console

# テストのデバッグ
bin/debug test [ファイルパス]
```

## デバッグ用ヘルパーメソッド

`lib/debug_helpers.rb`に便利なデバッグメソッドが定義されています：

### 条件付きデバッグ

```ruby
# 特定条件でのみデバッグ
debug_if(user.admin?, "Admin user detected")

# 特定ユーザーでのみデバッグ
debug_for_user("test@example.com", "Testing user flow")
```

### パフォーマンス測定付きデバッグ

```ruby
debug_with_timing('User Creation') do
  @user = User::Core.create!(user_params)
end
```

### SQLクエリのデバッグ

```ruby
debug_queries do
  users = User::Core.includes(:profile).limit(10)
  users.each { |user| puts user.profile.name }
end
```

## 実践的なデバッグパターン

### コントローラーでのデバッグ

```ruby
class UsersController < ApplicationController
  def create
    # パフォーマンス測定
    debug_with_timing('User Creation') do
      @user = User::Core.new(permitted_params)
      
      # 特定条件でのデバッグ
      debug_if(@user.email.include?('admin'), 'Admin user creation')
      
      if @user.save
        sign_in(@user)
        flash.now[:notice] = 'ユーザー登録が完了しました'
      else
        debugger # バリデーションエラー時のデバッグ
        render :new
      end
    end
  end
end
```

### モデルでのデバッグ

```ruby
class User::Core < ApplicationRecord
  def complex_calculation
    debug_queries do
      # 複雑なクエリの実行
      result = expensive_operation
      debugger if result.nil? # 予期しない結果の場合
      result
    end
  end
end
```

### テストでのデバッグ

```ruby
RSpec.describe UsersController do
  it 'creates user successfully' do
    post :create, params: { user_core: { email: 'test@example.com', password: 'password' } }
    
    debugger if response.status != 200 # 期待しないステータスの場合
    expect(response).to have_http_status(:success)
  end
end
```

## デバッガー内でのコマンド

デバッガーが起動した際に使用できる主要なコマンド：

- `n` (next): 次の行へ進む
- `s` (step): メソッド内にステップイン
- `c` (continue): 実行を継続
- `l` (list): 現在のコード周辺を表示
- `p variable_name`: 変数の値を表示
- `pp variable_name`: 変数を整形して表示
- `bt` (backtrace): スタックトレースを表示
- `info`: デバッガーの情報を表示
- `help`: ヘルプを表示

## トラブルシューティング

### デバッガーに接続できない場合

1. ポート12345が使用されていないか確認
2. `docker compose ps`でappサービスが起動しているか確認
3. `docker compose logs app`でエラーログを確認

### VS Codeでブレークポイントが効かない場合

1. `.vscode/launch.json`の設定を確認
2. VS CodeのRuby Debug拡張機能がインストールされているか確認
3. ファイルパスが正しくマッピングされているか確認

### パフォーマンスが遅い場合

1. 不要なブレークポイントを削除
2. `debug_queries`の使用を制限
3. ログレベルを調整

## ベストプラクティス

### 効果的なデバッグポイント

- **コントローラーのアクション開始時**: リクエストパラメータの確認
- **モデルのバリデーション前後**: データの整合性確認
- **複雑なビジネスロジック内**: 処理フローの確認
- **エラーが発生しやすい箇所**: 例外処理の確認

### デバッグ時の注意点

- 本番環境では`debugger`文を削除する
- 大量のデータを扱う際はブレークポイントの位置に注意
- チーム開発では一時的なデバッグコードをコミットしない
- パフォーマンステスト時はデバッガーを無効にする

### ログとの使い分け

- **デバッグ**: 詳細な変数の確認、ステップ実行
- **ログ**: 処理の流れの確認、本番環境での問題調査

```ruby
# デバッグ用（開発環境のみ）
debugger if Rails.env.development?

# ログ用（全環境）
Rails.logger.debug "Processing user: #{user.email}"
```

## 参考リンク

- [Ruby Debug (rdbg) 公式ドキュメント](https://github.com/ruby/debug)
- [VS Code Ruby Debug 拡張機能](https://marketplace.visualstudio.com/items?itemName=KoichiSasada.vscode-rdbg)
- [Rails デバッグガイド](https://guides.rubyonrails.org/debugging_rails_applications.html)
