# One shared registry for the whole account (see account/ecr), not one per
# environment -- so a real CI pipeline can build an image once and promote
# the same digest dev -> staging -> prod, instead of rebuilding per environment.
resource "aws_ecr_repository" "backend" {
  name                 = "${var.name_prefix}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.name_prefix}-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# team-analytics's Kafka consumer (analytics-demo repo) -- this team had no
# image of its own at all before this (it ran the hashicorp/http-echo public
# image as a placeholder), unlike backend/frontend which always needed a real
# repo from day one.
resource "aws_ecr_repository" "analytics" {
  name                 = "${var.name_prefix}-analytics"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# team-fraud-detection's Kafka consumer (fraud-detection-demo repo) -- same
# reasoning as analytics above. Hand-added directly here rather than via
# idp-cli's new publish-terraform-mr (built the same session, right after
# this exact gap was found against analytics) -- that path opens a real
# GitLab MR through a live pipeline run, worth exercising for a genuinely
# new service scaffolded from scratch, not simpler than editing this file
# by hand for a repo that already exists.
resource "aws_ecr_repository" "fraud_detection" {
  name                 = "${var.name_prefix}-fraud-detection"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
