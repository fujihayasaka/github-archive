# frozen_string_literal: true

require_relative "../test_helper"

module Authzd
  module Middleware
    class ControlAccessRetryTest < Minitest::Test
      ControlAccessStub      = Class.new
      RetryableError         = Class.new(StandardError)
      AnotherRetryableError  = Class.new(StandardError)
      NonRetryableError      = Class.new(StandardError)
      Instrumenter           = Authzd::Middleware::Instrumenters::Noop

      def setup
        @ca_request = Authzd::ControlAccess::Request.new
        @control_access = ControlAccessStub.new

        @control_access.stubs(:rpc_name).returns("check")

        options = {
          max_attempts: 3,
          retryable_errors: [RetryableError, AnotherRetryableError]
        }
        @middleware = Middleware::ControlAccessRetry.new(**options).tap do |middleware|
          middleware.request = @control_access
        end
      end

      def test_retry_max_attempts_and_bubble_up_error
        retryable_error = RetryableError.new
        @control_access.expects(:perform).times(3).with(@ca_request, {}).raises(retryable_error)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 1, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 2, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 3, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.failed", { middleware: "control_access_retry", operation: "failed", attempt: 3, authz_request: @ca_request, error: retryable_error, rpc: "check", indeterminate: true }).in_sequence(instrumentation_sequence)

        assert_raises(RetryableError) do
          @middleware.perform(@ca_request)
        end
      end

      def assert_twirp_response(res)
        res = res.data
        assert res, "invalid response"
        assert res.result, "invalid response, no results"
        assert res.result.outcome == :ALLOW , "Conditional Access not ALLOW"
      end

      def test_retry_and_on_success_return_result
        fail_and_succeed = sequence("fail and succeed")

        response = Authzd::ControlAccess::Response.new(
          result: Authzd::ControlAccess::Result.new(
            outcome: Authzd::Proto::Result::ALLOW,
          )
        )

        twirp_response = Twirp::ClientResp.new(data: response)

        @control_access.expects(:perform).with(@ca_request, {}).in_sequence(fail_and_succeed).raises(AnotherRetryableError)
        @control_access.expects(:perform).with(@ca_request, {}).in_sequence(fail_and_succeed).returns(twirp_response)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 1, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 2, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.succeeded", { middleware: "control_access_retry", operation: "succeeded", attempt: 2, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)

        res = @middleware.perform(@ca_request)
        assert_twirp_response res
      end

      def test_doesnt_retry_if_error_isnt_retryable
        error = NonRetryableError.new
        @control_access.expects(:perform).with(@ca_request, {}).once.raises(error)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 1, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.failed", { middleware: "control_access_retry", operation: "failed", attempt: 1, authz_request: @ca_request, error:, rpc: "check" }).in_sequence(instrumentation_sequence)

        assert_raises(NonRetryableError) do
          @middleware.perform(@ca_request)
        end
      end

      def test_wait_between_retries_if_option_provided
        fail_and_succeed = sequence("fail and succeed")
        retryable_error = RetryableError.new

        response = Authzd::ControlAccess::Response.new(
          result: Authzd::ControlAccess::Result.new(
            outcome: Authzd::Proto::Result::ALLOW,
          )
        )
        twirp_response = Twirp::ClientResp.new(data: response)

        @control_access.expects(:perform).with(@ca_request, {}).in_sequence(fail_and_succeed).raises(retryable_error)
        @control_access.expects(:perform).with(@ca_request, {}).in_sequence(fail_and_succeed).returns(twirp_response)

        @middleware = Middleware::ControlAccessRetry.new(wait_seconds: 0.1).tap do |middleware|
          middleware.request = @control_access
        end
        @middleware.stubs(:sleep).once.with(0.1)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 1, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.waited", { middleware: "control_access_retry", operation: "waited", attempt: 1, authz_request: @ca_request, wait_seconds: 0.1, error: retryable_error, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 2, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.succeeded", { middleware: "control_access_retry", operation: "succeeded", attempt: 2, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)

        res = @middleware.perform(@ca_request)
        assert_twirp_response res
      end

      def test_retries_for_indeterminate_error
        indeterminate_and_succeed = sequence("indeterminate and succeed")

        indeterminate_response = Authzd::ControlAccess::Response.new(
          result: Authzd::ControlAccess::Result.new(
            outcome: Authzd::Proto::Result::INDETERMINATE,
          )
        )
        twirp_indeterminate_response = Twirp::ClientResp.new(data: indeterminate_response)

        response = Authzd::ControlAccess::Response.new(
          result: Authzd::ControlAccess::Result.new(
            outcome: Authzd::Proto::Result::ALLOW,
          )
        )
        twirp_response = Twirp::ClientResp.new(data: response)

        @control_access.expects(:perform).with(@ca_request, {}).in_sequence(indeterminate_and_succeed).returns(twirp_indeterminate_response)
        @control_access.expects(:perform).with(@ca_request, {}).in_sequence(indeterminate_and_succeed).returns(twirp_indeterminate_response)
        @control_access.expects(:perform).with(@ca_request, {}).in_sequence(indeterminate_and_succeed).returns(twirp_response)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 1, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 2, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 3, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.succeeded", { middleware: "control_access_retry", operation: "succeeded", attempt: 3, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)

        res = @middleware.perform(@ca_request)
        assert_twirp_response res
      end

      def test_retries_for_unknown_error_nil_data
        unknown_and_succeed = sequence("unknown and succeed")

        twirp_unknown_response = Twirp::ClientResp.new(data: nil, error: Twirp::Error.unknown("boom"))

        response = Authzd::ControlAccess::Response.new(
          result: Authzd::ControlAccess::Result.new(
            outcome: Authzd::Proto::Result::ALLOW,
          )
        )
        twirp_response = Twirp::ClientResp.new(data: response)

        @control_access.expects(:perform).with(@ca_request, {}).in_sequence(unknown_and_succeed).returns(twirp_unknown_response)
        @control_access.expects(:perform).with(@ca_request, {}).in_sequence(unknown_and_succeed).returns(twirp_unknown_response)
        @control_access.expects(:perform).with(@ca_request, {}).in_sequence(unknown_and_succeed).returns(twirp_response)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 1, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 2, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 3, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.succeeded", { middleware: "control_access_retry", operation: "succeeded", attempt: 3, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)

        res = @middleware.perform(@ca_request)
        assert_twirp_response res
      end

      def test_max_retries_w_indeterminate_raises
        indeterminate_response = Authzd::ControlAccess::Response.new(
          result: Authzd::ControlAccess::Result.new(
            outcome: Authzd::Proto::Result::INDETERMINATE,
          )
        )
        twirp_indeterminate_response = Twirp::ClientResp.new(data: indeterminate_response)

        @control_access.expects(:perform).with(@ca_request, {}).times(3).returns(twirp_indeterminate_response)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 1, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 2, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 3, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).in_sequence(instrumentation_sequence)

        assert_raises(Authzd::IndeterminateError) do
          @middleware.perform(@ca_request)
        end
      end

      def test_max_retries_w_wait
        @middleware = Middleware::ControlAccessRetry.new(wait_seconds: 0.1, max_attempts: 3).tap do |middleware|
          middleware.request = @control_access
        end
        @middleware.stubs(:sleep).times(2).with(0.1)

        indeterminate_response = Authzd::ControlAccess::Response.new(
          result: Authzd::ControlAccess::Result.new(
            outcome: Authzd::Proto::Result::INDETERMINATE,
          )
        )
        twirp_indeterminate_response = Twirp::ClientResp.new(data: indeterminate_response)

        @control_access.expects(:perform).with(@ca_request, {}).times(3).returns(twirp_indeterminate_response)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 1, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 2, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.control_access_retry.tried", { middleware: "control_access_retry", operation: "tried", attempt: 3, authz_request: @ca_request, rpc: "check" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).in_sequence(instrumentation_sequence)

        assert_raises(Authzd::IndeterminateError) do
          @middleware.perform(@ca_request)
        end
      end

      def test_retry_with_factor
        retryable_error = RetryableError.new

        control_access_sequence = sequence("controlaccess")
        @control_access.expects(:perform).with(@ca_request, { "__timeout_factor__" => 1 }).raises(retryable_error).in_sequence(control_access_sequence)
        @control_access.expects(:perform).with(@ca_request, { "__timeout_factor__" => 2 }).raises(retryable_error).in_sequence(control_access_sequence)
        @control_access.expects(:perform).with(@ca_request, { "__timeout_factor__" => 3 }).raises(retryable_error).in_sequence(control_access_sequence)

        options = {
          max_attempts: 3,
          retryable_errors: [RetryableError, AnotherRetryableError],
          retry_factor: true
        }
        @middleware = Middleware::ControlAccessRetry.new(**options).tap do |middleware|
          middleware.request = @control_access
        end

        assert_raises(RetryableError) do
          @middleware.perform(@ca_request)
        end
      end
    end
  end
end
