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

variable "domain_name" {
  description = "The domain to use for the Route53 Public Hosted Zone"
  type        = string
}

variable "route53_records" {
  description = "Any DNS records to add to the Route53 Public Hosted Zone"
  default     = []

  type = list(object({
    name    = string,                           # Name of the record to add
    type    = string,                           # The record type. Options: A, AAAA, CAA, CNAME, DS, MX, NAPTR, NS, PTR, SOA, SPF, SRV and TXT
    ttl     = optional(number, 3600),           # Required for non-alias records, in seconds. Default: 1hr.
    records = optional(list(string)),           # Required for non-alias records
    alias = optional(object({                   # Conflicts with 'ttl' and 'records'
      name               = string,              # DNS domain name for a CloudFront distribution, S3 bucket, ELB, or another resource record set in this hosted zone
      zone_id            = string,              # Hosted zone ID for a CloudFront distribution, S3 bucket, ELB, or Route 53 hosted zone
      eval_target_health = optional(bool, true) # Set to true if you want Route 53 to determine whether to respond to DNS queries using this resource record set by checking the health of the resource record set
    }))
  }))
}
