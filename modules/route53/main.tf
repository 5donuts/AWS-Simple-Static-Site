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

resource "aws_route53_zone" "this" {
  name = var.domain_name

  lifecycle {
    # AWS charges $0.50 per hosted zone, per month, up to a maximum of 25 hosted zones ($12.50).
    # If (for whatever reason) you kept destroying & re-creating this hosted zone within a one month
    # period, you could rack up Route53 expenses for no real reason. So, we prevent accidental
    # destruction of the hosted zone.
    prevent_destroy = true
  }
}

# Create any non-alias Route53 records
resource "aws_route53_record" "non_alias" {
  for_each = {
    for record in var.route53_records : "${record.name == "" ? "@" : record.name}.${substr(md5(record.records[0]), 0, 5)}" => record if record.alias == null
  }

  zone_id = aws_route53_zone.this.zone_id

  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records
}

# Create any alias Route53 records
resource "aws_route53_record" "alias" {
  for_each = {
    for record in var.route53_records : "${record.name == "" ? "@" : record.name}.${substr(md5(record.records[0]), 0, 5)}" => record if record.alias != null
  }

  zone_id = aws_route53_zone.this.zone_id

  name = each.value.name
  type = each.value.type

  alias {
    name                   = each.value.alias.name
    zone_id                = each.value.alias.zone_id
    evaluate_target_health = each.value.alias.eval_target_health
  }
}
