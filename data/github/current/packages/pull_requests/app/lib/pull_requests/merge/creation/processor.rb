# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Creation
      class Processor
        include GitHub::Memoizer

        class AlreadyEnqueued < T::Struct
          const :auto_merge_request, T.nilable(AutoMergeRequest)
          const :merge_queue_entry, T.nilable(MergeQueueEntry)
        end

        class Error < T::Struct
          const :exception, T.nilable(Exception)
          const :message, String
        end

        sig do
          params(
            command: ICommand,
            request: Request,
          ).void
        end
        def initialize(command:, request:)
          @command = command
          @request = request
        end

        sig { returns(T.any(ICommand::Result::Success, ICommand::Result::DuplicateDatabaseRecord, ICommand::Result::Error, Results::Invalid, Results::AlreadyMerged)) }
        def call
          case validate_result = @command.validate!
          when ICommand::Result::Success,
               ICommand::Result::Error,
               Results::AlreadyMerged,
               Results::Invalid
            return validate_result
          when ICommand::Result::TerminalBranchRuleFailure
            return Results::Invalid.new(
              reason: Enums::Validations::BranchRuleFailure,
              message: validate_result.messages&.join(", ") || "Failed"
            )
          when ICommand::Result::ResolvableBranchRuleFailure
            # TODO: This should allow for most scenarios.
          else T.absurd(validate_result)
          end

          result = @command.create_auto_merge_request!(
            commit_email_address_id: @request.commit_email_address_id,
            commit_title: @request.commit_title,
            commit_message: @request.commit_message,
            merge_method:,
            actor_ip_address: @request.actor_ip_address,
          )

          @command.emit_create_telemetry!

          @command.publish_live_update!

          result
        end

        private

        # Generate the legacy DB column for the old AutoMergeJob implementation.
        sig { returns(Symbol) }
        def merge_method
          case mode = @request.mode
          when Mode::Queue
            if mode.solo
              :merge_queue_solo
            elsif mode.jump
              :merge_queue_jump
            else
              :merge_queue
            end
          else
            case strategy = mode.strategy
            when Enums::Strategy::Squash
              :auto_squash_and_merge
            when Enums::Strategy::Rebase
              :auto_rebase_and_merge
            else
              :auto_merge
            end
          end
        end
      end
    end
  end
end
