# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../authzd_server_helper"

module Authzd
  module ControlAccess
    class ClientIntegrationTest < Minitest::Test
      include Minitest::Hooks

      def before_all
        start_server(SERVER_ADDR, out: $stdout)
      end

      def after_all
        stop_server
      end

      def test_works
        client = create_controlaccess_client
        request = make_controlaccess_request
        resp = client.check(request)
        assert_equal :DENY, resp.data&.result&.outcome, resp.error
      end

      def test_invalid_hmac
        client = create_controlaccess_client(hmac_secret: "foobar")

        request = make_controlaccess_request
        resp = client.check(request)
        assert resp.error
        assert_match /HMAC .* is invalid/, resp.error.msg
      end

    end
  end
end
