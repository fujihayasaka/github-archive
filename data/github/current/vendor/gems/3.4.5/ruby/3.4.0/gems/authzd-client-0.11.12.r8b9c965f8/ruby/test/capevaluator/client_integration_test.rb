# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../authzd_server_helper"

module Authzd
  module CapEvaluator
    class ClientIntegrationTest < Minitest::Test
      include Minitest::Hooks

      def before_all
        start_server(SERVER_ADDR, out: $stdout)
      end

      def after_all
        stop_server
      end

      def test_invalid_hmac_single_resource
        client = create_capevaluator_client(hmac_secret: "foobar")

        request = Authzd::CapEvaluator::SingleResourceRequest.new
        resp = client.evaluate_policies_for_single_resource(request)
        assert resp.error
        assert_match(/HMAC .* is invalid/, resp.error.msg)
      end

      def test_invalid_hmac_filter
        client = create_capevaluator_client(hmac_secret: "foobar")

        request = Authzd::CapEvaluator::FilterRequest.new
        resp = client.evaluate_policies_for_filtering(request)
        assert resp.error
        assert_match(/HMAC .* is invalid/, resp.error.msg)
      end

      def test_twirp_methods_single_resource
        client = create_capevaluator_client

        request = evaluate_policies_for_single_resource_request
        resp = client.evaluate_policies_for_single_resource(request)
        # Default request uses a resource type that doesn't have a resolver
        assert_match(/target resolver not found/, resp.error.msg)

        request = evaluate_policies_for_single_resource_request(resource_id: 999, resource_type: "User", policy_group: "non_real_group_name")
        resp = client.evaluate_policies_for_single_resource(request)
        assert_match(/non_real_group_name not found in registry/, resp.error.msg)
      end

      def test_twirp_methods_filter
        client = create_capevaluator_client

        request = evaluate_policies_for_filtering_request(targets: [{ id: 123, type: "invalidTargetType" }], policy_group: nil, policy: "legacy_personal_access_tokens")
        resp = client.evaluate_policies_for_filtering(request)
        assert_match(/invalid target for conditional access/, resp.error.msg)

        request = evaluate_policies_for_filtering_request(targets: [{ id: 999, type: "User" }], policy_group: "non_real_group_name")
        resp = client.evaluate_policies_for_filtering(request)
        assert_match(/non_real_group_name not found in registry/, resp.error.msg)
      end

      def test_all_middleware_smoke_test
        ::Resilient::CircuitBreaker::Registry.default.reset
        conn = Faraday.new(url: TWIRP_ADDR) do |f|
          f.adapter(:net_http)
          f.options[:timeout] = 5
          f.options[:open_timeout] = 5
        end
        client = Authzd::CapEvaluator::Client.new(conn) do |client|
          client.use :evaluate_policies_for_single_resource, with: [
            Authzd::Middleware::Timing.new(instrumenter: Debug),
            Authzd::Middleware::CircuitBreaker.new(instrumenter: Debug),
            Authzd::Middleware::HmacSignature.new(instrumenter: Debug, key: "authzdhmac")
          ]
        end

        resp = client.evaluate_policies_for_single_resource(evaluate_policies_for_single_resource_request)
        assert_match(/target resolver not found/, resp.error.msg)
      end
    end
  end
end
