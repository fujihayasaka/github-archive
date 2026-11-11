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
            delete_auto_merge_request
          when ICommand::Result::ResolvableBranchRuleFailure,
               ICommand::Result::Error
            Enums::Signal::Waiting
          when ICommand::Result::Success
            case merge_result = ICommand::Result.with_retry { @command.add_to_merge_queue!(jump: @mode.jump, solo: @mode.solo) }
            when ICommand::Result::Success,
                 ICommand::Result::DuplicateDatabaseRecord
              Enums::Signal::Done
            when ICommand::Result::TerminalBranchRuleFailure
              delete_auto_merge_request
            when ICommand::Result::ResolvableBranchRuleFailure,
                 ICommand::Result::Error
              Enums::Signal::Waiting
            else T.absurd(merge_result)
            end
          else T.absurd(validations)
          end
        end

        sig { returns(Enums::Signal) }
        def delete_auto_merge_request
          case delete_auto_merge_request = ICommand::Result.with_retry { @command.delete_auto_merge_request! }
          when ICommand::Result::Success
            Enums::Signal::Done
          when ICommand::Result::Error
            Enums::Signal::Errored
          else T.absurd(delete_auto_merge_request)
          end
        end
      end
    end
  end
end
