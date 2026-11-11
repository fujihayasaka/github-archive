# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class RepositoryTag < RulesetDefinition
    include TargetTag
    include SourceRepository
  end
end
