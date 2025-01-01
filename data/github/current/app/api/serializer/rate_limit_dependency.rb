# typed: true
# frozen_string_literal: true

module Api::Serializer::RateLimitDependency
  def rate_limit_statuses_hash(rate_limit_statuses, options = {})
    options = Api::SerializerOptions.from(options)

    resources_hash = {}
    rate_limit_statuses.map do |family, rate_limit_status|
      rate_hash = {
        limit: rate_limit_status.max_tries,
        used: rate_limit_status.tries,
        remaining: rate_limit_status.remaining,
        reset: rate_limit_status.expires_at.to_i,
      }

      resources_hash[family] = rate_hash
    end

    result = {
      resources: resources_hash,
      rate: resources_hash[Api::RateLimitConfiguration::DEFAULT_FAMILY],
    }

    if options.changeset_active?(:remove_rate_limit_rate)
      result.delete(:rate)
    end

    result
  end
end
