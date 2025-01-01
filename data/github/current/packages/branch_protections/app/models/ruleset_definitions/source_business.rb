# typed: true
# frozen_string_literal: true

module RulesetDefinitions
  module SourceBusiness
    extend T::Sig

    sig { returns(Business) }
    def business
      @source
    end

    sig { returns(String) }
    def display_type
      "Enterprise"
    end

    sig { returns(T::Array[String]) }
    def source_required_condition_targets
      # enterprise rules require a organization and whatever the ruleset target requires
      %w(organization repository)
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
      context = if object.is_a?(Repository)
        RuleEngine::Conditions::RulesetTargetContext.new(repository: object)
      else
        RuleEngine::Conditions::RulesetTargetContext.new(organization: object)
      end
      ruleset.satisfies_conditions?(context, "organization")
    end
  end
end
