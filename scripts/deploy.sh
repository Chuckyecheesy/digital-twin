#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}          # dev | test | prod
PROJECT_NAME=${2:-twin}

echo "🚀 Deploying ${PROJECT_NAME} to ${ENVIRONMENT}..."

# 1. Build Lambda package
cd "$(dirname "$0")/.."        # project root
echo "📦 Building Lambda package..."
(cd backend && uv run deploy.py)

# 2. Ensure Terraform state backend resources exist
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${DEFAULT_AWS_REGION:-us-east-1}
TF_STATE_BUCKET="twin-terraform-state-${AWS_ACCOUNT_ID}"

echo "🪣 Ensuring Terraform state bucket exists..."
if ! aws s3 ls "s3://${TF_STATE_BUCKET}" 2>/dev/null; then
  echo "   Creating S3 bucket: ${TF_STATE_BUCKET}"
  aws s3 mb "s3://${TF_STATE_BUCKET}" --region "${AWS_REGION}"
  
  echo "   Enabling versioning..."
  aws s3api put-bucket-versioning \
    --bucket "${TF_STATE_BUCKET}" \
    --versioning-configuration Status=Enabled \
    --region "${AWS_REGION}"
  
  echo "   Setting bucket ownership controls..."
  aws s3api put-bucket-ownership-controls \
    --bucket "${TF_STATE_BUCKET}" \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]' \
    --region "${AWS_REGION}"
  
  echo "   Enabling encryption..."
  aws s3api put-bucket-encryption \
    --bucket "${TF_STATE_BUCKET}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }' \
    --region "${AWS_REGION}"
fi

# 3. Terraform workspace & apply
cd terraform
terraform init -input=false \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"

if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

# Import S3 buckets
MEMORY_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-memory-${AWS_ACCOUNT_ID}"
FRONTEND_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-frontend-${AWS_ACCOUNT_ID}"
LAMBDA_ROLE="${PROJECT_NAME}-${ENVIRONMENT}-lambda-role"

if ! terraform state list | grep -q 'aws_s3_bucket.memory'; then
  echo "   Importing S3 memory bucket: $MEMORY_BUCKET"
  terraform import aws_s3_bucket.memory "$MEMORY_BUCKET" || true
fi

if ! terraform state list | grep -q 'aws_s3_bucket.frontend'; then
  echo "   Importing S3 frontend bucket: $FRONTEND_BUCKET"
  terraform import aws_s3_bucket.frontend "$FRONTEND_BUCKET" || true
fi

if ! terraform state list | grep -q 'aws_iam_role.lambda_role'; then
  echo "   Importing IAM Lambda role: $LAMBDA_ROLE"
  terraform import aws_iam_role.lambda_role "$LAMBDA_ROLE" || true
fi

# Use prod.tfvars for production environment
if [ "$ENVIRONMENT" = "prod" ]; then
  TF_APPLY_CMD=(terraform apply -var-file=prod.tfvars -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve)
else
  TF_APPLY_CMD=(terraform apply -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve)
fi

echo "🎯 Applying Terraform..."
"${TF_APPLY_CMD[@]}"

API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || true)
FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket 2>/dev/null || true)
CUSTOM_URL=$(terraform output -raw custom_domain_url 2>/dev/null || true)

if [ -z "$API_URL" ]; then
  echo "❌ Missing Terraform output: api_gateway_url"
  echo "   Ensure terraform/outputs.tf defines output \"api_gateway_url\" and run terraform apply."
  exit 1
fi

if [ -z "$FRONTEND_BUCKET" ]; then
  echo "❌ Missing Terraform output: s3_frontend_bucket"
  echo "   Ensure terraform/outputs.tf defines output \"s3_frontend_bucket\" and run terraform apply."
  exit 1
fi

# 4. Build + deploy frontend
cd ../frontend

# Create production environment file with API URL
echo "📝 Setting API URL for production..."
echo "NEXT_PUBLIC_API_URL=$API_URL" > .env.production

npm install
npm run build
aws s3 sync ./out "s3://$FRONTEND_BUCKET/" --delete
cd ..

# 5. Final messages
echo -e "\n✅ Deployment complete!"
echo "🌐 CloudFront URL : $(terraform -chdir=terraform output -raw cloudfront_url)"
if [ -n "$CUSTOM_URL" ]; then
  echo "🔗 Custom domain  : $CUSTOM_URL"
fi
echo "📡 API Gateway    : $API_URL"
