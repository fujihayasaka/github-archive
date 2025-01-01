# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestMergeAction < Platform::Enums::Base
      description "Represents the available actions to use when merging a pull request."

      value "DIRECT_MERGE", "Merge the pull request immediately.", value: :direct_merge
      value "MERGE_QUEUE", "Merge the pull request via the merge queue.", value: :merge_queue
    end
  end
end
