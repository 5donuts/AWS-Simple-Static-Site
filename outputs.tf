# AWS Simple Static Site - IaC to deploy an economical static site on AWS
# Copyright (C) 2024, 2025  Charles German <5donuts@pm.me>
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

output "route53_hosted_zone_nameservers" {
  # If you purchased the domain name from a registrar other than AWS, you'll need to configure these nameservers
  # as authorities for the domain.
  description = "Nameservers for the Route53 public hosted zone"
  value       = aws_route53_zone.site.name_servers
}

output "s3_site_content_bucket_arn" {
  description = "ARN of the S3 bucket hosting site content"
  value       = aws_s3_bucket.buckets[local.site_bucket.name].arn
}

output "s3_logs_bucket_arn" {
  description = "ARN of the S3 bucket containing S3 & CloudFront logs"
  value       = aws_s3_bucket.buckets[local.logs_bucket.name].arn
}

output "cf_distribution_id" {
  description = "ID of the CloudFront distribution serving the site"
  value       = aws_cloudfront_distribution.this.id
}

output "cf_distribution_arn" {
  description = "ARN of the CloudFront distribution serving the site"
  value       = aws_cloudfront_distribution.this.arn
}
