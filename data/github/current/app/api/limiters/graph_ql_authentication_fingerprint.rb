# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class GraphQLAuthenticationFingerprint < GitHub::Limiters::MemcachedWindow
      include Api::Limiters::ObservabilityHelpers
      include Api::Limiters::Helpers
      include Api::Limiters::GraphqlHelper

      REQUEST_TYPE_MUTATION = "mutation".freeze
      REQUEST_TYPE_QUERY = "query".freeze

      sig { params(max: Integer).void }
      def initialize(max:)
        super(name, limit: max)
        @max = max
      end

      sig { override.params(request: Rack::Request).returns(T::Boolean) }
      def ignored?(request)
        return true unless graphql_request?(request)
        false
      end

      sig { override.params(request: Rack::Request).returns(State) }
      def start(request)
        return OK unless graphql_request?(request)
        super(request)
      end

      sig { override.params(request: Rack::Request).returns(T.untyped) }
      def record_finish(request)
        return OK unless graphql_request?(request)
        increment_counter(request)
      end

      # If the request was canceled we don't want to cost the request.
      sig { override.params(request: Rack::Request).returns(T.untyped) }
      def cancel(request)
        OK
      end

      sig { override.returns(String) }
      def name
        "graphql-authentication-fingerprint"
      end

      # Protected: This part of the key is used in conjuction with a key prefix
      # which is configured in the initializer.
      sig { override.params(request: Rack::Request).returns(String) }
      def key(request)
        "#{request_type}:#{fingerprint(request)}"
      end

      def request_type
        if Platform::GlobalScope.mutation?
          REQUEST_TYPE_MUTATION
        else
          REQUEST_TYPE_QUERY
        end
      end

      protected

      # Protected: If the GraphQL query was a mutation we charge the request 5
      # points against their allotted quota.
      sig { override.params(request: Rack::Request).returns(Integer) }
      def cost(request)
        if Platform::GlobalScope.mutation?
          5
        else
          1
        end
      end

      # The intention is that this gets overridden by the internal limiter.
      sig { returns(String) }
      def log_data_prefix
        "graphql_authentication_fingerprint"
      end
    end
  end
end
