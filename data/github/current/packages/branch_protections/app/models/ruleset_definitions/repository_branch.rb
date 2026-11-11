# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class RepositoryBranch < RulesetDefinition
    include TargetBranch
    include SourceRepository
  end
end
