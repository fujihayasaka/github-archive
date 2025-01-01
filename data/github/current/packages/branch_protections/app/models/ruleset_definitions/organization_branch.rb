# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationBranch < RulesetDefinition
    include TargetBranch
    include SourceOrganization
  end
end
