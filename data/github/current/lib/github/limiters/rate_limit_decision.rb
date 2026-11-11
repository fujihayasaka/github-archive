# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    # Public: Shared library for rate limit decision observability.
    #
    # Provides helpers to emit Hydro events and build response headers for
    # rate limit decisions.  Can be called as module-level methods or mixed
    # into a class.
    #
    #   GitHub::Limiters::RateLimitDecision.emit_hydro_event(
    #     rule_name: "api/auth-fingerprint-by-path",
    #     limit_key: "octocat",
    #     limit: 5000,
    #     cost: 1,
    #     request_id: "abc-123",
    #   )
    #
    module RateLimitDecision
      extend self

      HYDRO_SCHEMA = "hydro.schemas.ratelimit.v0.RateLimitDecision"
      SOURCE_APP = "github"
      HEADER_VERSION = "v0"

      # Public: Whether the GH-Rate-Limit-Decision response header should be included.
      #
      # Returns false on enterprise and when the feature flag is disabled.
      sig { returns(T::Boolean) }
      def include_response_header?
        return false if GitHub.enterprise?

        FeatureFlag.vexi.enabled?(:rate_limit_decision_response_header, default: false)
      end

      # Public: Build the GH-Rate-Limit-Decision response header value.
      #
      # rule_name     - String identifying the limiter rule.
      # limit_key     - Optional String key identifying what is being limited.
      # limit         - Optional Integer limit threshold.
      # cost          - Optional Integer cost of the request.
      # current_actor - Optional String login of the rate-limited user.
      #
      # Returns a String header value.
      sig do
        params(
          rule_name: String,
          limit_key: T.untyped,
          limit: T.untyped,
          cost: T.untyped,
          current_actor: T.nilable(String),
        ).returns(String)
      end
      def response_header(rule_name:, limit_key: nil, limit: nil, cost: nil, current_actor: nil)
        "v:#{HEADER_VERSION},sa:#{SOURCE_APP},rn:#{rule_name},lk:#{limit_key || "unknown"},l:#{limit || "unknown"},c:#{cost || "unknown"},ca:#{current_actor || "unknown"}"
      end

      # Public: Whether rate limit decision Hydro events should be emitted.
      #
      # Returns false on enterprise and when the feature flag is disabled.
      sig { returns(T::Boolean) }
      def emit_hydro_event?
        return false if GitHub.enterprise?

        FeatureFlag.vexi.enabled?(:rate_limit_decision_hydro_event, default: false)
      end

      # Public: Emit a Hydro event with rate limit decision details.
      #
      # rule_name  - String identifying the limiter rule (e.g. "api/auth-fingerprint-by-path").
      # limit_key  - Optional String key identifying what is being limited.
      # limit      - Optional Integer limit threshold.
      # cost       - Optional Integer cost of the request.
      # request_id - Optional String request ID (from X-GitHub-Request-Id header).
      #
      # Returns nothing.
      sig do
        params(
          rule_name: String,
          limit_key: T.untyped,
          limit: T.untyped,
          cost: T.untyped,
          request_id: T.nilable(String),
        ).void
      end
      def emit_hydro_event(rule_name:, limit_key: nil, limit: nil, cost: nil, request_id: nil)
        normalized_rule_name = rule_name.presence || "unknown"

        message = {
          source_app: SOURCE_APP,
          rule_name: normalized_rule_name,
        }

        message[:limit_key] = limit_key if limit_key
        message[:limit] = limit if limit
        message[:cost] = cost if cost
        message[:request_id] = request_id if request_id

        GitHub.hydro_publisher.publish(
          message,
          schema: HYDRO_SCHEMA,
          topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
        )
      rescue => e
        GitHub.logger.error("Failed to emit rate limit decision hydro event: #{e.message}")
        error_tags = ["rule_name:#{normalized_rule_name}", "error:#{e.class.name}"]
        error_tags << "cause:#{e.cause.class.name}" if e.cause
        GitHub.dogstats.increment("limiters.rate_limit_decision.hydro_event.error", tags: error_tags)
      end
    end
  end
end
