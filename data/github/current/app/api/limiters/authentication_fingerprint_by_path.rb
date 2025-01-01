# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class AuthenticationFingerprintByPath < GitHub::Limiters::MemcachedWindow
      include Api::Limiters::ObservabilityHelpers
      include Api::Limiters::Helpers

      LOG_DATA_PREFIX = "auth_fingerprint_path"

      # view modification and changes to regex at: https://rubular.com/r/rqUMu0hQkoChdU
      ENTERPRISE_SCIM_ENDPOINT_REGEX = /\/scim\/v2\/enterprises\/([\w-]+)\/[Users|Groups]+/
      ENTERPRISE_SCIM_LIMIT_MULTIPLIER = 100

      RATE_LIMIT_ENDPOINT_REGEX = /\/rate_limit/
      RATE_LIMIT_ENDPOINT_MULTIPLIER = 6

      CUSTOM_COSTS = {
        # /app/installations/:installation_id/access_tokens
        # This endpoint is heavily itilized by GitHub Apps to generate tokens
        # hourly for installations.
        # See: https://github.com/github/partner-engineering/issues/289#issuecomment-503771913
        %r{\A/app/installations/\d+/access_tokens(/|\z)} => 2,

        # /app/global/access_tokens
        # This endpoint is heavily utilized by GitHub Actions to generate tokens,
        # especially hourly when most scheduled workflows are running.
        # See: https://github.com/github/actions-launch/issues/383
        %r{\A/app/global/access_tokens\z} => 2,

        # /applications/:client_id/token
        # This endpoint checks a token's validity, it does
        # incure more CPU time than any other GET.
        #
        # See https://github.com/github/ecosystem-apps/issues/946 for more details.
        %r{\A/applications/\w+/token\z} => 1,

        # /scim/v2/
        # These endpoints are used by Identity Providers (AAD and Okta) to
        # provision users and groups.
        #
        %r{\A/scim/v2/.*} => 1,
      }

      include GitHub::Middleware::Constants

      def initialize(name = "authentication-fingerprint-by-path", max:)
        @max = max
        super(name, limit: max)
      end

      def record_start(request)
        # If the path is for GraphQL or Twirp we want to not cost the request.
        graphql_path = Api::Limiters::GraphQLAuthenticationFingerprint.graphql_path(request)
        twirp_path = Api::Limiters::TwirpAuthenticationFingerprintByPath.twirp_path(request)

        if graphql_path.present? || twirp_path.present?
          return OK
        end

        cur_limit = increment_counter(request)

        if GitHub::Routers::Api.internal_api_host?(request.host) && GitHub.multi_tenant_enterprise?
          if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
            add_to_log_data(LOG_DATA_PREFIX, log_data, key(request), http_user_agent(request), cost(request), cur_limit, @max)
          end

          unless auth_type(request) == :other
            post_to_datadog(key(request), cur_limit, @max, kind: "auth_fingerprint_by_path")
          end
        end
      end

      protected

      def at_limit?(request)
        if ENTERPRISE_SCIM_ENDPOINT_REGEX.match(request.path_info)
          # regex will get the business slug or id
          enterprise_slug_or_id = $1

          business = if enterprise_slug_or_id.match(/\d+/)
            Business.find_by(id: enterprise_slug_or_id.to_i)
          else
            Business.find_by(slug: enterprise_slug_or_id)
          end

          if business && GitHub.flipper[:scim_rate_limiting_multiplier].enabled?(business)
            max = limit(request) * ENTERPRISE_SCIM_LIMIT_MULTIPLIER
            max > 0 && val(key(request)) >= max
          else
            super
          end
        elsif RATE_LIMIT_ENDPOINT_REGEX.match(request.path_info)
          max = limit(request) * RATE_LIMIT_ENDPOINT_MULTIPLIER
          max > 0 && val(key(request)) >= max
        else
          super
        end
      end

      def key(request)
        authentication_fingerprint =
          Api::Middleware::RequestAuthenticationFingerprint.get(request.env).to_s

        hashed_path = Digest::SHA256.hexdigest(request.path_info)
        "#{authentication_fingerprint}:#{hashed_path}"
      end

      def custom_cost_for(path)
        CUSTOM_COSTS.detect { |path_regex, _| path =~ path_regex }
      end

      # Mutating methods often incur more CPU time, so let's charge more for
      # those.
      def cost(request)
        if custom_cost = custom_cost_for(request.path_info)
          return custom_cost[1]
        end

        case request.request_method
        when "GET", "HEAD", "OPTIONS"
          1
        else # POST, PATCH, PUT, DELETE
          5
        end
      end
    end
  end
end
