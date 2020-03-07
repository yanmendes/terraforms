provider "aws" {
  region = "us-east-1"
}

data "aws_route53_zone" "selected" {
  name         = var.domain
  private_zone = true
}

data "aws_ami" "default" {
  most_recent = "true"

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

// SSH key pair that allows connection to the machine
resource "aws_key_pair" "key" {
  key_name = "ssh-public-key"
  public_key = var.sshKey
}

// EC2 instance
resource "aws_instance" "instance" {
  ami           = data.aws_ami.default.id
  instance_type = "t3a.medium"
  key_name      = aws_key_pair.key.key_name
  tags          = var.tags
}

// Create security group that allows incoming TLS traffic
resource "aws_security_group" "sg" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = var.tags
}

// Attatch security group to created EC2 instance
resource "aws_network_interface_sg_attachment" "sg_attachment" {
  security_group_id    = aws_security_group.sg.id
  network_interface_id = aws_instance.instance.primary_network_interface_id
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
  enabled         = true
  aliases         = [var.host]
  tags            = var.tags
  is_ipv6_enabled = true

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    ssl_support_method  = "sni-only"
    acm_certificate_arn = aws_acm_certificate_validation.cert.certificate_arn
  }

  # logging_config {
  #   bucket          = "bucket.s3.amazonaws.com"
  #   include_cookies = false
  #   prefix          = "cloudfront"
  # }

  custom_error_response {
    error_caching_min_ttl = 0
    error_code            = 500
    response_code         = 0
  }

  origin {
    domain_name = aws_instance.instance.public_dns
    origin_id   = "Custom - ${aws_instance.instance.public_dns}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
      origin_protocol_policy = "http-only"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT", "DELETE"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "Custom - ${aws_instance.instance.public_dns}"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      headers      = ["Host", "Origin"]
      cookies {
        forward    = "all"
      }
    }
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