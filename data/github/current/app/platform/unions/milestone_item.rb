# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class MilestoneItem < Platform::Unions::Base
      docs_category :issues
      description "Types that can be inside a Milestone."

      possible_types(
        Objects::Issue,
        Objects::PullRequest,
      )
    end
  end
end
