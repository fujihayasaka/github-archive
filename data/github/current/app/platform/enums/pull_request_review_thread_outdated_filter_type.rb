# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewThreadOutdatedFilterType < Platform::Enums::Base
      description "The possible outdated filter types of a pull request review thread."

      value "ONLY_OUTDATED", "Only includes outdated review threads"
      value "EXCLUDE_OUTDATED", "Exclude outdated review threads"
      value "INCLUDE_OUTDATED", "Includes outdated as well as up-to-date review threads"
    end
  end
end
