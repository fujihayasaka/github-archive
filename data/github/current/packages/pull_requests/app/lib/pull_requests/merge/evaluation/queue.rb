# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Evaluation
      class Queue
        sig { params(command: ICommand, request: Request, mode: Mode::Queue).void }
        def initialize(command:, request:, mode:)
          @command = command
          @request = request
          @mode = mode
        end

        sig { returns(Enums::Signal) }
        def call
          case validations = @command.validate!
          when Results::Invalid,
               ICommand::Result::TerminalBranchRuleFailure,
               Results::AlreadyMerged
            @command.delete_merge_commit_request!
            return Enums::Signal::Done
          when ICommand::Result::ResolvableBranchRuleFailure,
               ICommand::Result::Error
            return Enums::Signal::Waiting
          when ICommand::Result::Success
            # Everything is valid and we're ready to attempt a merge.
          else T.absurd(validations)
          end

          case result = ICommand::Result.with_retry { @command.add_to_merge_queue!(jump: @mode.jump, solo: @mode.solo) }
          when ICommand::Result::Success,
               ICommand::Result::DuplicateDatabaseRecord
            Enums::Signal::Done
          when ICommand::Result::TerminalBranchRuleFailure
            @command.delete_merge_commit_request!
            Enums::Signal::Done
          when ICommand::Result::ResolvableBranchRuleFailure,
               ICommand::Result::Error
            Enums::Signal::Waiting
          else T.absurd(result)
          end
        end
      end
    end
  end
end
