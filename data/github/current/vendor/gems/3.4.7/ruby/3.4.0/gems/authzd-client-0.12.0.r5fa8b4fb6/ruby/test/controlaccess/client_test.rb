# frozen_string_literal: true

require_relative "../test_helper"

module Authzd
  module ControlAccess
    class ClientTest < Minitest::Test

      UNROUTABLE_ADDRESS = "http://10.255.255.255"

      def test_twirp_supports_addr_as_string
        client = Authzd::ControlAccess::Client.new(UNROUTABLE_ADDRESS)
        refute_nil client.conn
      end

      def test_twirp_supports_addr_as_faraday_connection
        conn = Faraday.new(url: UNROUTABLE_ADDRESS)
        client = Authzd::ControlAccess::Client.new(conn)
        assert_equal conn, client.conn
      end

      def test_raises_on_invalid_addr
        assert_raises(ArgumentError) do
          Authzd::ControlAccess::Client.new(1)
        end
      end

      def test_returns_for_twirp_error_bad_route
        client = Authzd::ControlAccess::Client.new(UNROUTABLE_ADDRESS)
        req = make_controlaccess_request
        client.twirp_stub
            .expects(:check)
            .with(req, { headers: {} })
            .returns(Twirp::ClientResp.new(error: Twirp::Error.bad_route("twirp error")))
        resp = client.check(req)
        assert_equal "twirp error", resp.error.msg
      end

      def test_removes_internal_metadata
        client = Authzd::ControlAccess::Client.new(UNROUTABLE_ADDRESS)
        metadata = {}
        req = make_controlaccess_request
        client.twirp_stub
            .expects(:check)
            .with(req, { headers: {} })
            .returns(Twirp::ClientResp.new)
        client.check(req, metadata)
        assert_empty metadata
      end
    end
  end
end
