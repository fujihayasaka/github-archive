# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module UpdateAllBranches
      class EnqueueService < BaseService
        class Success; end
        class AlreadyRunning; end

        Result = T.type_alias { T.any(Success, AlreadyRunning, Error) }
        ResultType = type_member { { fixed: Result } }

        sig do
          params(
            stack: PullRequests::Stack,
            actor: User,
            expected_head_oid_by_pr_number: T::Hash[Integer, String],
            start_pull_request: T.nilable(PullRequest),
            log_context: T::Hash[String, String],
          ).returns(Result)
        end
        def self.call(stack:, actor:, expected_head_oid_by_pr_number:, start_pull_request: nil, log_context: {})
          new(stack:, actor:, expected_head_oid_by_pr_number:, start_pull_request:, log_context:).call
        end

        sig do
          params(
            stack: PullRequests::Stack,
            actor: User,
            expected_head_oid_by_pr_number: T::Hash[Integer, String],
            start_pull_request: T.nilable(PullRequest),
            log_context: T::Hash[String, String],
          ).void
        end
        def initialize(stack:, actor:, expected_head_oid_by_pr_number:, start_pull_request: nil, log_context: {})
          @stack = stack
          @start_pull_request = start_pull_request
          @actor = actor
          @expected_head_oid_by_pr_number = expected_head_oid_by_pr_number
          super(log_context:)
        end

        sig { override.returns(String) }
        def metric_key = "update_all_branches_later"

        sig { override.returns(String) }
        def human_name = "Update all branches later"

        sig { override.returns(T::Hash[String, T.untyped]) }
        def service_log_context = {
          "gh.pull_request_stacks.id" => @stack.id,
          "gh.pull_request_stacks.update_all_branches.start_pull_request_id" => @start_pull_request&.id.to_s,
        }

        sig { override.returns(Result) }
        def perform
          if @start_pull_request.present?
            # Caller specified starting PR, so we need to validate it belongs
            # to the right stack.
            unless @start_pull_request.stack == @stack
              return logged_error_result(
                Error::FailureReason::WrongStack,
                pulls: [@start_pull_request]
              )
            end

            relevant_pulls = @stack.pulls_from(@start_pull_request)
          else
            if FeatureFlag.vexi.enabled?(:pull_request_stacks_smaller_rebase_pool, @stack.repository, default: false)
              # Caller did not specify starting PR, so we default to rebasing all
              # PRs that are not already merged, auto merging or currently sitting in the merge queue.
              relevant_pulls = @stack.pull_requests
                .drop_while(&:merged?)
                .drop_while(&:auto_merging?)
                .drop_while(&:in_merge_queue?)
            else
              # Caller did not specify starting PR, so we default to rebasing all
              # PRs that are not already merged or currently in the merge queue.
              relevant_pulls = @stack.pull_requests
                .drop_while(&:merged?)
                .drop_while(&:in_merge_queue?)
            end

            if relevant_pulls.empty?
              return logged_error_result(Error::FailureReason::FullyMerged)
            end
          end

          # If the caller specified the starting PR (or the stack was somehow
          # in an invalid state with unmerged PRs before merged PRs) we
          # might be attempting to rebase something that includes merged or
          # enqueued PRs.
          merged_pulls = relevant_pulls.select(&:merged?)
          if merged_pulls.any?
            return logged_error_result(Error::FailureReason::Merged, pulls: merged_pulls)
          end
          if FeatureFlag.vexi.enabled?(:pull_request_stacks_smaller_rebase_pool, @stack.repository, default: false)
            auto_merging_pulls = relevant_pulls.select(&:auto_merging?)
            if auto_merging_pulls.any?
              return logged_error_result(Error::FailureReason::AutoMergeEnabled, pulls: auto_merging_pulls)
            end
          end
          enqueued_pulls = relevant_pulls.select(&:in_merge_queue?)
          if enqueued_pulls.any?
            return logged_error_result(Error::FailureReason::InMergeQueue, pulls: enqueued_pulls)
          end

          # If the PR branches have been pushed since the caller last checked,
          # we shouldn't proceed with a rebase that was initiated based on
          # stale information.
          actual_head_oid_by_pr_number = relevant_pulls.to_h { |pr| [pr.number, pr.head_sha] }
          has_mismatched_head_oids = actual_head_oid_by_pr_number.any? do |pr_num, actual_head|
            @expected_head_oid_by_pr_number[pr_num] != actual_head
          end
          if has_mismatched_head_oids
            return logged_error_result(Error::FailureReason::StackContentsMismatch)
          end

          # If another rebase is in progress, we shouldn't proceed.
          # This validation should come last so that the time between this check
          # and creating a new status is as small as possible.
          existing_status = Status.find(stack: @stack)
          if existing_status.present? && !existing_status.done?
            return logged_already_running_result
          end

          # At this point we're done validating, and committed to rebasing.
          start_pull_request = T.must(relevant_pulls.first)
          new_status = Status.build(stack: @stack, start_pull_request:)
          new_status.save!

          UpdateAllBranchesJob.perform_later(
            start_pull_request:,
            actor: @actor,
            expected_head_oid_by_pr_number: actual_head_oid_by_pr_number.transform_keys(&:to_s),
          )

          record_success_outcome
          Success.new
        end

        private

        sig { returns(AlreadyRunning) }
        def logged_already_running_result
          record_outcome("already_running")
          AlreadyRunning.new
        end
      end
    end
  end
end
