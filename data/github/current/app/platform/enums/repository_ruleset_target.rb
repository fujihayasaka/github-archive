# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryRulesetTarget < Platform::Enums::Base
      description "The targets supported for rulesets."

      value "BRANCH", "Branch", value: "branch"
      value "TAG", "Tag", value: "tag"
      value "PUSH", "Push", value: "push"
      value "REPOSITORY", "repository", value: "repository"
    end
  end
end
