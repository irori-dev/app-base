# AWS Fargate + CloudFormation ベストプラクティス設計

## アーキテクチャ概要

### 2層CloudFormationスタック構成

1. **infra-base.yaml**: 共通基盤リソース
   - ALB、ターゲットグループ、リスナールール
   - IAMロール、セキュリティグループ
   - CloudWatch Logs
   - SSMパラメータ用のOutputs（ARN）

2. **app-deploy.yaml**: アプリケーション固有リソース
   - ECSクラスター、サービス、タスク定義
   - infra-baseからImportValueでリソース参照

### 利点

- **分離管理**: 基盤とアプリケーションの独立したライフサイクル
- **再利用性**: 複数アプリで基盤リソースを共有可能
- **安全性**: クロススタック参照で依存関係を明確化

## 設計のポイント

### 1. パラメータ設計

#### infra-base.yaml
```yaml
Parameters:
  AppName: 
    Type: String
    Description: Application name
  DatabaseUrlName:
    Type: String
    Description: SSM Parameter name for DATABASE_URL
    Default: myapp-database-url
```

#### app-deploy.yaml
```yaml
Parameters:
  InfraStackName:
    Type: String
    Description: Name of the infrastructure stack
  ImageURI:
    Type: String
    Description: ECR image URI
  RuntimePlatform:
    Type: String
    Default: ARM64
    AllowedValues: [ARM64, X86_64]
```

### 2. クロススタック参照

#### infra-base.yamlのOutputs
```yaml
Outputs:
  DatabaseUrlArn:
    Description: SSM Parameter Store ARN for DATABASE_URL
    Value:
      Fn::Sub: "arn:aws:ssm:${AWS::Region}:${AWS::AccountId}:parameter/${DatabaseUrlName}"
    Export:
      Name: 
        Fn::Sub: "${AWS::StackName}-DatabaseUrlArn"
```

#### app-deploy.yamlでのImportValue
```yaml
Secrets:
  - Name: DATABASE_URL
    ValueFrom: 
      Fn::ImportValue:
        Fn::Sub: "${InfraStackName}-DatabaseUrlArn"
```

### 3. ALBリスナールール設計

```yaml
# HTTP(80) → HTTPS(443)リダイレクト
HttpsRedirectListener:
  Type: AWS::ElasticLoadBalancingV2::Listener
  Properties:
    LoadBalancerArn: !Ref ApplicationLoadBalancer
    Port: 80
    Protocol: HTTP
    DefaultActions:
      - Type: redirect
        RedirectConfig:
          Protocol: HTTPS
          Port: 443
          StatusCode: HTTP_301

# HTTPS(443) → ターゲットグループフォワード
HttpsForwardListener:
  Type: AWS::ElasticLoadBalancingV2::Listener
  Properties:
    LoadBalancerArn: !Ref ApplicationLoadBalancer
    Port: 443
    Protocol: HTTPS
    Certificates:
      - CertificateArn: !Ref CertificateArn
    DefaultActions:
      - Type: forward
        TargetGroupArn: !Ref AppTargetGroup
```

### 4. IAM権限設計

#### ECSタスクロール（アプリケーション権限）
```yaml
TaskRole:
  Type: AWS::IAM::Role
  Properties:
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            Service: ecs-tasks.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: SSMParameterAccess
        PolicyDocument:
          Version: '2012-10-17'
          Statement:
            - Effect: Allow
              Action:
                - ssm:GetParameter
                - ssm:GetParameters
                - ssm:GetParametersByPath
              Resource:
                - Fn::Sub: "arn:aws:ssm:${AWS::Region}:${AWS::AccountId}:parameter/${DatabaseUrlName}"
                - Fn::Sub: "arn:aws:ssm:${AWS::Region}:${AWS::AccountId}:parameter/${CacheDatabaseUrlName}"
                - Fn::Sub: "arn:aws:ssm:${AWS::Region}:${AWS::AccountId}:parameter/${QueueDatabaseUrlName}"
                - Fn::Sub: "arn:aws:ssm:${AWS::Region}:${AWS::AccountId}:parameter/${RailsMasterKeyName}"
            - Effect: Allow
              Action:
                - kms:Decrypt
              Resource: "*"
```

