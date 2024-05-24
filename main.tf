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
    block_public_access = true
    object_ownership    = "BucketOwnerEnforced"
  }

  logs_root_path   = "logs"
  bucket_logs_path = "${local.logs_root_path}/origin"
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
  for_each = { for record in var.var.route53_records : "${record.name == "" ? "@" : record.name}.${substr(md5(record.records[0]), 0, 5)}" => record if record.alias == null }

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
