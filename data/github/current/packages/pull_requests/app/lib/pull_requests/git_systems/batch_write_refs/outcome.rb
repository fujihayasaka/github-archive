# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    # Batching class for doing ref updates that conform to branch rules/protections.
    module BatchWriteRefs
      module Outcome
        extend T::Helpers
        include Kernel

        abstract!
        sealed!

        # Initial state, signals that this ref update was never attempted.
        class Pending
          include Outcome
        end

        # Signals that the request and ref update were both successful.
        class Success
          include Outcome
        end

        # Signals that the request succeeded, but had individual ref update failures.
        class Failed < T::Struct
          include Outcome

          const :reason, FailureReason
          const :message, String
          const :exception, T.nilable(Exception)
        end

        # Signals that the request had an error.
        class Error
          include Outcome
        end
      end
    end
  end
end
