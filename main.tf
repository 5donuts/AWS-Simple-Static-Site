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
