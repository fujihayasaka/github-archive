# frozen_string_literal: true

require_relative "../test_helper"

module Authzd
  module Middleware
    class CAPRetryTest < Minitest::Test
      CapEvaluatorStub       = Class.new
      RetryableError         = Class.new(StandardError)
      AnotherRetryableError  = Class.new(StandardError)
      NonRetryableError      = Class.new(StandardError)
      Instrumenter           = Authzd::Middleware::Instrumenters::Noop

      def setup
        @cap_request = Authzd::CapEvaluator::SingleResourceRequest.new
        @cap_evaluator = CapEvaluatorStub.new

        @cap_evaluator.stubs(:rpc_name).returns("evaluate_policies_for_single_resource")

        options = {
          max_attempts: 3,
          retryable_errors: [RetryableError, AnotherRetryableError]
        }
        @middleware = Middleware::CAPRetry.new(**options).tap do |middleware|
          middleware.request = @cap_evaluator
        end
      end

      def test_retry_max_attempts_and_bubble_up_error
        retryable_error = RetryableError.new
        @cap_evaluator.expects(:perform).times(3).with(@cap_request, {}).raises(retryable_error)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 1, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 2, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 3, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.failed", { middleware: "cap_retry", operation: "failed", attempt: 3, authz_request: @cap_request, error: retryable_error, rpc: "evaluate_policies_for_single_resource", unknown: true }).in_sequence(instrumentation_sequence)

        assert_raises(RetryableError) do
          @middleware.perform(@cap_request)
        end
      end

      def assert_twirp_response(res)
        cap_res = res.data
        assert cap_res, "invalid response"
        assert cap_res.results, "invalid response, no results"
        assert cap_res.results.all? { |d| d.outcome == :SATISFIED }, "CAP policy not satisifed"
      end

      def test_retry_and_on_success_return_result
        fail_and_succeed = sequence("fail and succeed")

        cap_response = Authzd::CapEvaluator::SingleResourceResponse.new(
          results: [
            Authzd::CapEvaluator::Result.new(
              policy: "test_policy",
              outcome: Authzd::CapEvaluator::Outcome::SATISFIED
            )
          ]
        )
        twirp_response = Twirp::ClientResp.new(data: cap_response)

        @cap_evaluator.expects(:perform).with(@cap_request, {}).in_sequence(fail_and_succeed).raises(AnotherRetryableError)
        @cap_evaluator.expects(:perform).with(@cap_request, {}).in_sequence(fail_and_succeed).returns(twirp_response)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 1, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 2, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.succeeded", { middleware: "cap_retry", operation: "succeeded", attempt: 2, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)

        res = @middleware.perform(@cap_request)
        assert_twirp_response res
      end

      def test_doesnt_retry_if_error_isnt_retryable
        error = NonRetryableError.new
        @cap_evaluator.expects(:perform).with(@cap_request, {}).once.raises(error)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 1, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.failed", { middleware: "cap_retry", operation: "failed", attempt: 1, authz_request: @cap_request, error:, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)

        assert_raises(NonRetryableError) do
          @middleware.perform(@cap_request)
        end
      end

      def test_wait_between_retries_if_option_provided
        fail_and_succeed = sequence("fail and succeed")
        retryable_error = RetryableError.new

        cap_response = Authzd::CapEvaluator::SingleResourceResponse.new(
          results: [
            Authzd::CapEvaluator::Result.new(
              policy: "test_policy",
              outcome: Authzd::CapEvaluator::Outcome::SATISFIED
            )
          ]
        )
        twirp_response = Twirp::ClientResp.new(data: cap_response)

        @cap_evaluator.expects(:perform).with(@cap_request, {}).in_sequence(fail_and_succeed).raises(retryable_error)
        @cap_evaluator.expects(:perform).with(@cap_request, {}).in_sequence(fail_and_succeed).returns(twirp_response)

        @middleware = Middleware::CAPRetry.new(wait_seconds: 0.1).tap do |middleware|
          middleware.request = @cap_evaluator
        end
        @middleware.stubs(:sleep).once.with(0.1)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 1, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.waited", { middleware: "cap_retry", operation: "waited", attempt: 1, authz_request: @cap_request, wait_seconds: 0.1, error: retryable_error, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 2, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.succeeded", { middleware: "cap_retry", operation: "succeeded", attempt: 2, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)

        res = @middleware.perform(@cap_request)
        assert_twirp_response res
      end

      def test_retries_for_unknown_error
        unknown_and_succeed = sequence("unknown and succeed")

        cap_unknown_response = Authzd::CapEvaluator::SingleResourceResponse.new(
          results: [
            Authzd::CapEvaluator::Result.new(
              policy: "test_policy",
              outcome: Authzd::CapEvaluator::Outcome::OUTCOME_UNKNOWN
            )
          ]
        )
        twirp_unknown_response = Twirp::ClientResp.new(data: cap_unknown_response)

        cap_response = Authzd::CapEvaluator::SingleResourceResponse.new(
          results: [
            Authzd::CapEvaluator::Result.new(
              policy: "test_policy",
              outcome: Authzd::CapEvaluator::Outcome::SATISFIED
            )
          ]
        )
        twirp_response = Twirp::ClientResp.new(data: cap_response)

        @cap_evaluator.expects(:perform).with(@cap_request, {}).in_sequence(unknown_and_succeed).returns(twirp_unknown_response)
        @cap_evaluator.expects(:perform).with(@cap_request, {}).in_sequence(unknown_and_succeed).returns(twirp_unknown_response)
        @cap_evaluator.expects(:perform).with(@cap_request, {}).in_sequence(unknown_and_succeed).returns(twirp_response)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 1, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 2, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 3, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.succeeded", { middleware: "cap_retry", operation: "succeeded", attempt: 3, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)

        res = @middleware.perform(@cap_request)
        assert_twirp_response res
      end

      def test_retries_for_unknown_error_nil_data
        unknown_and_succeed = sequence("unknown and succeed")

        twirp_unknown_response = Twirp::ClientResp.new(data: nil, error: Twirp::Error.unknown("boom"))

        cap_response = Authzd::CapEvaluator::SingleResourceResponse.new(
          results: [
            Authzd::CapEvaluator::Result.new(
              policy: "test_policy",
              outcome: Authzd::CapEvaluator::Outcome::SATISFIED
            )
          ]
        )
        twirp_response = Twirp::ClientResp.new(data: cap_response)

        @cap_evaluator.expects(:perform).with(@cap_request, {}).in_sequence(unknown_and_succeed).returns(twirp_unknown_response)
        @cap_evaluator.expects(:perform).with(@cap_request, {}).in_sequence(unknown_and_succeed).returns(twirp_unknown_response)
        @cap_evaluator.expects(:perform).with(@cap_request, {}).in_sequence(unknown_and_succeed).returns(twirp_response)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 1, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 2, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 3, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.succeeded", { middleware: "cap_retry", operation: "succeeded", attempt: 3, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)

        res = @middleware.perform(@cap_request)
        assert_twirp_response res
      end

      def test_max_retries_w_indeterminate_raises
        cap_unknown_response = Authzd::CapEvaluator::SingleResourceResponse.new(
          results: [
            Authzd::CapEvaluator::Result.new(
              policy: "test_policy",
              outcome: Authzd::CapEvaluator::Outcome::OUTCOME_UNKNOWN
            )
          ]
        )
        twirp_unknown_response = Twirp::ClientResp.new(data: cap_unknown_response)

        @cap_evaluator.expects(:perform).with(@cap_request, {}).times(3).returns(twirp_unknown_response)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 1, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 2, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 3, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).in_sequence(instrumentation_sequence)

        assert_raises(Authzd::CAPUnknownError) do
          @middleware.perform(@cap_request)
        end
      end

      def test_max_retries_w_wait
        @middleware = Middleware::CAPRetry.new(wait_seconds: 0.1, max_attempts: 3).tap do |middleware|
          middleware.request = @cap_evaluator
        end
        @middleware.stubs(:sleep).times(2).with(0.1)

        cap_unknown_response = Authzd::CapEvaluator::SingleResourceResponse.new(
          results: [
            Authzd::CapEvaluator::Result.new(
              policy: "test_policy",
              outcome: Authzd::CapEvaluator::Outcome::OUTCOME_UNKNOWN
            )
          ]
        )
        twirp_unknown_response = Twirp::ClientResp.new(data: cap_unknown_response)

        @cap_evaluator.expects(:perform).with(@cap_request, {}).times(3).returns(twirp_unknown_response)

        instrumentation_sequence = sequence("instrumentation")
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 1, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 2, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).with("authzd.client.cap_retry.tried", { middleware: "cap_retry", operation: "tried", attempt: 3, authz_request: @cap_request, rpc: "evaluate_policies_for_single_resource" }).in_sequence(instrumentation_sequence)
        Instrumenter.expects(:instrument).in_sequence(instrumentation_sequence)

        assert_raises(Authzd::CAPUnknownError) do
          @middleware.perform(@cap_request)
        end
      end

      def test_retry_with_factor
        retryable_error = RetryableError.new

        cap_evaluator_sequence = sequence("capevaluator")
        @cap_evaluator.expects(:perform).with(@cap_request, { '__timeout_factor__' => 1 }).raises(retryable_error).in_sequence(cap_evaluator_sequence)
        @cap_evaluator.expects(:perform).with(@cap_request, { '__timeout_factor__' => 2 }).raises(retryable_error).in_sequence(cap_evaluator_sequence)
        @cap_evaluator.expects(:perform).with(@cap_request, { '__timeout_factor__' => 3 }).raises(retryable_error).in_sequence(cap_evaluator_sequence)

        options = {
          max_attempts: 3,
          retryable_errors: [RetryableError, AnotherRetryableError],
          retry_factor: true
        }
        @middleware = Middleware::CAPRetry.new(**options).tap do |middleware|
          middleware.request = @cap_evaluator
        end

        assert_raises(RetryableError) do
          @middleware.perform(@cap_request)
        end
      end
    end
  end
end
