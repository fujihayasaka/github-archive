# typed: strict
# frozen_string_literal: true

module Api::Limiters::TwirpObservabilityHelpers
  extend T::Helpers

  requires_ancestor { GitHub::Limiter }

  sig { params(client: String, current: Integer, maximum: Integer, kind: String, evaluation: T::Boolean).void }
  def post_to_datadog(client, current, maximum, kind:, evaluation: false)
    return unless FeatureFlag.vexi.enabled?(:twirp_api_post_to_datadog, default: false)

    # ensure percentage value is between 0 and 1 (if under threshold) or above 1 (if threshold reached)
    percentage = current / maximum.to_f

    tags = ["kind:#{kind}", "client:#{client}", "limiter:#{name}", "evaluation:#{evaluation}"]

    # gauge metrics will only submit the last value during the flush period
    GitHub.dogstats.gauge("api.twirp.limiter.gauge.current", current, tags: tags)
    GitHub.dogstats.gauge("api.twirp.limiter.gauge.percent", percentage, tags: tags)
  end

  sig { params(client: String, current: Integer, maximum: Integer, evaluation: T::Boolean).void }
  def post_count_limiter_to_datadog(client, current, maximum, evaluation: false)
    return unless FeatureFlag.vexi.enabled?(:twirp_api_post_to_datadog, default: false)

    post_to_datadog(client, current, maximum, kind: "count", evaluation: evaluation)
  end

  sig { params(client: String, current: Integer, maximum: Integer, evaluation: T::Boolean).void }
  def post_elapsed_limiter_to_datadog(client, current, maximum, evaluation: false)
    return unless FeatureFlag.vexi.enabled?(:twirp_api_post_to_datadog, default: false)

    post_to_datadog(client, current, maximum, kind: "elapsed", evaluation: evaluation)
  end
end
