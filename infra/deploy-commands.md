# CloudFormation デプロイコマンド例

## 1. 基盤リソース（infra-base.yaml）のデプロイ

### 初回デプロイ
```bash
aws cloudformation create-stack \
  --stack-name myapp-infra-base \
  --template-body file://infra-base.yaml \
  --parameters \
    ParameterKey=AppName,ParameterValue=myapp \
    ParameterKey=VpcId,ParameterValue=vpc-12345678 \
    ParameterKey=PrivateSubnetIds,ParameterValue="subnet-12345678,subnet-87654321" \
    ParameterKey=PublicSubnetIds,ParameterValue="subnet-abcdef12,subnet-21fedcba" \
    ParameterKey=AppPort,ParameterValue=3000 \
    ParameterKey=CertificateArn,ParameterValue=arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012 \
    ParameterKey=DatabaseUrlName,ParameterValue=myapp-database-url \
    ParameterKey=CacheDatabaseUrlName,ParameterValue=myapp-cache-database-url \
    ParameterKey=QueueDatabaseUrlName,ParameterValue=myapp-queue-database-url \
    ParameterKey=RailsMasterKeyName,ParameterValue=myapp-rails-master-key \
  --capabilities CAPABILITY_IAM \
  --region us-east-1
```

### 更新デプロイ
```bash
aws cloudformation update-stack \
  --stack-name myapp-infra-base \
  --template-body file://infra-base.yaml \
  --parameters \
    ParameterKey=AppName,ParameterValue=myapp \
    ParameterKey=VpcId,ParameterValue=vpc-12345678 \
    ParameterKey=PrivateSubnetIds,ParameterValue="subnet-12345678,subnet-87654321" \
    ParameterKey=PublicSubnetIds,ParameterValue="subnet-abcdef12,subnet-21fedcba" \
    ParameterKey=AppPort,ParameterValue=3000 \
    ParameterKey=CertificateArn,ParameterValue=arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012 \
    ParameterKey=DatabaseUrlName,ParameterValue=myapp-database-url \
    ParameterKey=CacheDatabaseUrlName,ParameterValue=myapp-cache-database-url \
    ParameterKey=QueueDatabaseUrlName,ParameterValue=myapp-queue-database-url \
    ParameterKey=RailsMasterKeyName,ParameterValue=myapp-rails-master-key \
  --capabilities CAPABILITY_IAM \
  --region us-east-1
```

## 2. SSMパラメータストアへのシークレット登録

```bash
# データベース接続文字列
aws ssm put-parameter \
  --name "myapp-database-url" \
  --value "postgres://user:password@hostname:5432/database" \
  --type "SecureString" \
  --region us-east-1

# キャッシュデータベース接続文字列  
aws ssm put-parameter \
  --name "myapp-cache-database-url" \
  --value "redis://cache-hostname:6379/0" \
  --type "SecureString" \
  --region us-east-1

# キューデータベース接続文字列
aws ssm put-parameter \
  --name "myapp-queue-database-url" \
  --value "redis://queue-hostname:6379/1" \
  --type "SecureString" \
  --region us-east-1

# Rails Master Key
aws ssm put-parameter \
  --name "myapp-rails-master-key" \
  --value "your-rails-master-key-here" \
  --type "SecureString" \
  --region us-east-1
```

## 3. アプリケーションデプロイ（app-deploy.yaml）

### 初回デプロイ
```bash
aws cloudformation create-stack \
  --stack-name myapp-app-deploy \
  --template-body file://app-deploy.yaml \
  --parameters \
    ParameterKey=AppName,ParameterValue=myapp \
    ParameterKey=ImageURI,ParameterValue=123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:latest \
    ParameterKey=AppPort,ParameterValue=3000 \
    ParameterKey=InfraStackName,ParameterValue=myapp-infra-base \
    ParameterKey=DesiredCount,ParameterValue=2 \
    ParameterKey=RuntimePlatform,ParameterValue=ARM64 \
  --region us-east-1
```

### 更新デプロイ（新しいイメージ）
```bash
aws cloudformation update-stack \
  --stack-name myapp-app-deploy \
  --template-body file://app-deploy.yaml \
  --parameters \
    ParameterKey=AppName,ParameterValue=myapp \
    ParameterKey=ImageURI,ParameterValue=123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:v1.2.3 \
    ParameterKey=AppPort,ParameterValue=3000 \
    ParameterKey=InfraStackName,ParameterValue=myapp-infra-base \
    ParameterKey=DesiredCount,ParameterValue=2 \
    ParameterKey=RuntimePlatform,ParameterValue=ARM64 \
  --region us-east-1
```

## 4. ECRイメージプッシュ

### ARM64イメージのビルド・プッシュ
```bash
# ECRログイン
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

# ARM64イメージビルド
docker buildx build --platform linux/arm64 -t myapp:latest .

# タグ付け
docker tag myapp:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:latest

# プッシュ
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:latest
```

### x86_64イメージのビルド・プッシュ
```bash
# x86_64イメージビルド
docker buildx build --platform linux/amd64 -t myapp:latest .

# タグ付け・プッシュ（同様）
docker tag myapp:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:latest
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:latest
```

## 5. スタック削除

### アプリケーションスタック削除
```bash
aws cloudformation delete-stack \
  --stack-name myapp-app-deploy \
  --region us-east-1
```

### 基盤スタック削除
```bash
aws cloudformation delete-stack \
  --stack-name myapp-infra-base \
  --region us-east-1
```

## 注意事項

1. **パラメータ値の確認**: VPC ID、サブネット ID、証明書ARNなどは実際の環境に合わせて変更してください。

2. **アーキテクチャの統一**: ECSタスク（ARM64/x86_64）とDockerイメージのアーキテクチャを合わせてください。

3. **シークレット管理**: SSMパラメータストアの値は実際の接続情報に置き換えてください。

4. **権限設定**: CloudFormationを実行するIAMユーザー/ロールに適切な権限があることを確認してください。

5. **リージョン設定**: 全てのリソースを同一リージョンにデプロイしてください。

6. **依存関係**: app-deploy.yamlはinfra-base.yamlのOutputsに依存しているため、必ずinfra-base.yamlを先にデプロイしてください。
