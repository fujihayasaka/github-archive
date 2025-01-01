# frozen_string_literal: true

require "feature_flags"

# configure feature flags a la https://github.com/github/feature-flags-client-ruby
FeatureFlags.configure do |config|
  github_api_base_url = ENV.fetch("GITHUB_API_BASE_URL", nil)
  if github_api_base_url.blank?
    github_api_base_url = "http://api.github.localhost"
  end
  url_to_use = "#{github_api_base_url}/internal/twirp"

  config.twirp_url = url_to_use
  # This HMAC and the default GITHUB_API_BASE_URL will work against a co-located github service.
  config.hmac_key = ENV.fetch("GITHUB_API_FEATURES_HMAC", "launchhmac")
  config.cache = ActiveSupport::Cache::RedisCacheStore.new(redis: AdvisoryDB.redis)
  config.cache_expiration = 10.seconds
end

AdvisoryDB::Application.extend(FeatureFlags)
Rails.application.reloader.to_prepare do
  AdvisoryDB::Application.connect_feature_flags_client
end
