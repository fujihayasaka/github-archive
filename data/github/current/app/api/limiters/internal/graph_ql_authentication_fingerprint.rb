# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    module Internal
      class GraphQLAuthenticationFingerprint < Api::Limiters::GraphQLAuthenticationFingerprint
        include Api::Limiters::GraphqlHelper

        def initialize(max:)
          super(max: max)
        end

        sig { override.params(request: Rack::Request).returns(T::Boolean) }
        def ignored?(request)
          return true unless graphql_request?(request)
          false
        end

        # Overrides the name of the limiter to avoid conflicts with the public GraphQLAuthenticationFingerprint limiter.
        sig { override.returns(String) }
        def name
          "internal-graphql-authentication-fingerprint"
        end

        protected

        # Overrides the method to omit the IP address from the fingerprint.
        sig { override.params(request: Rack::Request).returns(T.nilable(String)) }
        def fingerprint(request)
          super(request, omit_ip: true)
        end

        # Overrides the method to return the log data prefix for the internal limiter.
        sig { override.returns(String) }
        def log_data_prefix
          "internal.graphql_authentication_fingerprint"
        end
      end
    end
  end
end
