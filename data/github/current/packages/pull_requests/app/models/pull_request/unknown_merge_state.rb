# typed: true
# frozen_string_literal: true

class PullRequest
  class UnknownMergeState < MergeState
    def mergeable
      nil
    end

    def async_status
      Promise.resolve(:unknown)
    end
  end
end
