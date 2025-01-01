# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  class OrganizationPush < RulesetDefinition
    include TargetPush
    include SourceOrganization

    sig { params(targets: T.nilable(T::Array[String])).returns(T::Boolean) }
    def applies_to_targets?(targets)
      super && ruleset_feature_enabled?
    end

    sig { params(ruleset: RepositoryRuleset, object: T.untyped).returns(T::Boolean) }
    def applies_to_source?(ruleset, object)
      if super
        object.is_a?(Organization) ||
        RulesetDefinitions::RulesetDefinition.factory(object, "Repository", "push").is_valid?
      else
        false
      end
    end

    sig { returns(T::Boolean) }
    def ruleset_feature_enabled?
      @source.push_rulesets_enabled?
    end

    sig { returns(T::Boolean) }
    def supports_delegated_bypass?
      @source.delegated_bypass_enabled?
    end
  end
end
