# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ComparisonStatus < Platform::Enums::Base
      description "The status of a git comparison between two refs."

      value "DIVERGED", "The head ref is both ahead and behind of the base ref, indicating git history has diverged.", value: "diverged"
      value "AHEAD", "The head ref is ahead of the base ref.", value: "ahead"
      value "BEHIND", "The head ref is behind the base ref.", value: "behind"
      value "IDENTICAL", "The head ref and base ref are identical.", value: "identical"
    end
  end
end
