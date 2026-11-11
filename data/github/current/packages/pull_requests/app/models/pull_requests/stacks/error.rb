# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    class Error < T::Struct
      class FailureReason < T::Enum
        enums do
          # Invalid stack state
          CrossRepo = new("CROSS_REPO")
          MismatchedRepo = new("MISMATCHED_REPO")
          NonLinear = new("NON_LINEAR")
          StackContentsMismatch = new("STACK_CONTENTS_MISMATCH")
          TooSmall = new("TOO_SMALL")
          ValidationFailed = new("VALIDATION_FAILED")
          FullyMerged = new("FULLY_MERGED")

          # Individual PR statuses
          AlreadyStacked = new("ALREADY_STACKED")
          WrongStack = new("WRONG_STACK")
          NotStacked = new("NOT_STACKED")
          AutoMergeEnabled = new("AUTO_MERGE_ENABLED")
          InMergeQueue = new("IN_MERGE_QUEUE")
          Merged = new("MERGED")
          AllPullsLocked = new("ALL_PULLS_LOCKED")
          MergeConflict = new("MERGE_CONFLICT")

          # Dependency errors
          GitReadError = new("GIT_READ_ERROR")
          GitWriteError = new("GIT_WRITE_ERROR")
        end
      end

      const :reason, FailureReason
      const :pulls, T.nilable(T::Array[PullRequest]), default: nil
      const :exception, T.nilable(Exception), default: nil

      sig { returns(String) }
      def message
        case r = reason
        when FailureReason::TooSmall
          "Stack must contain at least two pull requests"
        when FailureReason::NonLinear
          "Pull requests must form a stack, where each PR's base ref is the previous PR's head ref"
        when FailureReason::CrossRepo
          "Pull requests from forks cannot be added to stacks."
        when FailureReason::MismatchedRepo
          "Pull requests must be in the same repo to form a stack"
        when FailureReason::StackContentsMismatch
          "Stack contents have changed"
        when FailureReason::FullyMerged
          "All pull requests in the stack are merged"
        when FailureReason::AlreadyStacked
          message_with_pull_numbers(
            one: "Pull request %s is already part of a stack",
            many: "Pull requests %s are already part of a stack",
            unknown_number: "Some pull requests are already part of a stack",
          )
        when FailureReason::WrongStack
          message_with_pull_numbers(
            one: "Pull request %s is part of a different stack",
            many: "Pull requests %s are part of a different stack",
            unknown_number: "Some pull requests are part of a different stack",
          )
        when FailureReason::NotStacked
          message_with_pull_numbers(
            one: "Pull request %s is not part of a stack",
            many: "Pull requests %s are not part of a stack",
            unknown_number: "Some pull requests are not part of a stack",
          )
        when FailureReason::AutoMergeEnabled
          message_with_pull_numbers(
            one: "Pull request %s has auto-merge enabled",
            many: "Pull requests %s have auto-merge enabled",
            unknown_number: "Some pull requests have auto-merge enabled",
          )
        when FailureReason::InMergeQueue
          message_with_pull_numbers(
            one: "Pull request %s is in the merge queue",
            many: "Pull requests %s are in the merge queue",
            unknown_number: "Some pull requests are in the merge queue",
          )
        when FailureReason::Merged
          message_with_pull_numbers(
            one: "Pull request %s is merged",
            many: "Pull requests %s are merged",
            unknown_number: "Some pull requests are merged",
          )
        when FailureReason::AllPullsLocked
          message_with_pull_numbers(
            one: "Pull request %s cannot be removed from this stack",
            many: "Pull requests %s cannot be removed from this stack",
            unknown_number: "Pull requests in this stack cannot be removed",
          )
        when FailureReason::MergeConflict
          message_with_pull_numbers(
            one: "Pull request %s encountered a merge conflict",
            many: "Pull requests %s encountered merge conflicts",
            unknown_number: "Encountered a merge conflict",
          )
        when FailureReason::ValidationFailed
          validation_failed_message
        when FailureReason::GitReadError
          "Failed to load state from Git"
        when FailureReason::GitWriteError
          "Failed to update state in Git"
        else
          T.absurd(r)
        end
      end

      sig { returns(T.noreturn) }
      def raise!
        raise ArgumentError, message
      end

      sig { returns(Integer) }
      def http_status
        case r = reason
        when FailureReason::TooSmall, FailureReason::NonLinear,
          FailureReason::CrossRepo, FailureReason::MismatchedRepo,
          FailureReason::AlreadyStacked, FailureReason::ValidationFailed,
          FailureReason::AutoMergeEnabled, FailureReason::InMergeQueue,
          FailureReason::FullyMerged, FailureReason::WrongStack,
          FailureReason::NotStacked, FailureReason::Merged,
          FailureReason::AllPullsLocked
          422
        when FailureReason::StackContentsMismatch, FailureReason::MergeConflict
          409
        when FailureReason::GitReadError, FailureReason::GitWriteError
          500
        else
          T.absurd(r)
        end
      end

      private

      sig { returns(String) }
      def validation_failed_message
        case e = exception
        when ActiveRecord::RecordInvalid
          e.record.errors.full_messages.to_sentence
        else
          "An unexpected error occurred when validating the stack"
        end
      end

      sig { params(unknown_number: String, one: String, many: String).returns(String) }
      def message_with_pull_numbers(unknown_number:, one:, many:)
        numbers = pulls&.map { "##{_1.number}" } || []
        if numbers.empty?
          unknown_number
        elsif numbers.count == 1
          one % numbers.first
        else
          many % numbers.join(", ")
        end
      end
    end
  end
end
