# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    module Internal
      class AuthenticationFingerprintByPathNoop < GitHub::Limiters::MemcachedWindow
        include Api::Limiters::ObservabilityHelpers
        include Api::Limiters::Helpers
        include Api::Limiters::TwirpHelpers
        include Api::Limiters::GraphqlHelper
        include GitHub::Middleware::Constants

        INTERNAL_AUTH_FING_PATH_NOOP_KEY = "github.api.internal_auth_fingerprint_by_path_noop_limiter"

        CUSTOM_LIMIT_BY_INTEGRATION = {
          "github-actions" => 30_000,
        }

        # view modification and changes to regex at: https://rubular.com/r/rqUMu0hQkoChdU
        ENTERPRISE_SCIM_ENDPOINT_REGEX = /\/scim\/v2\/enterprises\/([\w-]+)\/[Users|Groups]+/
        ENTERPRISE_SCIM_LIMIT_MULTIPLIER = 100

        RATE_LIMIT_ENDPOINT_REGEX = /\/rate_limit/
        RATE_LIMIT_ENDPOINT_MULTIPLIER = 6

        CUSTOM_COSTS = {
          # /app/installations/:installation_id/access_tokens
          # This endpoint is heavily utilized by GitHub Apps to generate tokens
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

        sig { params(name: String, max: Integer).void }
        def initialize(name = "internal-authentication-fingerprint-by-path-noop", max:)
          @max = max
          super(name, limit: max)
        end

        sig { params(request: Rack::Request).returns(T::Boolean) }
        def ignored?(request)
          return true unless GitHub::Routers::Api.internal_api_host?(request.host)
          return true unless FeatureFlag.vexi.enabled?(:internal_auth_fingerprint_by_path_noop, default: false)
          false
        end

        def start(request)
          set_custom_limit(request)
          super(request)
        end

        sig { params(request: Rack::Request).void }
        def record_start(request)
          # If the path is for GraphQL or Twirp we want to not cost the request.
          graphql_path = graphql_path(request)
          twirp_path = self.class.twirp_path(request)

          if graphql_path.present? || twirp_path.present?
            return OK
          end

          current_total = increment_counter(request)

          if auth_type(request, omit_ip: true) == :hmac
            client = self.class.twirp_client_name_per_request(request)
            post_to_datadog(client, current_total, @limit, kind: "points_per_path", evaluation: true)
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

            if business && FeatureFlag.vexi.enabled?(:scim_rate_limiting_multiplier, business, default: false)
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

        sig { params(request: Rack::Request).void }
        def set_custom_limit(request)
          @limit = if FeatureFlag.vexi.enabled?(:internal_auth_fingerprint_path_custom_limit, default: false) && integration_actor?(request, omit_ip: true)
            CUSTOM_LIMIT_BY_INTEGRATION.fetch(integration_slug(request, omit_ip: true), @max)
          else
            @max
          end
        end

        sig { params(request: Rack::Request).returns(String) }
        def key(request)
          if !request.env.key?(INTERNAL_AUTH_FING_PATH_NOOP_KEY)
            auth_type = auth_type(request, omit_ip: true)
            authentication_fingerprint = auth_type == :hmac ? self.class.twirp_client_name_per_request(request) : fingerprint(request, omit_ip: true)

            hashed_path = Digest::SHA256.hexdigest(request.path_info)
            # store this so we don't need to keep calculating this value for this request
            request.env[INTERNAL_AUTH_FING_PATH_NOOP_KEY] = "#{authentication_fingerprint}:#{hashed_path}"
          end
          request.env[INTERNAL_AUTH_FING_PATH_NOOP_KEY]
        end

        # Mutating methods often incur more CPU time, so let's charge more for
        # those.
        sig { params(request: Rack::Request).returns(T.nilable(Integer)) }
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

        sig { params(path: String).returns(T.nilable(T::Array[Integer])) }
        def custom_cost_for(path)
          CUSTOM_COSTS.detect { |path_regex, _| path =~ path_regex }
        end
      end
    end
  end
end
