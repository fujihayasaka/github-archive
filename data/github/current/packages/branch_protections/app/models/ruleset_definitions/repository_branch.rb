# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class RepositoryBranch < RulesetDefinition
    extend T::Sig
    include TargetBranch
    include SourceRepository
  end
end
