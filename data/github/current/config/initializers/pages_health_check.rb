# frozen_string_literal: true

# The network proxy is only available from within the VPN, so restrict this to production-like envs.
if Rails.env.production? && ENV["EXTERNAL_COMMUNICATION_PROXY_HOST"]
  GitHubPages::HealthCheck.set_proxy(ENV["EXTERNAL_COMMUNICATION_PROXY_HOST"])
end
