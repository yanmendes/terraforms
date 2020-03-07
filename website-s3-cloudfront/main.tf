provider "aws" {
  region = "us-east-1"
}

terraform {
  # backend "s3" {
  #   bucket         = "terraform-backend"
  #   key            = "website-s3-cloudfront/site.yanmendes.dev.tfstate"
  #   dynamodb_table = "terraform-locks"
  #   region         = "us-east-1"
  #   encrypt        = true
  # }
  backend "local" {}
}

data "aws_route53_zone" "selected" {
  name         = var.domain
  private_zone = true
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid = "PublicReadAccess"

    actions = ["s3:GetObject"]

    resources = ["arn:aws:s3:::origin.${var.host}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:UserAgent"
      values   = [var.s3Key]
    }

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

// S3 bucket that hosts the website
resource "aws_s3_bucket" "bucket" {
  bucket = "origin.${var.host}"
  acl    = "public-read"

  policy = data.aws_iam_policy_document.bucket_policy.json

  website {
    index_document = "index.html"
    error_document = "index.html"
  }

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

  tags = var.tags
}

// Create ACM Certificate for SSL
resource "aws_acm_certificate" "cert" {
  domain_name       = var.host
  validation_method = "DNS"
  tags              = var.tags
}

// Create Route53 record to validate certificate
resource "aws_route53_record" "cert_validation" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_type
  records = [aws_acm_certificate.cert.domain_validation_options.0.resource_record_value]
  ttl     = 60
}

// Create validation to validate certificate based on the Route53 record
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

// Create CloudFront distribution
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  aliases             = [var.host]
  tags                = var.tags
  http_version        = "http2"
  default_root_object = "index.html"

  origin {
    origin_id   = "origin-bucket-${aws_s3_bucket.bucket.id}"
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name

    custom_origin_config {
      origin_protocol_policy = "http-only"
      http_port              = "80"
      https_port             = "443"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "User-Agent"
      value = var.s3Key
    }
  }

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "DELETE", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = "0"
    default_ttl            = "300"
    max_ttl                = "1200"
    target_origin_id       = "origin-bucket-${aws_s3_bucket.bucket.id}"

    // This redirects any HTTP request to HTTPS. Security first!
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only"
  }

  # logging_config {
  #   bucket          = "bucket.s3.amazonaws.com"
  #   include_cookies = false
  #   prefix          = "cloudfront"
  # }

  custom_error_response {
    error_code = "404"
    error_caching_min_ttl = 0
    response_code = "200"
    response_page_path = "/index.html"
  }
}

// Configure Route53 record to deliver distribution
resource "aws_route53_record" "main" {
  zone_id         = data.aws_route53_zone.selected.zone_id
  name            = var.host
  type            = "A"
  allow_overwrite = true

  alias {
    name    = aws_cloudfront_distribution.main.domain_name
    zone_id = aws_cloudfront_distribution.main.hosted_zone_id

    evaluate_target_health = false
  }
}
