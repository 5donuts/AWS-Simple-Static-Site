# AWS Simple Static Site - IaC to deploy an economical static site on AWS
# Copyright (C) 2024  Charles German <5donuts@pm.me>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

locals {
  site_bucket = {
    name                = var.domain_name
    block_public_access = true
    object_ownership    = "BucketOwnerEnforced"
  }

  logs_bucket = {
    name                = "${local.site_bucket.name}-logs"
    block_public_access = false                  # These two settings are required in order to enable ACLs
    object_ownership    = "BucketOwnerPreferred" # This is annoying, but required for CloudFront logs
  }

  logs_root_path       = "logs"
  bucket_logs_path     = "${local.logs_root_path}/origin"
  cloudfront_logs_path = "${local.logs_root_path}/cdn"

  sanitized_domain = replace(var.domain_name, ".", "_")
  origin_id        = "${local.sanitized_domain}-s3-origin"
}

# --------------------------------------------------------------------------- #
#                   Configure the Route53 Public Hosted Zone                  #
# --------------------------------------------------------------------------- #

resource "aws_route53_zone" "site" {
  name = var.domain_name

  lifecycle {
    # AWS charges US$0.50 per hosted zone created within one month, up to a maximum of 25 hosted zones.
    prevent_destroy = true
  }
}

# Create any additional non-alias Route53 records for the hosted zone
resource "aws_route53_record" "non_alias" {
  for_each = { for record in var.route53_records : "${record.name == "" ? "@" : record.name}.${substr(md5(record.records[0]), 0, 5)}" => record if record.alias == null }

  zone_id = aws_route53_zone.site.zone_id

  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records
}

# Create any additional alias Route53 records for the hosted zone
resource "aws_route53_record" "alias" {
  for_each = { for record in var.route53_records : "${record.name == "" ? "@" : record.name}.${substr(md5(record.records[0]), 0, 5)}" => record if record.alias != null }

  zone_id = aws_route53_zone.site.zone_id

  name = each.value.name
  type = each.value.type

  alias {
    name                   = each.value.alias.name
    zone_id                = each.value.alias.zone_id
    evaluate_target_health = each.value.alias.eval_target_health
  }
}

# Records to validate the ACM certificate used by the site
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for option in aws_acm_certificate.site.domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      type   = option.resource_record_type
      record = option.resource_record_value
    }
  }

  zone_id = aws_route53_zone.site.zone_id

  name = each.value.name
  type = each.value.type
  ttl  = 60

  records = [
    each.value.record
  ]
}

# --------------------------------------------------------------------------- #
#                Configure the ACM certificate for the website                #
# --------------------------------------------------------------------------- #

