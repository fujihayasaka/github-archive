# typed: strict
# frozen_string_literal: true

module MergeQueues
  # Interface describing mutation that can occur from the Merge Queue. This enables us to test with limited
  # amounts of DB state required.
  module ICommand
    extend T::Helpers
    interface!

    module Result
      extend T::Helpers
      sealed!
      abstract!

      # Call the block up until max_attempts number of times. Retrying only occurs when the Error object returned
      # permits retrying.
      sig do
        type_parameters(:T).params(
          max_attempts: Integer,
          block: T.proc.returns(T.all(ICommand::Result, T.type_parameter(:T)))
        ).returns(T.type_parameter(:T))
      end
      def self.with_retry(max_attempts = 3, &block)
        attempts = 0

        loop do
          attempts += 1

          result = yield

          return result unless result.permit_retry
          return result if attempts >= max_attempts

          case result
          when ICommand::Result::Error
            GitHub.logger.info(
              "Retryable error",
              "exception.message": result.as_exception,
              "gh.merge_queue.command_retry_attempts": attempts,
            )
          when ICommand::Result::GitTreeError
            GitHub.logger.info("no_such_head")
          end

          case result
          when ICommand::Result::Error, ICommand::Result::GitTreeError
            # Don't slow down tests that include retrying.
            next if Rails.env.test?
            sleep(attempts)
          else
            return result
          end
        end
      end

      # Determines if our retry logic should apply to this return value.
      sig { returns(T::Boolean) }
      def permit_retry
        false
      end

      class Error < T::Struct
        include Result

        const :message, String
        const :permit_retry, T::Boolean, default: false
        const :exception, T.nilable(Exception), default: nil

        sig { returns(Errors::CommandFailed) }
        def as_exception
          domain_exception = Errors::CommandFailed.new(message)

          if exception.nil?
            domain_exception
          else
            wrap_exception_with(domain_exception)
          end
        end

        private

        sig { params(wrapper: Errors::CommandFailed).returns(Errors::CommandFailed) }
        def wrap_exception_with(wrapper)
          # The only way to set the `cause` field on an exception is to raise
          # it from a rescue block. In this case, we want to set our exception
          # as the cause of a `MergeQueues::Errors::CommandFailed` instance.
          begin
            raise T.must(exception)
          rescue # rubocop:todo Lint/GenericRescue
            raise wrapper
          end
        rescue Errors::CommandFailed => result
          result
        end
      end

      class MergeConflictError < T::Struct
        include Result
        const :details, T.nilable(T::Hash[Symbol, T.untyped]), default: nil
      end

      class RebaseConflictError
        include Result
      end

      class InvalidMergeCommitError
        include Result
      end

      class AlreadyMergedError
        include Result
      end

      class GitTreeError
        include Result

        # This is a very race prone error due to PR background jobs and git systems state.
        sig { returns(T::Boolean) }
        def permit_retry
          true
        end
      end

      class Success < T::Struct
        include Result
      end

      class CreateRefSuccess < T::Struct
        include Result
        const :head_ref, String
        const :head_sha, String
        const :base_sha, String
      end

      class BranchProtectionError < T::Struct
        include Result

        const :message, String
        const :exception, Exception
      end

      class MergeSuccess < T::Struct
        include Result
        const :old_oid, String
        const :new_oid, String
        const :head_ref, String
        const :written_at, ActiveSupport::TimeWithZone
      end
    end

    CreateRefResult = T.type_alias do
      T.any(
        Result::CreateRefSuccess,
        Result::Error,
        Result::MergeConflictError,
        Result::RebaseConflictError,
        Result::AlreadyMergedError,
        Result::GitTreeError,
        Result::InvalidMergeCommitError,
        Result::BranchProtectionError,
      )
    end

    MergeResult = T.type_alias do
      T.any(
        Result::MergeSuccess,
        Result::Error,
        Result::BranchProtectionError,
        Result::AlreadyMergedError,
      )
    end

    GenericResult = T.type_alias { T.any(Result::Error, Result::Success) }

    # Merge a specific Entry and it's ancestors.
    sig do
      abstract.params(
        entry: T.any(Entry, MergeQueueEntry),
        expected_base_sha: String,
        actor: T.nilable(User),
      ).returns(MergeResult)
    end
    def merge!(entry, expected_base_sha:, actor: nil); end

    # After a merge group successfully merges to the base branch, save all RuleSuite records.
    sig do
      abstract.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_method: IConfiguration::MergeMethod,
      ).returns(GenericResult)
    end
    def finalize_rule_suite_records!(entries, merge_method:); end

    # Perform post-merge operations on Pull Requests to ensure their state changes.
    sig do
      abstract.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_result: Result::MergeSuccess,
        merge_method: IConfiguration::MergeMethod,
        merge_action: T.nilable(Symbol),
      ).returns(GenericResult)
    end
    def update_merged_pull_requests!(entries, merge_result:, merge_method:, merge_action: nil); end

    # Track metrics for the Merge Queue.
    sig do
      abstract.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_result: Result::MergeSuccess
      ).returns(GenericResult)
    end
    def record_merge_stats!(entries, merge_result:); end

    # Record an insights record when an entire merge group is rejected due to rules / branch protections.
    sig do
      abstract.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_result: Result::BranchProtectionError,
        merge_method: IConfiguration::MergeMethod,
      ).returns(GenericResult)
    end
    def record_merge_group_failure!(entries, merge_result:, merge_method:); end

    # Remove the given entries from the Merge Queue.
    sig do
      abstract.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        actor: T.nilable(User),
        reason: T.nilable(Entry::RemovalReason)
      ).returns(GenericResult)
    end
    def remove!(entries, actor: nil, reason: Entry::RemovalReason::Unknown); end

    # Retry a build that has failed.
    sig { abstract.params(entry: Entry).returns(GenericResult) }
    def retry_checks!(entry); end

    # Persist the changes to the given entries to the database.
    sig { abstract.params(entries: T::Array[Entry]).returns(GenericResult) }
    def update!(entries); end

    # Create the git ref for the Entry from the requested base sha.
    sig { abstract.params(entry: Entry, base_sha: String, method: IConfiguration::MergeMethod).returns(CreateRefResult) }
    def create_ref!(entry, base_sha:, method:); end

    # Request checks for an entry that contains retryable Checks.
    sig { abstract.params(entry: Entry, create_ref_result: Result::CreateRefSuccess).returns(GenericResult) }
    def request_checks!(entry, create_ref_result:); end

    # Deliver webhooks related to subscribing to the Merge Queue.
    sig { abstract.params(payload: WebHook).returns(GenericResult) }
    def dispatch_webhook!(payload); end

    # Recalculate the positions of the entries in the queue.
    sig { abstract.params(entries: EntryList).returns(GenericResult) }
    def recalculate_positions!(entries); end

    # Store merge conflict data to be shown in the PullRequests#show interface.
    sig { abstract.params(entry: Entry, conflict: Result::MergeConflictError).returns(GenericResult) }
    def store_merge_conflict!(entry, conflict:); end

    sig { abstract.params(entries: T::Array[T.any(Entry, MergeQueueEntry)]).returns(GenericResult) }
    def delete_refs!(entries); end

    # Determine if the feature is enabled for the current merge queue.
    sig { abstract.params(feature: Symbol).returns(T::Boolean) }
    def feature_enabled?(feature); end
  end
end
