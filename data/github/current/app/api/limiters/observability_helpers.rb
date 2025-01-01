# typed: true
# frozen_string_literal: true

module Api::Limiters::ObservabilityHelpers
  extend T::Helpers

  requires_ancestor { GitHub::Limiter }

  GH_API_LOG_PREFIX = "gh.api"

  def add_to_log_data(limiter_prefix, log_data, key, user_agent, cost, current, max)
    log_data["#{GH_API_LOG_PREFIX}.#{limiter_prefix}.limiter"] = name
    log_data["#{GH_API_LOG_PREFIX}.#{limiter_prefix}.key"] = key
    log_data["#{GH_API_LOG_PREFIX}.#{limiter_prefix}.user_agent"] = user_agent
    log_data["#{GH_API_LOG_PREFIX}.#{limiter_prefix}.current"] = current
    log_data["#{GH_API_LOG_PREFIX}.#{limiter_prefix}.max"] = max
    if cost
      log_data["#{GH_API_LOG_PREFIX}.#{limiter_prefix}.cost"] = cost
    end
  end

  def post_to_datadog(key, current, max, kind:, evaluation: false)
    return unless GitHub.flipper[:post_request_data_to_datadog].enabled?

    percentage = current / max.to_f
    tags = ["key:#{key}", "kind:#{kind}", "limiter:#{name}", "evaluation:#{evaluation}"]

    GitHub.dogstats.gauge("api.limiter.gauge.current", current, tags: tags)
    GitHub.dogstats.gauge("api.limiter.gauge.percent", percentage, tags: tags)
  end
end
