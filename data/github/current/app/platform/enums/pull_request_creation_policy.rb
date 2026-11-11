# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestCreationPolicy < Platform::Enums::Base
      docs_category :pulls
      description "The policy controlling who can create pull requests in a repository."

      value "ALL", "Anyone can create pull requests.", value: Configurable::PullRequestCreationPolicy::ALL
      value "COLLABORATORS_ONLY", "Only collaborators can create pull requests.", value: Configurable::PullRequestCreationPolicy::COLLABORATORS_ONLY
    end
  end
end
