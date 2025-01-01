# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestMergeConditionResult < Platform::Enums::Base
      description "Represents the result of evaluating the merge condition."

      value "PASSED", "The condition passed.", value: :passed
      value "FAILED", "The condition failed.", value: :failed
      value "UNKNOWN", "The result is unknown or cannot be calculated at this time.", value: :unknown
    end
  end
end
