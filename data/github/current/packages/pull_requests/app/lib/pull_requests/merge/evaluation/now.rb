# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Evaluation
      class Now
        sig { params(command: ICommand, request: Request, mode: Mode::Now).void }
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
            Enums::Signal::Done
          when ICommand::Result::Error
            # TODO: Some validation error occurred. What should we return?
            Enums::Signal::Errored
          when ICommand::Result::ResolvableBranchRuleFailure
            Enums::Signal::Waiting
          when ICommand::Result::Success
            case merge_result = ICommand::Result.with_retry { @command.perform_merge!(merge_commit_sha: @request.merge_commit_sha) }
            when ICommand::Result::Success,
                ICommand::Result::StaleMergeCommit,
                ICommand::Result::TerminalBranchRuleFailure,
                Results::AlreadyMerged
              Enums::Signal::Done
            when ICommand::Result::Error
              Enums::Signal::Errored
            else T.absurd(merge_result)
            end
          else T.absurd(validations)
          end
        end
      end
    end
  end
end
