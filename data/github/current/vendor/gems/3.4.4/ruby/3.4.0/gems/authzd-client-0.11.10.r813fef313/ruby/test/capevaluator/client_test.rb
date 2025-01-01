# frozen_string_literal: true

require_relative "../test_helper"

module Authzd
  module CapEvaluator
    class ClientTest < Minitest::Test

      UNROUTABLE_ADDRESS = "http://10.255.255.255"

      def test_twirp_supports_addr_as_string
        client = Authzd::CapEvaluator::Client.new(UNROUTABLE_ADDRESS)
        refute_nil client.conn
      end

      def test_twirp_supports_addr_as_faraday_connection
        conn = Faraday.new(url: UNROUTABLE_ADDRESS)
        client = Authzd::CapEvaluator::Client.new(conn)
        assert_equal conn, client.conn
      end

      def test_raises_on_invalid_addr
        assert_raises(ArgumentError) do
          Authzd::CapEvaluator::Client.new(1)
        end
      end

      def test_returns_for_twirp_error_bad_route
        client = Authzd::CapEvaluator::Client.new(UNROUTABLE_ADDRESS)
        req = evaluate_policies_for_single_resource_request
        client.twirp_stub
            .expects(:evaluate_policies_for_single_resource)
            .with(req, {:headers => {}})
            .returns(Twirp::ClientResp.new(error: Twirp::Error.bad_route("twirp error")))
        resp = client.evaluate_policies_for_single_resource(req)
        assert_equal "twirp error", resp.error.msg
      end

      def test_removes_internal_metadata
        client = Authzd::CapEvaluator::Client.new(UNROUTABLE_ADDRESS)
        metadata = {}
        req = evaluate_policies_for_single_resource_request
        client.twirp_stub
            .expects(:evaluate_policies_for_single_resource)
            .with(req, {:headers => {}})
            .returns(Twirp::ClientResp.new())
        client.evaluate_policies_for_single_resource(req, metadata)
        assert_empty metadata
      end
    end
  end
end
