# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationPush < RulesetDefinition
    include TargetPush
    include SourceOrganization

    sig { params(ruleset: RepositoryRuleset, object: T.untyped).returns(T::Boolean) }
    def applies_to_source?(ruleset, object)
      if super
        object.is_a?(Organization) ||
        RulesetDefinitions::RulesetDefinition.factory(object, "Repository", "push").is_valid?
      else
        false
      end
    end
  end
end
