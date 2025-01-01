# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryRulesetBypassActorBypassMode < Platform::Enums::Base
      description "The bypass mode for a specific actor on a ruleset."

      # TODO: Change numbers to strings when the enum is added to the RepositoryRulesetBypassActor AR object
      value "ALWAYS", "The actor can always bypass rules", value: 0
      value "PULL_REQUEST", "The actor can only bypass rules via a pull request", value: 1
    end
  end
end
