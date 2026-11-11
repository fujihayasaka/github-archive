# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ProjectCardItem < Platform::Unions::Base
      description "Types that can be inside Project Cards."

      possible_types(
        Objects::Issue,
        Objects::PullRequest,
      )
    end
  end
end
