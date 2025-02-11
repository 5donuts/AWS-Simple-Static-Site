# AWS Simple Static Site

An OpenTofu module to economically host a static site on AWS using S3 and CloudFront.

> [!WARNING]
> Below version `1.0.0`, this project may have breaking changes on minor release versions.
> Additionally, the `main` branch is the development branch and there may be breaking changes
> on commits. Starting at version `1.0.0`, this project will follow SemVer guidelines with
> respect to breaking changes.

## Using this module

To use this module to deploy the AWS infrastructure to deploy a static site of your own, you'll need to configure your providers
as follows:

```tf
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"

      # Some resources _must_ be deployed in the us-east-1 region
      configuration_aliases = [aws.us_east_1]
    }
  }
}

# Choose your preferred region here. Most resources will be deployed in this region.
provider "aws" {
  region = "us-east-2"
}

# This region _must_ be the `us-east-1` region; some resources _must_ be deployed in this region.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

Then, you can use this module as follows:
```tf
module "static_site" {
  source = "github.com/5donuts/AWS-Simple-Static-Site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name = "example.com"
}
```

This will create a CloudFront Distribution with an S3 origin and the correct Route53 records to serve the site as well as an
ACM certificate to serve it over HTTPS.

See the **Variables** section for details on how to customize the module to fit your needs.

## Publishing/Updating the site

After deploying the site infrastructure, you should create your static site using the SSG of your choice.
Popular options include [Hugo](https://gohugo.io/) and [Jekyll](https://jekyllrb.com/).
I personally like [Zola](https://www.getzola.org/), a static site generator written in Rust.
You can find many more options on [Jamstack](https://jamstack.org/generators/).

Once you've created your site you can upload the content to S3 with:
```bash
$ aws s3 sync --delete /path/to/your/site/content s3://$(tofu output -raw site_content_bucket)
```

If you're updating content on your site, you'll also need to create a CloudFront Invalidation to update the CDN caches:
```bash
$ aws cloudfront create-invalidation --distribution-id $(tofu output -raw cloudfront_distribution_id) --paths "/*"
```

## Cost

If you deploy this module, it will cost the following:
* $0.50/mo for the Route53 Hosted Zone (potentially more if you have millions of DNS requests each month)
* The (very small) cost to store & serve S3 objects through CloudFront; in my case $0.02/mo.

It's an economical way to host a static site using a CSP, though you can certainly have significant savings by moving to a different
DNS provider (e.g., Cloudflare).

## Variables

The following is a listing of each variable you can use to customize this module with a type, a description, as well as example
usage, where appropriate.

**`common_tags`**

Description: `Tags to apply to all taggable resources`
Type: `map(any)`
Default: `{}`

Use this variable to apply tags (for example, user-defined cost allocation tags) to all taggable resources created by this module.

Example usage:
```tf
common_tags = {
  Website   = "example.com",
  ManagedBy = "Terraform"
}
```

**`domain_name`

Description: `The domain name to use for the site`
Type: `string`

Specify the domain name to use for this site.
Note that this will be the apex of the Route53 Hosted Zone.
The module will automatically create a `www.` record for the site.

If your site needs to be deployed as a subdomain, you should set `create_route53_zone = false` and manage DNS yourself.

**`create_route53_zone`**

Description: `If true, create a Route53 Public Hosted Zone & manage DNS records`
Type: `bool`
Default: `true`

Set this to false if you do not want the module to create a Route53 Public Hosted Zone for your domain.
Scenarios where you wouldn't want the module to create a hosted zone include:
* You already manage DNS for your site elsewhere
* You need to deploy the site as a subdomain

**`auto_acm_validation`**

Description: `If true, automatically validate ACM certs as part of the apply; requires managed Route53 Public Hosted Zone`
Type: `bool`
Default: `true`

This module generates an ACM certificate configured to use DNS-based validation.
If this variable is `true`, the module will automatically add the validation records to the Route53 Hosted Zone (assuming that
`create_route53_zone = true`).
Otherwise, the validation records will be provided as module outputs.

**`route53_records`**

Description: `List of additional Route53 records to add to the managed Route53 Public Hosted Zone`
Default: `[]`
Type:
```tf
list(object({
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
```

If you wanted to add `MX` records to your site, you could do so with something like:
```tf
route53_records = [
  {
    name = "",
    type = "MX",
    records = [
      "10 mail.myemailprovider.site."
    ]
  },
  {
    name = "_dmarc",
    type = "TXT",
    records = [
      "v=DMARC1; p=quarantine"
    ]
  },
  {
    name = "",
    type = "TXT",
    records = [
      "v=spf1 include:_spf.myemailprovider.site mx ~all"
    ]
  }
]
```

Note that the above example is _far_ from a complete guide to setting up email for your domain.
I recommend reading [this blog post](https://proton.me/support/custom-domain) if you intend on using an established email
provider for your site.
While that specific post is for Proton, the steps will largely be the same irrespective of email provider.

Alternatively, I can also recommend [_Run Your Own Mail Server_](https://mwl.io/nonfiction/tools#ryoms) by Michael Lucas.

**`s3_logs_bucket_paths`**

Description: `Configure the paths to which logs are saved in the logs bucket`
Default: `{}`
Type:
```tf
object({
  logs_root_path  = optional(string, "logs")
  s3_logs_subpath = optional(string, "s3"), # These will be joined as "${logs_root_path}/${xx_logs_subpath}"
  cf_logs_subpath = optional(string, "cf")  # For example, "logs/s3" and "logs/cf"
})
```

You shouldn't need to use this argument, unless you imported an S3 bucket to use as the logs bucket for this module.
In that case, specify the paths in that imported bucket where S3 Access Logs and CloudFront Standard Logs should be written.

**`cf_default_root_object`**

Description: `The default root object for CloudFront to use`
Type: `string`
Default: `index.html`

This is the object in the S3 bucket that CloudFront will serve when a visitor accesses the root (`/`) of the site.
If you are using a Static Site Generator, it is very likely to be `index.html`.

**`cf_custom_error_responses`**

Description: `Custom error response configurations for the CloudFront Distribution`
Default: `[]`
Type:
```tf
list(object({
  error_caching_min_ttl = optional(number, 60),
  error_code            = number,
  response_code         = number,
  response_page_path    = string
}))
```

Configure [custom error responses](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/GeneratingCustomErrorResponses.html).
For example, to use a custom `404` page you could use the following:
```tf
cf_custom_error_responses = [
  {
    error_caching_min_ttl = 60,
    error_code            = 404,
    response_code         = 404,
    response_page_path    = "/404.html"
  }
]
```

**`cf_price_class`**

Description: `Price class of the CDN. See https://aws.amazon.com/cloudfront/pricing/ for details.`
Type: `string`
Default: `PriceClass_100`

By default, use the cheapest price class.
If you want your site to have better performance outside North America and Europe, you should consider using a more expensive
price class.

**`cf_restrictions`**

Description: `Whitelist or blacklist certain regions, or place no restrictions on viewing your content.`
Default: `{}`
Type:
```tf
object({
  restriction_type = optional(string, "none"),  # Options are 'whitelist', 'blacklist', and 'none'
  locations        = optional(list(string), []) # Country codes affected; see https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
})
```

Optionally place geographical restrictions on your content.
For details, see [the AWS docs](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/georestrictions.html).

**`cf_remove_headers`**

Description: `List of headers to remove from responses to clients`
Type: `list(string)`
Default:
```tf
[
  "server",                      # Reveals the 'AmazonS3' server
  "etag",                        # Value specific to S3 buckets
  "x-amz-server-side-encryption" # Reveals the S3-SSE scheme
]
```

This is the list of HTTP headers CloudFront will remove from responses to clients.
Note that not all headers can be removed by CloudFront.
For details, see [the AWS docs](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/understanding-response-headers-policies.html#understanding-response-headers-policies-remove-headers).

**`cf_custom_headers`**

Description: `Map of headers to add to responses to clients`
Type: `map(string)`
Default: `{}`

Use this variable to add custom headers to responses.
For example, if you wanted to configure the `X-Robots-Tag` header you could use the following:
```tf
cf_custom_headers = {
  # Set the X-Robots-Tag header
  # See: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Robots-Tag
  # This has a number of standard and non-standard directives that (should)
  # prevent any crawler, including AI crawlers, from visiting the site. Of course,
  # many of them don't actually care about things like this so it's kind of moot.
  "X-Robots-Tag" = join(", ", [
    "none",
    "noindex",
    "nofollow",
    "noarchive",
    "nosnippet",
    "noimageindex",
    "nocache",
    "notranslate",
    "noai",
    "noimageai",
    "max-image-preview: none",
    "max-video-preview: 0",
  ])
}
```

**`cf_functions`**

Description: `Configure CloudFront Functions to customize distribution behaviors`
Default: `{}`
Type:
```tf
map(object({
  event_type       = string,                                # Event the function processes; viewer-request or viewer-response
  function_name    = optional(string)                       # If unset, generate a default name based on event_type and the map key
  function_runtime = optional(string, "cloudfront-js-2.0"), # JS runtime; cloudfront-js-1.0 or cloudfront-js-2.0
  function_code    = string                                 # The source code for the function
  function_comment = optional(string)                       # Description for the function
}))
```

Configure [CloudFront Functions](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-functions.html) to
customize the behavior of the distribution.

For example, to customize the behavior of the distribution for `viewer-request` events you could use:
```tf
cf_functions = {
  # My custom viewer-request function
  Viewer-Request = {
    function_name    = "my-viewer-request-fn"
    event_type       = "viewer-request",
    function_comment = "Process viewer-request events for ${var.domain_name}"
    function_code    = file("${path.module}/scripts/viewer-request-fn.js")
  }
}
```

## License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
