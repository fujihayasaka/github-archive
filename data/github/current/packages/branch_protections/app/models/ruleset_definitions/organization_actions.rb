# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationActions < RulesetDefinition
    include TargetActions
    include SourceOrganization
  end
end
