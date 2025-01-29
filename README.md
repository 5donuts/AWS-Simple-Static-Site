# AWS Simple Static Site

An OpenTofu module to economically host a static site on AWS using S3 and CloudFront.

> [!WARNING]
> Below version `1.0.0`, this project may have breaking changes on minor release versions.
> Additionally, the `main` branch is the development branch and there may be breaking changes
> on commits. Starting at version `1.0.0`, this project will follow SemVer guidelines with
> respect to breaking changes.

## Configuration

If you want to deploy the site with the default configuration options, you can simply run `tofu apply`.
You'll be prompted to enter the domain name of the site (note: you'll have to purchase this separately), then OpenTofu will spin up the AWS resources to run the site.

Alternatively, you can create a `tofu.auto.tfvars` file and override default values there.
For example:
```
domain_name = "example.com"

custom_error_responses = [
  {
    error_caching_min_ttl = 60,
    error_code            = 404,
    response_code         = 404,
    response_page_path    = "/404.html"
  }
]
```

See `variables.tf` for a full list of options you can override.

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

If you deploy a site with this module, you'll spend at least $0.50/mo on Route53 costs (potentially more if your site gets heavy traffic).
Additionally, you'll spend anywhere from a couple to a couple dozen cents per month on S3 costs, depending on the volume of logs CloudFront
generates and the volume of data viewers request from your site.

Overall, it's an economical way to host a static site using a CSP.

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
