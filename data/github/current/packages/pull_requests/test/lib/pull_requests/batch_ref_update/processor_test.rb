# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./helpers"
require_relative "./mock_command"

module PullRequests
  module BatchRefUpdate
    class ProcessorTest < GitHub::TestCase
      include MockCommand::Assertions
      include Helpers

      test "performs no actions when there are no requests" do
        requests = []
        command = MockCommand.new.as_logger

        Processor.new(command:, requests:).call

        assert_actions_performed(command, [])
      end

      context "eligible requests" do
        test "single ref update" do
          requests = [build_eligible_request]
          command = MockCommand.new.as_logger

          Processor.new(command:, requests:).call

          assert_actions_performed command, [
            did_mark_requests_as_processing(requests:),
            did_update_refs(requests:),
            did_delete_processing_requests(requests:),
          ]
        end

        test "failing to mark requests as processing should prevent ref updates" do
          requests = [build_eligible_request]
          command = MockCommand.new(
            mark_as_processing: [ICommand::Result::Error.new(message: "failed")]
          ).as_logger

          Processor.new(command:, requests:).call

          assert_actions_performed command, [
            did_mark_requests_as_processing(requests:),
          ]
        end

        test "failing to delete records should not prevent processor from finishing" do
          requests = [build_eligible_request]
          command = MockCommand.new(
            delete_processing_requests: [ICommand::Result::Error.new(message: "failed")]
          ).as_logger

          Processor.new(command:, requests:).call

          assert_actions_performed command, [
            did_mark_requests_as_processing(requests:),
            did_update_refs(requests:),
            did_delete_processing_requests(requests:),
          ]
        end

        test "dispatches failure job for pending requests" do
          request = build_eligible_request
          requests = [request]
          command = MockCommand.new(
            update_refs: [
              ICommand::Result::UpdateRefs.new(
                requests: {
                  request => GitSystems::BatchWriteRefs::Outcome::Pending.new
                }
              )
            ]
          ).as_logger

          Processor.new(command:, requests:).call

          assert_actions_performed command, [
            did_mark_requests_as_processing(requests:),
            did_update_refs(requests:),
            did_dispatch_request_failure(request:, reason: Enums::Failures::PendingRefUpdate),
            did_delete_processing_requests(requests:),
          ]
        end

        test "dispatches failure job for failed requests" do
          request = build_eligible_request
          requests = [request]
          command = MockCommand.new(
            update_refs: [
              ICommand::Result::UpdateRefs.new(
                requests: {
                  request => GitSystems::BatchWriteRefs::Outcome::Failed.new(
                    reason: GitSystems::BatchWriteRefs::FailureReason::RefUpdateFailed,
                    message: "object not found",
                  )
                }
              )
            ]
          ).as_logger

          Processor.new(command:, requests:).call

          assert_actions_performed command, [
            did_mark_requests_as_processing(requests:),
            did_update_refs(requests:),
            did_dispatch_request_failure(request:, reason: Enums::Failures::GitFailure),
            did_delete_processing_requests(requests:),
          ]
        end

        test "dispatches failure job for update_refs errors" do
          request = build_eligible_request
          requests = [request]

          exception = StandardError.new("bad things happened")

          command = MockCommand.new(update_refs: [
            ICommand::Result::UpdateRefs.new(
              exception:,
              requests: { request => GitSystems::BatchWriteRefs::Outcome::Error.new }
            )
          ]).as_logger

          Processor.new(command:, requests:).call

          assert_actions_performed command, [
            did_mark_requests_as_processing(requests:),
            did_update_refs(requests:),
            did_dispatch_request_failure(request:, reason: Enums::Failures::GitError),
            did_delete_processing_requests(requests:),
          ]
        end
      end

      test "dispatches failure job and does not update ref for ineligible request" do
        request = build_ineligible_request
        requests = [request]
        command = MockCommand.new.as_logger

        Processor.new(command:, requests:).call

        assert_actions_performed command, [
          did_mark_requests_as_processing(requests:),
          did_dispatch_request_failure(request: request, reason: requests.first.reason),
          did_delete_processing_requests(requests:),
        ]
      end

      test "handles eligible and ineligible requests in same batch" do
        eligible_request = build_eligible_request
        invalid_request = build_ineligible_request

        requests = [eligible_request, invalid_request]

        command = MockCommand.new.as_logger

        Processor.new(command:, requests:).call

        assert_actions_performed command, [
          did_mark_requests_as_processing(requests:),
          did_dispatch_request_failure(request: invalid_request, reason: invalid_request.reason),
          did_update_refs(requests: [eligible_request]),
          did_delete_processing_requests(requests:),
        ]
      end

      private

      sig { params(command: ICommand).returns(Logging::Commands) }
      def wrap_command(command)
        Logging::Commands.new(command)
      end
    end
  end
end
