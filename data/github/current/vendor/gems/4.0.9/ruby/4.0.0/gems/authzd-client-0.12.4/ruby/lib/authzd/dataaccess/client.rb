# frozen_string_literal: true

module Authzd; end

require_relative "../proto/membership_pb"
require_relative "../proto/membership_twirp"
require_relative "../decoratable"
require_relative "../middleware/base"
require_relative "../middleware/hmac_signature"

module Authzd
  module DataAccess
    class Client
      include Authzd::Decoratable

      attr_reader :twirp_stub, :conn

      def initialize(conn)
        @conn = conn
        @twirp_stub = ::Authzd::DataAccess::MembershipClient.new(conn)
        yield self if block_given?
      end

      def find_organization_ids_for_user_by_id(request, metadata = {})
        @twirp_stub.find_organization_ids_for_user_by_id(request, { headers: metadata })
      end
    end
  end
end
