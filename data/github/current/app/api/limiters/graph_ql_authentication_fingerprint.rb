# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    class GraphQLAuthenticationFingerprint < GitHub::Limiters::MemcachedWindow
      REQUEST_TYPE_MUTATION = "mutation".freeze
      REQUEST_TYPE_QUERY = "query".freeze

      # Public: Extract the GraphQL path from the incoming request.
      #
      # request - Rack::Request instance.
      #
      # Returns String if GraphQL path is present, false otherwise.
      def self.graphql_path(request)
        if match = ::Api::GraphQL::PATH_REGEX.match(request.path_info)
          match[0].downcase
        end
      end

      # Public: Determine if the incoming request is for a GraphQL endpoint. Our
      # specific GraphQL implementation has a preference for POST requests for
      # query execution.
      #
      # request - Rack::Request instance.
      #
      # Returns true if GraphQL request, false otherwise.
      def self.graphql_request?(request)
        return false if request.request_method != "POST"
        !graphql_path(request).nil?
      end

      def initialize(max:)
        super("graphql-authentication-fingerprint", limit: max)
      end

      def start(request)
        return OK unless self.class.graphql_request?(request)
        super(request)
      end

      def record_finish(request)
        return OK unless self.class.graphql_request?(request)
        increment_counter(request)
      end

      # If the request was canceled we don't want to cost the request.
      def cancel(request)
        OK
      end

      protected

      # Protected: If the GraphQL query was a mutation we charge the request 5
      # points against their allotted quota.
      def cost(request)
        if Platform::GlobalScope.mutation?
          5
        else
          1
        end
      end

      # Protected: This part of the key is used in conjuction with a key prefix
      # which is configured in the initializer.
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

      def fingerprint(request)
        Api::Middleware::RequestAuthenticationFingerprint.get(request.env).to_s
      end
    end
  end
end
