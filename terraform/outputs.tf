output "api_gateway_url" {
  description = "Invoke URL for the API Gateway default stage"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "s3_frontend_bucket" {
  description = "S3 bucket name that hosts frontend static assets"
  value       = aws_s3_bucket.frontend.id
}

output "cloudfront_url" {
  description = "CloudFront distribution URL"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "custom_domain_url" {
  description = "Custom domain URL when enabled, otherwise empty"
  value       = var.use_custom_domain ? "https://${var.root_domain}" : ""
}
