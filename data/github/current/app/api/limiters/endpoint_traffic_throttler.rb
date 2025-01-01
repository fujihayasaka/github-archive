# typed: true
# frozen_string_literal: true

# This module is responsible for implementing a global percentage-based throttling mechanism for API requests.
# It allows requests for an endpoint to be throttled based on a percentage of allowed traffic. In order for an endpoint
# to be throttled it must be added as an actor to one of the feature flags specified in the ALLOWED_TRAFFIC_PERCENTAGE_TIERS hash.
# If an actor is added to multiple tiers the lowest once will be used. If an actor is not added to any tier it will be allowed 100% of the time.
module Api
  module Limiters
    module EndpointTrafficThrottler
      extend T::Helpers

      MAXIMUM_TRAFFIC_PERCENTAGE = { ANON: 90, AUTH: 100 }.freeze
      HIGH_TRAFFIC_PERCENTAGE = { ANON: 75, AUTH: 100 }.freeze
      MEDIUM_TRAFFIC_PERCENTAGE = { ANON: 50, AUTH: 100 }.freeze
      LOW_TRAFFIC_PERCENTAGE = { ANON: 25, AUTH: 80 }.freeze
      MINIMAL_TRAFFIC_PERCENTAGE = { ANON: 10, AUTH: 50 }.freeze
      NONE_TRAFFIC_PERCENTAGE = { ANON: 0, AUTH: 0 }.freeze

      # ALLOWED_TRAFFIC_PERCENTAGE_TIERS is a hash that maps the traffic percentage tiers to their corresponding values.
      # The keys are symbols representing the tier names, and the values are integers representing the allowed traffic percentage.
      # Additionally these tiers map indirectly to the feature flags that are used to determine if a route is in the tier.
      ALLOWED_TRAFFIC_PERCENTAGE_TIERS = T.let({
        # https://devportal.githubapp.com/feature-flags/api_platform_endpoint_throttler_allow_maximum_traffic_routes
        MAXIMUM: MAXIMUM_TRAFFIC_PERCENTAGE,
        # https://devportal.githubapp.com/feature-flags/api_platform_endpoint_throttler_allow_high_traffic_routes
        HIGH: HIGH_TRAFFIC_PERCENTAGE,
        # https://devportal.githubapp.com/feature-flags/api_platform_endpoint_throttler_allow_medium_traffic_routes
        MEDIUM: MEDIUM_TRAFFIC_PERCENTAGE,
        # https://devportal.githubapp.com/feature-flags/api_platform_endpoint_throttler_allow_low_traffic_routes
        LOW: LOW_TRAFFIC_PERCENTAGE,
        # https://devportal.githubapp.com/feature-flags/api_platform_endpoint_throttler_allow_minimal_traffic_routes
        MINIMAL: MINIMAL_TRAFFIC_PERCENTAGE,
        # https://devportal.githubapp.com/feature-flags/api_platform_endpoint_throttler_allow_no_traffic_routes
        NONE: NONE_TRAFFIC_PERCENTAGE,
      }.freeze, T::Hash[Symbol, T::Hash[Symbol, Integer]])

      # allow_request? is a method that determines whether a request to a given route should be allowed based on the
      # global throttler settings and the allowed traffic percentage for the route.
      # Valid auth types are :ANON and :AUTH.
      #
      # This method will always return true if the route is not present in any of the tiers, if there is a misconfiguration
      # in the feature flags/tier map, or if an invalid auth_type is passed.
      sig { params(actor: Api::HashedRouteActor, auth_type: Symbol, log_data: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def self.allow_request?(actor, auth_type, log_data = {})
        global_throttler_enabled = T.let(GitHub.flipper[:api_platform_endpoint_throttler_enabled].enabled?, T::Boolean)
        log_data["gh.api.endpoint_throttler.enabled"] = global_throttler_enabled
        return true unless global_throttler_enabled

        metrics_tags = []
        # the primary reason for instrumenation is to measure the effect of the feature flags checks on the request
        # additionally, we only want to instrument the call if the throttler is enabled
        started_at = Time.now.utc
        allowed_traffic_percentage = get_allowed_traffic_percentage(actor, auth_type, log_data, metrics_tags)

        allowed_traffic_percentage = 100 if !allowed_traffic_percentage.between?(0, 100)
        log_data["gh.api.endpoint_throttler.allowed_traffic_percentage"] = allowed_traffic_percentage
        metrics_tags << "allowed_traffic_percentage:#{allowed_traffic_percentage}"

        allow_request = if allowed_traffic_percentage == 0
          false
        elsif allowed_traffic_percentage == 100
          true
        else
          # kernel.rand is not inclusive on the upper bound so we need to add 1 to the allowed_traffic_percentage
          # to make sure the random number is between 0 and allowed_traffic_percentage
          allowed_traffic_percentage >= Kernel.rand(100 + 1)
        end

        metrics_tags << "request_allowed:#{allow_request}"
        elapsed = GitHub::Dogstats.duration(started_at, Time.now.utc)
        GitHub.dogstats.distribution("api.endpoint_throttler.duration", elapsed, tags: metrics_tags)

        allow_request
      end

      # get_allowed_traffic_percentage returns the allowed traffic percentage for a given route.
      # It checks the feature flags to determine the tier of the route and returns the corresponding percentage.
      # If a route is not present in a tier it will be allowed 100% of the time.
      # If the route is present in multiple tiers, the lowest one will be used.
      # If there is a misconfiguration in the feature flags or tier map, it will return 100% as a fallback.
      sig { params(actor: Api::HashedRouteActor, auth_type: Symbol, log_data: T::Hash[String, T.untyped], metrics_tags: T::Array[String]).returns(Integer) }
      private_class_method def self.get_allowed_traffic_percentage(actor, auth_type, log_data = {}, metrics_tags = [])
        log_data["gh.api.endpoint_throttler.route"] = actor.route_pattern
        log_data["gh.api.endpoint_throttler.actor"] = actor.vexi_id
        log_data["gh.api.endpoint_throttler.auth_type"] = auth_type

        # NOTE: Right now the actor id is a route, but eventually may be replaced by route+JA3+AS hashes.
        # Therefore don't push the actor id to avoid cardinality issues.
        # It is safe to push the route though as other requests like request.dist.time do this.
        metrics_tags.push("route:#{actor.route_pattern}", "auth_type:#{auth_type}")

        # Determine traffic_tier and capture the specific actor that matched
        matched_blocking_actor = nil
        traffic_tier = :MISSING # Default to MISSING

        if (found_actor = actor.blocked_actor(:api_platform_endpoint_throttler_allow_no_traffic_routes))
          traffic_tier = :NONE
          matched_blocking_actor = found_actor
        elsif (found_actor = actor.blocked_actor(:api_platform_endpoint_throttler_allow_minimal_traffic_routes))
          traffic_tier = :MINIMAL
          matched_blocking_actor = found_actor
        elsif (found_actor = actor.blocked_actor(:api_platform_endpoint_throttler_allow_low_traffic_routes))
          traffic_tier = :LOW
          matched_blocking_actor = found_actor
        elsif (found_actor = actor.blocked_actor(:api_platform_endpoint_throttler_allow_medium_traffic_routes))
          traffic_tier = :MEDIUM
          matched_blocking_actor = found_actor
        elsif (found_actor = actor.blocked_actor(:api_platform_endpoint_throttler_allow_high_traffic_routes))
          traffic_tier = :HIGH
          matched_blocking_actor = found_actor
        elsif (found_actor = actor.blocked_actor(:api_platform_endpoint_throttler_allow_maximum_traffic_routes))
          traffic_tier = :MAXIMUM
          matched_blocking_actor = found_actor
        end

        log_data["gh.api.endpoint_throttler.tier"] = traffic_tier
        log_data["gh.api.endpoint_throttler.matched_actor"] = matched_blocking_actor.to_s if matched_blocking_actor
        metrics_tags << "tier:#{traffic_tier}"
        metrics_tags << "asn:#{matched_blocking_actor.asn}" if matched_blocking_actor&.asn&.present?
        metrics_tags << "ja3:#{matched_blocking_actor.ja3}" if matched_blocking_actor&.ja3&.present?

        return 100 if traffic_tier == :MISSING

        tier = ALLOWED_TRAFFIC_PERCENTAGE_TIERS[traffic_tier]
        percentage = tier&.dig(auth_type)
        percentage&.between?(0, 100) ? percentage : 100
      end
    end
  end
end
