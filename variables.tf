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

variable "common_tags" {
  description = "Tags to apply to all taggable resources"
  type        = map(any)
  default     = {}
}

variable "domain_name" {
  description = "The domain name to use for the site"
  type        = string
}

variable "alternative_names" {
  description = "Any other domains or subdomains to use for this site"
  type        = list(string)
  default     = []
}

variable "create_route53_zone" {
  description = "If true, create a Route53 Public Hosted Zone & manage DNS records"
  type        = bool
  default     = true
}

variable "auto_acm_validation" {
  description = "If true, automatically validate ACM certs as part of the apply; requires managed Route53 Public Hosted Zone"
  type        = bool
  default     = true
}

variable "route53_records" {
  description = "List of additional Route53 records to add to the managed Route53 Public Hosted Zone"
  default     = []

  type = list(object({
    name    = string,                 # Name of the record to add
    type    = string,                 # The record type. Options: A, AAAA, CAA, CNAME, DS, MX, NAPTR, NS, PTR, SOA, SPF, SRV and TXT
    ttl     = optional(number, 3600), # Required for non-alias records. In seconds, defaults to 1hr.
    records = optional(list(string)), # Required for non-alias records

    # Conflicts with 'ttl' and 'records'
    alias = optional(object({
      name               = string,              # DNS domain name for a CloudFront distribution, S3 bucket, ELB, or another resource record set in this hosted zone
      zone_id            = string,              # Hosted zone ID for a CloudFront distribution, S3 bucket, ELB, or Route 53 hosted zone
      eval_target_health = optional(bool, true) # Set to true if you want Route 53 to determine whether to respond to DNS queries using this resource record set by checking the health of the resource record set
    }))
  }))
}

variable "s3_logs_bucket_paths" {
  description = "Configure the paths to which logs are saved in the logs bucket"
  default     = {} # Use the default paths unless specified

  type = object({
    logs_root_path  = optional(string, "logs")
    s3_logs_subpath = optional(string, "s3"), # These will be joined as "${logs_root_path}/${xx_logs_subpath}"
    cf_logs_subpath = optional(string, "cf")  # For example, "logs/s3" and "logs/cf"
  })
}

variable "cf_default_root_object" {
  description = "The default root object for CloudFront to use"
  type        = string
  default     = "index.html"
}

variable "cf_custom_error_responses" {
  description = "Custom error response configurations for the CloudFront Distribution"
  default     = []

  type = list(object({
    error_caching_min_ttl = optional(number, 60),
    error_code            = number,
    response_code         = number,
    response_page_path    = string
  }))
}

variable "cf_price_class" {
  description = "Price class of the CDN. See https://aws.amazon.com/cloudfront/pricing/ for details."
  type        = string
  default     = "PriceClass_100" # Cheapest; only NA + Europe. Options: PriceClass_100, PriceClass_200, PriceClass_All
}

variable "cf_restrictions" {
  description = "Whitelist or blacklist certain regions, or place no restrictions on viewing your content."
  default     = {} # Default to no restrictions

  type = object({
    restriction_type = optional(string, "none"),  # Options are 'whitelist', 'blacklist', and 'none'
    locations        = optional(list(string), []) # Country codes affected; see https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
  })
}

# Configure which headers (if any) CloudFront should remove from responses.
# CloudFront disallows removing a number of headers.
# See: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/understanding-response-headers-policies.html#understanding-response-headers-policies-remove-headers
variable "cf_remove_headers" {
  description = "List of headers to remove from responses to clients."
  type        = list(string)

  # By default, filter some headers that reveal details about the underlying AWS
  # infrastructure.
  default = [
    "server",                      # Reveals the 'AmazonS3' server
    "etag",                        # Value specific to S3 buckets
    "x-amz-server-side-encryption" # Reveals the S3-SSE scheme
  ]
}

# Configure which headers (if any) CloudFront should add to responses.
variable "cf_custom_headers" {
  description = "Map of headers to add to responses to clients."
  type        = map(string)
  default     = {}
}

# Configure CloudFront Functions to customize distribution behaviors.
variable "cf_functions" {
  description = "Configure CloudFront Functions to customize distribution behaviors."
  default     = {}

  type = map(object({
    event_type       = string,                                # Event the function processes; viewer-request or viewer-response
    function_name    = optional(string)                       # If unset, generate a default name based on event_type and the map key
    function_runtime = optional(string, "cloudfront-js-2.0"), # JS runtime; cloudfront-js-1.0 or cloudfront-js-2.0
    function_code    = string                                 # The source code for the function
    function_comment = optional(string)                       # Description for the function
  }))
}
