# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MergeStateStatus < Platform::Enums::Base
      description "Detailed status information about a pull request merge."

      value "DIRTY", "The merge commit cannot be cleanly created.", value: :dirty
      value "UNKNOWN", "The state cannot currently be determined.", value: :unknown
      value "BLOCKED", "The merge is blocked.", value: :blocked
      value "BEHIND", "The head ref is out of date.", value: :behind
      value "DRAFT", "The merge is blocked due to the pull request being a draft.", value: :draft, deprecated: {
                start_date: Date.new(2020, 9, 13),
                reason: "DRAFT state will be removed from this enum and `isDraft` should be used instead",
                superseded_by: "Use PullRequest.isDraft instead.",
                owner: "nplasterer",
              }
      value "UNSTABLE", "Mergeable with non-passing commit status.", value: :unstable
      value "HAS_HOOKS", "Mergeable with passing commit status and pre-receive hooks.", value: :has_hooks
      value "CLEAN", "Mergeable and passing commit status.", value: :clean
    end
  end
end
