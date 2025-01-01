# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module SourceBusiness

    sig { returns(Business) }
    def business
      @source
    end

    sig { returns(String) }
    def display_type
      "Enterprise"
    end

    sig { returns(String) }
    def display_source_name
      @source.slug
    end

    sig { returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
    def source_required_condition_targets
      # enterprise rules require a organization and whatever the ruleset target requires
      [RuleEngine::Conditions::ConditionTarget::TargetObject::Organization, RuleEngine::Conditions::ConditionTarget::TargetObject::Repository]
    end

    sig { returns(T::Boolean) }
    def supports_evaluate_mode?
      # all enterprise rulesets support evaluate mode
      true
    end

    sig { returns(T::Array[String]) }
    def validation_errors
      []
    end

    sig { returns(T::Boolean) }
    def is_valid_for_source?
      business.plan_supports?(:enterprise_rulesets)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def event_payload
      {
        ruleset_source_type: display_type,
        business: business
      }
    end

    sig { params(ruleset_id: Integer).returns(String) }
    def url(ruleset_id)
      ""
    end

    sig { params(ruleset: RepositoryRuleset, object: T.untyped).returns(T::Boolean) }
    def applies_to_source?(ruleset, object)
      return true if object == business
      return false unless is_valid_for_source?
      return false unless object.is_a?(Repository) || object.is_a?(Organization)

      if object.is_a?(Repository)
        target = RuleEngine::Conditions::Targets::Repository.new(repository: object)
        return ruleset.satisfies_conditions?(target, RuleEngine::Conditions::ConditionTarget::TargetObject::Repository) &&
          ruleset.satisfies_conditions?(target, RuleEngine::Conditions::ConditionTarget::TargetObject::Organization)
      end

      target = RuleEngine::Conditions::Targets::Organization.new(organization: object)
      ruleset.satisfies_conditions?(target, RuleEngine::Conditions::ConditionTarget::TargetObject::Organization)
    end

    sig { params(targetable: RuleEngine::Conditions::Targetable).returns(T::Boolean) }
    def source_supports_targetable?(targetable)
      targetable.get_attribute(RuleEngine::Conditions::Targetable::Attribute::Enterprise) == business
    end
  end
end
