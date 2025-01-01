# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ProjectNextItemContent < Platform::Unions::Base
      description "Types that can be inside Project Items."
      required_capabilities [:mobile_only_schema_mask]

      possible_types(
        Objects::Issue,
        Objects::PullRequest,
        Objects::DraftIssue
      )
    end
  end
end
