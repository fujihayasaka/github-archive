# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationTag < RulesetDefinition
    include TargetTag
    include SourceOrganization
  end
end
