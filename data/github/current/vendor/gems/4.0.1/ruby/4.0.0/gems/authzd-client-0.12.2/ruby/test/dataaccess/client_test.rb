# frozen_string_literal: true

require_relative "../test_helper"

module Authzd
  module DataAccess
    class ClientTest < Minitest::Test

      UNROUTABLE_ADDRESS = "http://10.255.255.255"

      def test_twirp_supports_addr_as_string
        client = Authzd::DataAccess::Client.new(UNROUTABLE_ADDRESS)
        refute_nil client.conn
      end

      def test_twirp_supports_addr_as_faraday_connection
        conn = Faraday.new(url: UNROUTABLE_ADDRESS)
        client = Authzd::DataAccess::Client.new(conn)
        assert_equal conn, client.conn
      end

      def test_raises_on_invalid_addr
        assert_raises(ArgumentError) do
          Authzd::DataAccess::Client.new(1)
        end
      end

      def test_find_organization_ids_for_user_by_id
        client = Authzd::DataAccess::Client.new(UNROUTABLE_ADDRESS)
        req = Authzd::DataAccess::FindOrganizationIDsForUserByIDRequest.new(user_id: 123)
        client.twirp_stub
            .expects(:find_organization_ids_for_user_by_id)
            .with(req, { headers: {} })
            .returns(Twirp::ClientResp.new(data: Authzd::DataAccess::FindOrganizationIDsForUserByIDResponse.new))
        resp = client.find_organization_ids_for_user_by_id(req)
        refute_nil resp
      end

      def test_removes_internal_metadata
        client = Authzd::DataAccess::Client.new(UNROUTABLE_ADDRESS)
        metadata = {}
        req = Authzd::DataAccess::FindOrganizationIDsForUserByIDRequest.new(user_id: 123)
        client.twirp_stub
            .expects(:find_organization_ids_for_user_by_id)
            .with(req, { headers: {} })
            .returns(Twirp::ClientResp.new)
        client.find_organization_ids_for_user_by_id(req, metadata)
        assert_empty metadata
      end
    end
  end
end
