# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationTag < RulesetDefinition
    extend T::Sig
    include TargetBranch
    include SourceOrganization
  end
end
