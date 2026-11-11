# frozen_string_literal: true

# Define the Authzd namespace for generated Ruby
module Authzd; end

require_relative "../proto/controlaccess_pb"
require_relative "../proto/controlaccess_twirp"
require_relative "../decoratable"
require_relative "../middleware/base"
require_relative "../middleware/hmac_signature"

module Authzd
  module ControlAccess
    # Creates a Twirp Client for authzd control_access service
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
        @twirp_stub = ::Authzd::ControlAccess::ControlAccessClient.new(conn)
        yield self if block_given?
      end

      # Performs API authorization
      #
      # Params:
      # - request: an Authzd::ControlAccess::Request
      #
      # Retuns Authzd::ControlAccess::Response
      def check(request, metadata = {})
        @twirp_stub.check(request, { headers: metadata })
      end
    end
  end
end
