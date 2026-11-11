# frozen_string_literal: true

require "monolith_feature_flags"

# This initializes the monolith's centrally-managed feature flags for use in
# DependabotAPI.
#
# These are managed via the Web UI here:
#   https://admin.github.com/devtools/feature_flags
FeatureFlags.configure do |config|
  config.twirp_url = URI.join(Dependabot::Application.target_github_internal_api_endpoint, "internal/twirp")
  config.hmac_key = Prius.get(:github_internal_twirp_hmac_key)
  config.cache = Rails.cache # optional
  config.cache_expiration = 1.minute # optional, defaults to 60 seconds
end

# We access FeatureFlags via a wrapper which provides metrics and a
# circuit-breaker
Dependabot::Application.extend(MonolithFeatureFlags)
Rails.application.reloader.to_prepare do
  Dependabot::Application.connect_monolith_feature_flags_client
end
