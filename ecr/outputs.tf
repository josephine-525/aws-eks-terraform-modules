output "backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "frontend_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "analytics_repository_url" {
  value = aws_ecr_repository.analytics.repository_url
}

output "fraud_detection_repository_url" {
  value = aws_ecr_repository.fraud_detection.repository_url
}
