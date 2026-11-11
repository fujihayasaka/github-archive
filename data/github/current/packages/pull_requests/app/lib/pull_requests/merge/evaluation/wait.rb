# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Evaluation
      class Wait
        sig { params(command: ICommand, request: Request, mode: Mode::Wait).void }
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
            # Merging is not possible
            return Enums::Signal::Done
          when ICommand::Result::Error
            # TODO: Some validation error occurred. What should we return?
            return Enums::Signal::Errored
          when ICommand::Result::Success,
               ICommand::Result::ResolvableBranchRuleFailure
            # Everything is valid and we're ready to attempt an auto merge.
          else T.absurd(validations)
          end

          case result = ICommand::Result.with_retry { @command.perform_merge!(merge_commit_sha: @request.merge_commit_sha) }
          when ICommand::Result::Success,
               ICommand::Result::StaleMergeCommit,
               ICommand::Result::TerminalBranchRuleFailure,
               Results::AlreadyMerged
            Enums::Signal::Done
          when ICommand::Result::Error
            Enums::Signal::Errored
          else T.absurd(result)
          end
        end
      end
    end
  end
end
