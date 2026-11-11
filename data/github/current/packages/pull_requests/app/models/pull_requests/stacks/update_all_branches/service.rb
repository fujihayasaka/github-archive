# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module UpdateAllBranches
      class Service
        include GitHub::Memoizer

        class Result < T::Enum
          enums do
            SuccessfullyEnqueued = new("SUCCESSFULLY_ENQUEUED")
            AlreadyRunning = new("ALREADY_RUNNING")
            NotStacked = new("NOT_STACKED")
            StackContentsChanged = new("STACK_CONTENTS_CHANGED")
            IncludesMergedPulls = new("INCLUDES_MERGED_PULLS")
            IncludesEnqueuedPulls = new("INCLUDES_ENQUEUED_PULLS")
            NoRelevantPulls = new("NO_RELEVANT_PULLS")
          end
        end

        sig do
          params(
            stack: PullRequests::Stack,
            actor: User,
            expected_head_oid_by_pr_number: T::Hash[Integer, String],
            start_pull_request: T.nilable(PullRequest),
          ).void
        end
        def initialize(stack:, actor:, expected_head_oid_by_pr_number:, start_pull_request: nil)
          @stack = stack
          @start_pull_request = start_pull_request
          @actor = actor
          @expected_head_oid_by_pr_number = expected_head_oid_by_pr_number
        end

        sig { returns(Result) }
        def call
          return Result::NotStacked unless @start_pull_request.nil? || @start_pull_request.stack == @stack
          return Result::NoRelevantPulls unless relevant_pulls.any?
          return Result::StackContentsChanged unless expected_head_oids_match?
          return Result::IncludesMergedPulls if relevant_pulls.any?(&:merged?)
          return Result::IncludesEnqueuedPulls if relevant_pulls.any?(&:in_merge_queue?)

          existing_status = Status.find(stack: @stack)
          if existing_status.present? && !existing_status.done?
            return Result::AlreadyRunning
          end

          start_pull_request = T.must(relevant_pulls.first)
          new_status = Status.build(stack: @stack, start_pull_request:)
          new_status.save!

          UpdateAllBranchesJob.perform_later(
            start_pull_request:,
            actor: @actor,
            expected_head_oid_by_pr_number: relevant_head_oid_by_pr_number.transform_keys(&:to_s),
          )
          Result::SuccessfullyEnqueued
        end

        private

        sig { returns(T::Enumerable[PullRequest]) }
        memoize def relevant_pulls
          if @start_pull_request
            @stack.pulls_from(@start_pull_request)
          else
            @stack.pull_requests
              .drop_while(&:merged?)
              .drop_while(&:in_merge_queue?)
          end
        end

        sig { returns(T::Hash[Integer, String]) }
        memoize def relevant_head_oid_by_pr_number
          relevant_pulls.to_h { |pr| [pr.number, pr.head_sha] }
        end

        sig { returns(T::Boolean) }
        def expected_head_oids_match?
          relevant_head_oid_by_pr_number.all? do |pr_number, head_sha|
            @expected_head_oid_by_pr_number[pr_number] == head_sha
          end
        end
      end
    end
  end
end
