data "http" "gh_ips" {
  url = "https://api.github.com/meta"
  request_headers = {
    Accept = "application/json"
  }
}

locals {
  github_ipv4_ips = [for x in jsondecode(data.http.gh_ips.response_body)["hooks"] : x if length(regexall(":", x)) == 0]
  ip_rules = concat(
    length(var.additional_ips_to_allow) > 0 ? var.additional_ips_to_allow : [],
    var.allow_gh_dcs ? local.github_ipv4_ips : []
  )
}
