# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestMergeRequirementsState < Platform::Enums::Base
      description "Detailed status information about a pull request merge."

      value "UNKNOWN", "The pull request state cannot currently be determined.", value: :unknown
      value "MERGEABLE", "The pull request can be merged in this state.", value: :mergeable
      value "UNMERGEABLE", "The pull request cannot be merged in this state.", value: :unmergeable
    end
  end
end
