# frozen_string_literal: true

# Define the Authzd namespace for generated Ruby
module Authzd; end

require_relative "../proto/capevaluator_pb"
require_relative "../proto/capevaluator_twirp"
require_relative "../decoratable"
require_relative "../middleware/base"
require_relative "../middleware/hmac_signature"

module Authzd
  module CapEvaluator
    # Creates a Twirp Client for authzd Cap Evaulator service
    class Client
      include Authzd::Decoratable

      attr_reader :twirp_stub, :conn

      # Initializes a new Client
      # - conn: the Faraday::Connection or the server address.
      #         If passed as String, the Faraday::Connection will be created with default configuration
      # - block: (optional) a block receiving this same instance that is used to initialize
      #   the middleware stack for this class services
      #
      def initialize(conn)
        @conn = conn
        @twirp_stub = ::Authzd::CapEvaluator::CapEvaluatorClient.new(conn)
        yield self if block_given?
      end

      # Forwards the cap policy evaluation for a single resource request to the server.
      #
      # Params:
      # - request: an Authzd::CapEvaluator::SingleResourceRequest describing the
      #            types of subjects that we want to enumerate for the actor.
      #
      # Returns Authzd::CapEvaluator::SingleResourceResponse
      def evaluate_policies_for_single_resource(request, metadata = {})
        @twirp_stub.evaluate_policies_for_single_resource(request, { headers: metadata })
      end

      # Forwards the cap policy evaluation for a filtering request to the server.
      #
      # Params:
      # - request: an Authzd::CapEvaluator::FilterRequest describing the
      #            targets to filter for a given actor.
      #
      # Returns Authzd::CapEvaluator::FilterResponse
      def evaluate_policies_for_filtering(request, metadata = {})
        @twirp_stub.evaluate_policies_for_filtering(request, { headers: metadata })
      end
    end
  end
end
