# frozen_string_literal: true

require_relative "../test_helper"

module Authzd
  module Middleware
    class CircuitBreakerTest < Minitest::Test

      AuthorizerStub = Class.new
      Instrumenter   = Instrumenters::Noop

      def setup
        ::Resilient::CircuitBreaker::Registry.default.reset

        @authzd_request = Authzd::Proto::Request.new
        @batch_request = Authzd::Proto::BatchRequest.new
        @authorizer = AuthorizerStub.new

        options = {
          request_volume_threshold: 1,  # second bad request in the window, opens the circuit
          sleep_window_seconds: 5       # wait 5 seconds to close the circuit again
        }
        @middleware = Middleware::CircuitBreaker.new(**options).tap do |middleware|
          middleware.request = @authorizer
        end

        @circuit = @middleware.send(:circuit)
      end

      def test_circuit_closed_success_keeps_it_closed
        expected_metadata = {}
        Instrumenter.expects(:instrument).with("authzd.client.circuit_breaker.success", { middleware: "circuit_breaker", operation: "success", authz_request: @authzd_request, rpc: "authorize" })
        @authorizer.expects(:perform).once.with(@authzd_request, expected_metadata).returns(Authzd::Proto::Decision.allow)
        assert_predicate @middleware.perform(@authzd_request), :allow?
        refute @circuit.open
      end

      def test_circuit_close_second_try_opened
        expected_metadata = {}
        error = StandardError.new
        @authorizer.expects(:perform).once.with(@authzd_request, expected_metadata).raises(error)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.circuit_breaker.failure",
                                               { middleware: "circuit_breaker",
                                               operation: "failure",
                                               error: error,
                                               authz_request: @authzd_request,
                                               rpc: "authorize" }
        ).in_sequence(instrumentation_sequence)

        Instrumenter.expects(:instrument).with("authzd.client.circuit_breaker.open",
                                               { middleware: "circuit_breaker",
                                               operation: "open",
                                               authz_request: @authzd_request,
                                               rpc: "authorize" }
        ).in_sequence(instrumentation_sequence)

        assert_raises(StandardError)  do
          @middleware.perform(@authzd_request)
        end

        assert_raises(Middleware::CircuitBreaker::CircuitOpenError)  do
          @middleware.perform(@authzd_request)
        end
        assert @circuit.open
      end

      def test_circuit_opens_with_batch_authorize
        expected_metadata = {}
        @batch_request = Authzd::Proto::BatchRequest.new
        error = StandardError.new
        @authorizer.expects(:perform).once.with(@batch_request, expected_metadata).raises(error)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.circuit_breaker.failure",
                                               { middleware: "circuit_breaker",
                                               operation: "failure",
                                               error: error,
                                               authz_request: @batch_request,
                                               rpc: "batch_authorize" }
        ).in_sequence(instrumentation_sequence)

        Instrumenter.expects(:instrument).with("authzd.client.circuit_breaker.open",
                                               { middleware: "circuit_breaker",
                                               operation: "open",
                                               authz_request: @batch_request,
                                               rpc: "batch_authorize" }
        ).in_sequence(instrumentation_sequence)

        assert_raises(StandardError)  do
          @middleware.perform(@batch_request)
        end

        assert_raises(Middleware::CircuitBreaker::CircuitOpenError)  do
          @middleware.perform(@batch_request)
        end
        assert @circuit.open
      end

      def test_batch_auth_success_keeps_circuit_closed
        expected_metadata = {}
        Instrumenter.expects(:instrument).with("authzd.client.circuit_breaker.success",
                                               { middleware: "circuit_breaker",
                                               operation: "success",
                                               authz_request: @batch_request,
                                               rpc: "batch_authorize" })
        @authorizer.expects(:perform).once.with(@batch_request, expected_metadata).returns(Authzd::Proto::BatchDecision.new)
        assert_equal Authzd::Proto::BatchDecision, @middleware.perform(@batch_request).class
        refute @circuit.open
      end

      def test_client_error_does_not_open_circuit
        expected_metadata = {}
        twirp_error = Twirp::Error.invalid_argument("bad request", argument: "targets")
        client_error = Authzd::ClientError.new(twirp_error)

        @authorizer.expects(:perform).twice.with(@authzd_request, expected_metadata).raises(client_error)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.circuit_breaker.client_error",
                                                { middleware: "circuit_breaker",
                                                operation: "client_error",
                                                error: client_error,
                                                authz_request: @authzd_request,
                                                rpc: "authorize" }
        ).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.circuit_breaker.client_error",
                                                { middleware: "circuit_breaker",
                                                operation: "client_error",
                                                error: client_error,
                                                authz_request: @authzd_request,
                                                rpc: "authorize" }
        ).in_sequence(instrumentation_sequence)

        # Two client errors should NOT open the circuit (request_volume_threshold is 1)
        assert_raises(Authzd::ClientError) { @middleware.perform(@authzd_request) }
        assert_raises(Authzd::ClientError) { @middleware.perform(@authzd_request) }
        refute @circuit.open
      end

      def test_client_error_counts_as_success_helps_close_circuit
        expected_metadata = {}
        server_error = StandardError.new("server error")
        twirp_error = Twirp::Error.invalid_argument("bad request")
        client_error = Authzd::ClientError.new(twirp_error)

        call_sequence = sequence("calls")
        # First call: server error records failure in metrics
        @authorizer.expects(:perform).with(@authzd_request, expected_metadata).in_sequence(call_sequence).raises(server_error)

        Instrumenter.stubs(:instrument)

        assert_raises(StandardError) { @middleware.perform(@authzd_request) }

        # Second call: circuit opens (lazily on allow_request? check)
        assert_raises(Authzd::Middleware::CircuitBreaker::CircuitOpenError) { @middleware.perform(@authzd_request) }
        assert @circuit.open

        # Advance time past sleep window so circuit is half-open
        @circuit.instance_variable_set(:@opened_or_last_checked_at_epoch, Time.now.to_i - 10)

        # Third call: client error counts as success, should close circuit
        @authorizer.expects(:perform).with(@authzd_request, expected_metadata).in_sequence(call_sequence).raises(client_error)

        assert_raises(Authzd::ClientError) { @middleware.perform(@authzd_request) }
        refute @circuit.open
      end
    end
  end
end
