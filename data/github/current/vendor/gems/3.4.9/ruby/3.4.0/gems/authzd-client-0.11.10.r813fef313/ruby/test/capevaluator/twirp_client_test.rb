# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../authzd_server_helper"

module Authzd
  module CapEvaluator
    class TwirpClientTest < Minitest::Test
      PORT = "18082"
      SERVER_ADDR = "127.0.0.1:#{PORT}"
      INVALID_TWIRP_URL = "http://#{SERVER_ADDR}"
      TWIRP_URL = "http://#{SERVER_ADDR}/twirp"

      def test_bad_route_error
        start_server(SERVER_ADDR, out: STDOUT)
        client = Authzd::CapEvaluator::Client.new(INVALID_TWIRP_URL)
        resp = client.evaluate_policies_for_single_resource(evaluate_policies_for_single_resource_request)

        assert_match /bad_route/, resp.error.msg
      ensure
        stop_server
      end

      def test_timeout_error
        conn = Faraday.new(url: "http://10.255.255.255") do |f|
          f.adapter(:net_http)
          f.options[:timeout] = 0.01
          f.options[:open_timeout] = 0.01
        end
        client = Authzd::CapEvaluator::Client.new(conn)
        assert_raises Faraday::ConnectionFailed do
          client.evaluate_policies_for_single_resource(evaluate_policies_for_single_resource_request)
        end
      ensure
        stop_server
      end
    end
  end
end
