# typed: true
# frozen_string_literal: true

# Public: Various methods useful for obtaining the rate limit status for API
# consumers.
#
# See also: Api::RateLimitConfiguration.
module Api::RateLimitStatus
  # Public: Find the current rate limit status for all resource families for a
  # specific API consumer.
  #
  # request_context - An object that describes the request. Specifically, the
  #                   object must respond to #current_user, #current_app, and
  #                   #remote_ip. This information is used to identify the API
  #                   consumer.
  #
  # Returns a Hash where each key is a String representing a resource family
  # name (e.g., "search"), and each value is a RedisRateLimiter::Result instance representing
  # the current rate limit status for that resource family.
  def self.all(request_context)
    families = Api::RateLimitConfiguration::PUBLIC_FAMILIES

    if !FeatureFlag.vexi.enabled?(:audit_log_api_rate_limit, request_context.current_user, default: true) ||
       FeatureFlag.vexi.enabled?(:audit_log_rate_limit_exempt, request_context.current_user, default: false)
      families = families.reject { |fam| fam == "audit_log" || fam == "audit_log_streaming" }
    end

    families_and_rates = families.map do |family|
      config = Api::RateLimitConfiguration.for(family, request_context)
      rate = Api::ConfigThrottler.new(config).check

      [family, rate]
    end

    Hash[families_and_rates]
  end
end
