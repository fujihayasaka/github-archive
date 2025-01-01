# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class DashboardPinnableItem < Platform::Unions::Base
      description "Types that can be pinned to a user's dashboard."
      mobile_only true

      possible_types(Objects::Gist, Objects::Repository, Objects::Issue,
        Objects::Project, Objects::PullRequest, Objects::User,
        Objects::Organization, Objects::Team)
    end
  end
end
