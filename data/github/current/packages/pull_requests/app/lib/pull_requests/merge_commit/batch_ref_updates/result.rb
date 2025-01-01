# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      class Result < T::Struct
        class Outcome < T::Enum
          enums do
            Success = new("success")
            Error = new("error")
            NoRequests = new("no_requests")
          end
        end

        RefUpdate = T.type_alias do
          T.nilable(T.any(ICommand::GenericResult, ICommand::Result::Skipped))
        end

        sig { params(exception: StandardError, ref_update: RefUpdate).returns(Result) }
        def self.error(exception:, ref_update: nil)
          new(outcome: Outcome::Error, exception:, ref_update:)
        end

        const :outcome, Outcome
        const :exception, T.nilable(StandardError)
        const :ref_update, RefUpdate, default: nil
      end
    end
  end
end
