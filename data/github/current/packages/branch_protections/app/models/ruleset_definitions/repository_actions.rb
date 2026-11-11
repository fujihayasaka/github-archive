# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class RepositoryActions < RulesetDefinition
    include TargetActions
    include SourceRepository
  end
end
