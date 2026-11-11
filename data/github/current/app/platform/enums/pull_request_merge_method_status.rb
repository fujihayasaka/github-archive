# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestMergeMethodStatus < Platform::Enums::Base
      description "Represents the allowability status of a merge method."

      value "ALLOWED", "The merge method is allowed.", value: :allowed
      value "BLOCKED", "The merge method is blocked.", value: :blocked
      value "ALLOWED_WITH_BYPASS", "The merge method is allowed when bypassing rules.", value: :allowed_with_bypass
    end
  end
end
