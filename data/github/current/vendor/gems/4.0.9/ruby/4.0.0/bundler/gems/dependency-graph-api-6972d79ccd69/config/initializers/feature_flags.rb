# frozen_string_literal: true

require "feature_flags"

redis_enabled = !ENV["DEPENDENCY_GRAPH_REDIS_CACHE_URL"].blank?
config = Rails.application.config_for(:monolith).with_indifferent_access
monolith_api_url = config.fetch(:base_uri, "")
monolith_hmac_key = config.fetch(:client_key, "")

raise ConfigNotFoundError.new "base_uri must not be blank (config/monolith.yml, environment: #{Rails.env})" if monolith_api_url.blank?

FeatureFlags.configure do |config|
  config.twirp_url = "#{monolith_api_url}/twirp"
  config.hmac_key = monolith_hmac_key

  if redis_enabled
    config.cache = Rails.cache
    config.cache_expiration = 1.minute
  end
end

DependencyGraph.extend(FeatureFlags)
Rails.application.reloader.to_prepare do
  DependencyGraph.connect_feature_flags_client
end
