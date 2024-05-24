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

variable "primary_region" {
  type        = string
  default     = "us-east-1"
  description = "The AWS region in which to provision most resources. Some resources _must_ be provisioned in us-east-1 (e.g., CloudFront distributions)"
}

variable "default_tags" {
  type        = map(any)
  description = "Default tags to apply to taggable resources"

  default = {
    Provisioner = "OpenTofu"
    Application = "AWS Simple Static Site"
  }
}
