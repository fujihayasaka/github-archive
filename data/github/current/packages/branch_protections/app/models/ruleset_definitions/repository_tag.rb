# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class RepositoryTag < RulesetDefinition
    include TargetBranch
    include SourceRepository
  end
end
