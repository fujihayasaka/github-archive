# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module Merging
      module Result
        extend T::Helpers
        sealed!
        abstract!

        # The stack was successfully enqueued for merging.
        class Success < T::Struct
          include Result
        end

        # The enqueue operation failed with an actionable error.
        class Error < T::Struct
          include Result

          const :message, String
          const :exception, T.nilable(Exception), default: nil
        end

        # The merge could not be completed due to a conflict.
        class Conflict < T::Struct
          include Result

          const :message, String
        end

        # The stack cannot be enqueued yet because a prerequisite is
        # unmet (e.g. a parent PR is still open). A subsequent event
        # may resolve the condition and allow a retry.
        class Waiting < T::Struct
          include Result

          const :message, String
        end

        # The pull request is no longer part of a stack, so there is
        # nothing to enqueue.
        class NoLongerStacked < T::Struct
          include Result
        end
      end
    end
  end
end
