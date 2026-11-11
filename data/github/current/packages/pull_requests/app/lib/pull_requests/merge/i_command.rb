# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
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
            block: T.proc.returns(T.type_parameter(:T))
          ).returns(T.type_parameter(:T))
        end
        def self.with_retry(max_attempts = 3, &block)
          attempts = 0

          loop do
            attempts += 1

            case result = yield
            when ICommand::Result::Error
              if result.permit_retry
                if attempts < max_attempts
                  next if Rails.env.test? #rubocop:disable GitHub/DoNotBranchOnRailsEnv
                  sleep(attempts)
                else
                  GitHub.logger.info(
                    "Retryable error",
                    "exception.message": result.as_exception,
                    "gh.merge_comment.command_retry_attempts": attempts,
                  )
                end
              end
            end

            return result
          end
        end

        class Success
          include Result
        end

        class StaleMergeCommit
          include Result
        end

        class TerminalBranchRuleFailure < T::Struct
          include Result

          const :rules, T::Array[RulesEngine::RepositoryRuleRollup::RuleType], default: []
          const :messages, T.nilable(T::Array[String]), default: nil
        end

        class ResolvableBranchRuleFailure < T::Struct
          include Result

          const :rules, T::Array[RulesEngine::RepositoryRuleRollup::RuleType]
          const :messages, T.nilable(T::Array[String])
        end

        class DuplicateDatabaseRecord
          include Result
        end

        class MergeCommitCreated < T::Struct
          const :oid, String
        end

        class NotMergeable
          include Result
        end

        class Error < T::Struct
          include Result

          const :message, String
          const :permit_retry, T::Boolean, default: false
          const :exception, T.nilable(Exception), default: nil
          const :error_code, T.nilable(Symbol), default: nil

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
            begin
              raise T.must(exception)
            rescue
              raise wrapper
            end
          rescue Errors::CommandFailed => result
            result
          end
        end
      end

      SuccessOrError = T.type_alias { T.any(Result::Success, Result::Error) }

      ValidateResult = T.type_alias do
        T.any(
          Result::Success,
          Result::Error,
          Results::Invalid,
          Results::AlreadyMerged,
          Result::TerminalBranchRuleFailure,
          Result::ResolvableBranchRuleFailure,
        )
      end

      sig { abstract.returns(ValidateResult) }
      def validate!; end

      CreateAutoMergeRequestResult = T.type_alias do
        T.any(
          Result::Success,
          Result::Error,
          Result::DuplicateDatabaseRecord,
        )
      end

      sig do
        abstract.params(
          commit_title: T.nilable(String),
          commit_message: T.nilable(String),
          merge_method: Symbol,
          actor_ip_address: T.nilable(String),
          commit_email_address_id: T.nilable(Integer),
        ).returns(CreateAutoMergeRequestResult)
      end
      def create_auto_merge_request!(commit_title:, commit_message:, merge_method:, actor_ip_address:, commit_email_address_id:); end

      CreateMergeCommitResult = T.type_alias do
        T.any(
          Result::MergeCommitCreated,
          Result::Error,
        )
      end

      sig { abstract.returns(CreateMergeCommitResult) }
      def create_merge_commit!; end

      PerformMergeResult = T.type_alias do
        T.any(
          Result::Success,
          Result::Error,
          Result::StaleMergeCommit,
          Result::TerminalBranchRuleFailure,
          Results::AlreadyMerged
        )
      end

      sig { abstract.params(merge_commit_sha: T.nilable(String)).returns(PerformMergeResult) }
      def perform_merge!(merge_commit_sha:); end

      AddToMergeQueueResult = T.type_alias do
        T.any(
          SuccessOrError,
          Result::ResolvableBranchRuleFailure,
          Result::TerminalBranchRuleFailure,
          Result::DuplicateDatabaseRecord
        )
      end

      sig { abstract.params(jump: T::Boolean, solo: T::Boolean).returns(AddToMergeQueueResult) }
      def add_to_merge_queue!(jump:, solo:); end

      sig { abstract.returns(SuccessOrError) }
      def delete_auto_merge_request!; end

      sig { abstract.void }
      def emit_create_telemetry!; end

      sig { abstract.params(reason: Enums::DisableReason).returns(SuccessOrError) }
      def emit_disabled_telemetry!(reason:); end

      sig { abstract.void }
      def publish_live_update!; end

      sig { abstract.params(enqueue_reason: T.nilable(String)).void }
      def request_auto_merge_job!(enqueue_reason: nil); end

      sig { abstract.returns(SuccessOrError) }
      def request_cprmc!; end

      sig { abstract.params(name: Symbol).returns(T::Boolean) }
      def feature_enabled?(name); end
    end
  end
end
