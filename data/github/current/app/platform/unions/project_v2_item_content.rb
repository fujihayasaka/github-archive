# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ProjectV2ItemContent < Platform::Unions::Base
      description "Types that can be inside Project Items."

      visibility :public, environments: [:dotcom, :enterprise]

      possible_types(
        Objects::Issue,
        Objects::PullRequest,
        Objects::DraftIssue
      )
    end
  end
end