# ACM Certificates used by CloudFront _must_ be issued from the us-east-1 region.
# See: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html
resource "aws_acm_certificate" "site" {
  provider = aws.us_east_1

  domain_name       = var.domain_name
  validation_method = "DNS"
  key_algorithm     = "RSA_2048" # I kept getting SSL_ERROR_NO_CYPHER_OVERLAP errors with ECDSA ciphers...

  subject_alternative_names = [
    "www.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# This resource does not represent a real-word entity.
# This resource is used to wait for ACM validation to complete.
resource "aws_acm_certificate_validation" "site" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# --------------------------------------------------------------------------- #
#                          Configure the S3 buckets                           #
# --------------------------------------------------------------------------- #

resource "aws_s3_bucket" "buckets" {
  for_each = toset([local.site_bucket.name, local.logs_bucket.name])

  bucket = each.value
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse_s3" {
  for_each = {
    for bucket in [local.site_bucket.name, local.logs_bucket.name] :
    bucket => aws_s3_bucket.buckets[bucket].id
  }

  bucket = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "buckets" {
  for_each = {
    for bucket in [local.site_bucket, local.logs_bucket] :
    bucket.name => {
      id        = aws_s3_bucket.buckets[bucket.name].id,
      ownership = bucket.object_ownership
    }
  }

  bucket = each.value.id

  rule {
    object_ownership = each.value.ownership
  }
}

resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = {
    for bucket in [local.site_bucket, local.logs_bucket] :
    bucket.name => {
      id                  = aws_s3_bucket.buckets[bucket.name].id,
      block_public_access = bucket.block_public_access
    }
  }

  bucket = each.value.id

  block_public_acls       = each.value.block_public_access
  block_public_policy     = each.value.block_public_access
  ignore_public_acls      = each.value.block_public_access
  restrict_public_buckets = each.value.block_public_access
}

resource "aws_s3_bucket_logging" "site_bucket" {
  bucket        = aws_s3_bucket.buckets[local.site_bucket.name].id
  target_bucket = aws_s3_bucket.buckets[local.logs_bucket.name].id
  target_prefix = local.bucket_logs_path
}

# See: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html#oac-permission-to-access-s3
# And: https://repost.aws/knowledge-center/s3-website-cloudfront-error-403
data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid = "CloudFrontAccess"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket" # So users get 404s instead of 403s
    ]

    resources = [
      "${aws_s3_bucket.buckets[local.site_bucket.name].arn}",
      "${aws_s3_bucket.buckets[local.site_bucket.name].arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

# Note: this _may_ need to be created in a funky order wrt the CloudFront resources
# See: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html#create-oac-overview-s3
resource "aws_s3_bucket_policy" "site_bucket" {
  bucket = aws_s3_bucket.buckets[local.site_bucket.name].id
  policy = data.aws_iam_policy_document.site_bucket.json
}

data "aws_iam_policy_document" "logs_bucket" {
  statement {
    sid = "S3PutAccessLogs"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    effect  = "Allow"
    actions = ["s3:PutObject*"]

    resources = [
      "${aws_s3_bucket.buckets[local.logs_bucket.name].arn}",
      "${aws_s3_bucket.buckets[local.logs_bucket.name].arn}/${local.bucket_logs_path}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "logs_bucket" {
  bucket = aws_s3_bucket.buckets[local.logs_bucket.name].id
  policy = data.aws_iam_policy_document.logs_bucket.json
}

resource "aws_s3_bucket_lifecycle_configuration" "logs_bucket" {
  bucket = aws_s3_bucket.buckets[local.logs_bucket.name].id

  rule {
    id     = "logs"
    status = "Enabled"

    filter {
      prefix = "${local.logs_root_path}/"
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

# --------------------------------------------------------------------------- #
#                    Configure the CloudFront Distribution                    #
# --------------------------------------------------------------------------- #

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = local.origin_id
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "this" {
  name = "${local.sanitized_domain}-cdn-response-headers-policy"

  # Probably worth a skim: https://infosec.mozilla.org/guidelines/web_security
  security_headers_config {
    # Note: the X-XSS-Protection is intentionally NOT set
    # See: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-XSS-Protection

    # Set HSTS header
    # See: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security
    strict_transport_security {
      access_control_max_age_sec = 31536000 # 1 year
      include_subdomains         = true
      override                   = true
      preload                    = true
    }

    # Set Referrer-Policy header
    # See: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Referrer-Policy
    referrer_policy {
      referrer_policy = "strict-origin"
      override        = true
    }

    # Set X-Frame-Options header
    # See: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Frame-Options
    frame_options {
      frame_option = "DENY"
      override     = true
    }

    # Set X-Content-Type-Options header
    # See: https://infosec.mozilla.org/guidelines/web_security#x-content-type-options
    content_type_options {
      override = true
    }

    # Set Content-Security-Policy header
    # See: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy
    content_security_policy {
      # You can evaluate the quality of this CSP using https://observatory.mozilla.org/analyze/dozen-donuts.com?third-party=false
      content_security_policy = "default-src 'none'; object-src 'none'; frame-ancestors 'none'; base-uri ${var.domain_name} www.${var.domain_name}; form-action ${var.domain_name} www.${var.domain_name}; connect-src ${var.domain_name} www.${var.domain_name}; script-src ${var.domain_name} www.${var.domain_name}; style-src ${var.domain_name} www.${var.domain_name} 'unsafe-inline'; img-src ${var.domain_name} www.${var.domain_name}; font-src ${var.domain_name} www.${var.domain_name}"
      override                = true
    }
  }

  # When visiting the site from https://www.${var.domain_name}, some resources are not loaded
  # properly because the requests are considered as coming from a different origin. This block
  # configures the 'www.' domain as an allowed origin.
  cors_config {
    access_control_allow_credentials = false
    origin_override                  = true

    access_control_allow_headers {
      items = [
        "Accept-Encoding" # so clients can accept gzip-compressed data
      ]
    }

    access_control_allow_methods {
      items = [
        "GET",
        "HEAD"
      ]
    }

    access_control_allow_origins {
      items = [
        "https://www.${var.domain_name}"
      ]
    }

    access_control_expose_headers {
      items = []
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  comment             = "${var.domain_name} Distribution"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.cloudfront_price_class
  default_root_object = var.default_root_object

  aliases = [
    var.domain_name,
    "www.${var.domain_name}"
  ]

  origin {
    origin_id                = local.origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
    domain_name              = aws_s3_bucket.buckets[local.site_bucket.name].bucket_regional_domain_name
  }

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.buckets[local.logs_bucket.name].bucket_domain_name
    prefix          = local.cloudfront_logs_path
  }

  dynamic "custom_error_response" {
    for_each = var.custom_error_responses

    content {
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
    }
  }

  default_cache_behavior {
    target_origin_id           = local.origin_id
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this.id
    compress                   = true                # Compress when `Accept-Encoding: gzip` is set
    viewer_protocol_policy     = "redirect-to-https" # Goal: https-only
    min_ttl                    = 0
    default_ttl                = 86400    # 1 day
    max_ttl                    = 31536000 # 1 year

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.auto_index.arn
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.site.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021" # Newest available when going through the Console
  }

  restrictions {
    geo_restriction {
      restriction_type = var.cloudfront_restrictions.restriction_type
      locations        = var.cloudfront_restrictions.locations
    }
  }
}

# Function to automatically add the trailing `/index.html` to page requests.
resource "aws_cloudfront_function" "auto_index" {
  provider = aws.us_east_1

  name    = "auto-index"
  runtime = "cloudfront-js-1.0"
  comment = "Automatically add 'index.html' to page requests for ${var.domain_name}"
  publish = true
  code    = file("${path.module}/auto-index.js")
}