#### ECSタスク実行ロール（AWS基盤権限）
```yaml
TaskExecutionRole:
  Type: AWS::IAM::Role
  Properties:
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            Service: ecs-tasks.amazonaws.com
          Action: sts:AssumeRole
    ManagedPolicyArns:
      - arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

### 5. アーキテクチャ対応

#### ARM64対応（Graviton2）
```yaml
# ECSタスク定義
RuntimePlatform:
  CpuArchitecture: !Ref RuntimePlatform  # ARM64 or X86_64
  OperatingSystemFamily: LINUX

# Dockerビルド
docker buildx build --platform linux/arm64 -t myapp:latest .
```

#### x86_64対応
```yaml
# Dockerビルド
docker buildx build --platform linux/amd64 -t myapp:latest .
```

### 6. シークレット管理

#### SSMパラメータストア
```bash
aws ssm put-parameter \
  --name "myapp-database-url" \
  --value "postgres://user:password@hostname:5432/database" \
  --type "SecureString" \
  --key-id "alias/aws/ssm"
```

#### ECSタスクでの参照
```yaml
Secrets:
  - Name: DATABASE_URL
    ValueFrom: 
      Fn::ImportValue:
        Fn::Sub: "${InfraStackName}-DatabaseUrlArn"
```

## VPCエンドポイント（オプション）

### 必要なエンドポイント
- **com.amazonaws.region.ssm**: SSMパラメータストアアクセス
- **com.amazonaws.region.ecr.dkr**: ECRイメージプル
- **com.amazonaws.region.ecr.api**: ECR API
- **com.amazonaws.region.s3**: S3（ECRレイヤー保存）
- **com.amazonaws.region.logs**: CloudWatch Logs

### CloudFormationでの作成例
```yaml
SSMVPCEndpoint:
  Type: AWS::EC2::VPCEndpoint
  Properties:
    VpcId: !Ref VpcId
    ServiceName: !Sub 'com.amazonaws.${AWS::Region}.ssm'
    VpcEndpointType: Interface
    SubnetIds: !Ref PrivateSubnetIds
    SecurityGroupIds:
      - !Ref VPCEndpointSecurityGroup
```

## 運用フロー

### 1. 新規アプリケーション追加
1. SSMパラメータにシークレット登録
2. infra-base.yamlデプロイ（基盤リソース作成）
3. ECRイメージビルド・プッシュ
4. app-deploy.yamlデプロイ（アプリケーション起動）

### 2. アプリケーション更新
1. 新しいECRイメージビルド・プッシュ
2. app-deploy.yamlを新しいImageURIで更新デプロイ

### 3. 基盤設定変更
1. infra-base.yamlで基盤リソース更新
2. 必要に応じてapp-deploy.yamlも更新

### 4. スケーリング
```yaml
# app-deploy.yamlのDesiredCountを変更
Service:
  Properties:
    DesiredCount: !Ref DesiredCount  # 2 → 4 など
```

## トラブルシューティング

### よくあるエラーと対処法

#### 1. exec format error
**原因**: ECSタスクのアーキテクチャとDockerイメージのアーキテクチャが不一致

**対処法**:
```bash
# ARM64用
docker buildx build --platform linux/arm64 -t myapp:latest .

# x86_64用  
docker buildx build --platform linux/amd64 -t myapp:latest .
```

#### 2. AccessDenied (SSM Parameter)
**原因**: ECSタスクロールにSSM/KMS権限が不足

**対処法**: IAMロールにkms:Decrypt権限追加
```yaml
- Effect: Allow
  Action:
    - kms:Decrypt
  Resource: "*"
```

#### 3. CloudFormation YAMLアンカーエラー
**原因**: CloudFormationはYAMLアンカー/エイリアスをサポートしない

**対処法**: Fn::Subを使用
```yaml
# ❌ 使用不可
Resource: *DatabaseUrlArn

# ✅ 正しい記述
Resource:
  Fn::Sub: "arn:aws:ssm:${AWS::Region}:${AWS::AccountId}:parameter/${DatabaseUrlName}"
```

## セキュリティ考慮事項

1. **最小権限の原則**: IAMロールには必要最小限の権限のみ付与
2. **シークレット暗号化**: SSMパラメータはSecureStringを使用
3. **ネットワーク分離**: ECSタスクはprivateサブネットに配置
4. **SSL/TLS**: ALBでHTTPS通信を強制
5. **ログ監視**: CloudWatch Logsで適切なログ出力

この設計により、スケーラブルで安全なAWS Fargateアプリケーションの運用が可能になります。
