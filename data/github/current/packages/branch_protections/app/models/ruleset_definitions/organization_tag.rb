# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationTag < RulesetDefinition
    include TargetBranch
    include SourceOrganization
  end
end
