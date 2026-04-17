# OIDC 클라우드 배포 인증 (GitHub Actions → AWS/GCP/Azure)

## 도입 조건

- 배포 대상이 **클라우드(AWS S3/CloudFront, GCP, Azure)**로 확장된 경우
- 현재 하네스는 사내 자체 Docker 서버 배포만 지원 (`deploy.yml`의 SSH 기반). 이 트리거가 발생하면 추가.

## 문제 (왜 필요한가)

GitHub Actions에서 클라우드 리소스에 접근하려면 인증이 필요합니다. 전통적 방식:

- Access Key를 GitHub Secrets에 저장
- 문제: **장기 자격 증명**이 한 번 유출되면 클라우드 전체 피해. 교체 주기 관리 필수. CI 로그 실수로 노출 위험.

OIDC(OpenID Connect) 방식:

- GitHub Actions가 **단기 토큰**을 받아 클라우드 Role로 승격
- 장기 시크릿 불필요
- Role Trust Policy로 "어느 repo / 어느 branch에서만 사용 가능"을 제한

## 구현 개요 (AWS 예시)

### 1. AWS 측: Identity Provider 생성

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list <GitHub OIDC thumbprint>
```

현재 GitHub thumbprint는 AWS 공식 문서를 참조(갱신됨).

### 2. IAM Role 생성 + Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPO>:ref:refs/heads/main"
      }
    }
  }]
}
```

**중요**: `sub`을 `repo:OWNER/REPO:*`로 하면 어떤 branch/tag도 허용됨. `refs/heads/main` 또는 `environment:production`처럼 **좁게 제한**해야 타 repo 도용 방지.

### 3. 최소 권한 Policy

배포 대상에 꼭 필요한 권한만:
- S3 + CloudFront: `s3:PutObject`, `s3:GetObject`, `cloudfront:CreateInvalidation`
- EKS: `eks:DescribeCluster`, `eks:*Nodegroup*` (필요분만)

### 4. GitHub Actions workflow

```yaml
permissions:
  id-token: write      # OIDC 토큰 요청 권한 — 필수
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
          aws-region: ap-northeast-2
      - run: aws s3 sync ./dist s3://my-bucket/
```

### 5. 보안 검증

- 다른 repo에서 같은 role을 사용할 수 없는지 확인 (Trust Policy `sub` 제한 작동 확인)
- Role이 부여한 권한이 **배포에만 국한**되는지 확인 (계정 전체 권한 금지)
- CloudTrail로 Role assume 로그 모니터링

## GCP / Azure 변종

- **GCP**: Workload Identity Federation. 개념 동일, 명령이 `gcloud iam workload-identity-pools providers create-oidc`.
- **Azure**: Federated credential. `az ad app federated-credential create`.

## 하네스 통합 지점

- 새 workflow `.github/workflows/deploy-cloud.yml` 생성 (기존 `deploy.yml`과 병존)
- `AGENTS.md`와 `deploy-rules.md`에 "클라우드 배포 시 OIDC 사용 필수, 장기 access key 금지" 규칙 추가
- `setup-repo.sh`에 OIDC provider 존재 확인 + 없으면 경고 추가

## 참고

- GitHub 공식: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
- AWS: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html
- GCP: https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines
