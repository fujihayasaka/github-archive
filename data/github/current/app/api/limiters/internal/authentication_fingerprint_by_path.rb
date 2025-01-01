# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    module Internal
      class AuthenticationFingerprintByPath < Api::Limiters::AuthenticationFingerprintByPath
        include Api::Limiters::ObservabilityHelpers
        include Api::Limiters::Helpers

        INTERNAL_LIMITER_AUTH_PATH_FINGERPRINT_KEY = "github.api.internal_limiter_auth_path_limiter_fingerprint"
        INTERNAL_AUTH_FINGERPRINT_PATH_FF_KEY = "internal-authentication-fingerprint-by-path"

        LOG_DATA_PREFIX = "internal.auth_fingerprint_path"

        include GitHub::Middleware::Constants

        sig { params(max: Integer).void }
        def initialize(max:)
          @max = max
          super("internal-authentication-fingerprint-by-path", max: max)
        end

        sig { params(request: Rack::Request).returns(T::Boolean) }
        def ignored?(request)
          return true unless GitHub.flipper[INTERNAL_AUTH_FINGERPRINT_PATH_FF_KEY].enabled?
          return true unless GitHub::Routers::Api.internal_api_host?(request.host)
          return true if super(request)

          false
        end

        sig { params(request: Rack::Request).void }
        def record_start(request)
          # If the path is for GraphQL or Twirp we want to not cost the request.
          graphql_path = Api::Limiters::GraphQLAuthenticationFingerprint.graphql_path(request)
          twirp_path = Api::Limiters::TwirpAuthenticationFingerprintByPath.twirp_path(request)

          if graphql_path.present? || twirp_path.present?
            return OK
          end

          cur_limit = increment_counter(request)

          if (log_data = request.env[Rack::RequestLogger::APPLICATION_LOG_DATA])
            add_to_log_data(LOG_DATA_PREFIX, log_data, key(request), http_user_agent(request), cost(request), cur_limit, @max)
          end

          unless auth_type(request, omit_ip: true) == :other
            post_to_datadog(key(request), cur_limit, @max, kind: "auth_fingerprint_by_path", evaluation: true)
          end

        end

        protected

        sig { params(request: Rack::Request).returns(String) }
        def key(request)
          if !request.env.key?(INTERNAL_LIMITER_AUTH_PATH_FINGERPRINT_KEY)
            authentication_fingerprint = fingerprint(request, omit_ip: true)
            hashed_path = Digest::SHA256.hexdigest(request.path_info)
            # store this so we don't need to keep calculating this value for this request
            request.env[INTERNAL_LIMITER_AUTH_PATH_FINGERPRINT_KEY] = "#{authentication_fingerprint}:#{hashed_path}"
          end
          request.env[INTERNAL_LIMITER_AUTH_PATH_FINGERPRINT_KEY]
        end
      end
    end
  end
end
