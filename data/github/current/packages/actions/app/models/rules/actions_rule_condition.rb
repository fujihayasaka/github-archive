# typed: true
# frozen_string_literal: true

module Rules
  class ActionsRuleCondition < ApplicationRecord::ActionsEnvironments
    include RuleEngine::Timing
    include RuleEngine::IRuleCondition

    self.table_name = "actions_rule_conditions"

    sig { returns(RuleEngine::RulesetImplementationPayload) }
    def self.impl_payload
      ActionsRuleset.impl_payload
    end
    include RuleEngine::RuleConditionBase

    before_validation :transform_parameters

    validates :target, uniqueness: { scope: [:actions_ruleset],
      message: ->(object, _data) {
        "'#{object.target}' is already used for this ruleset. Only one instance of this target is allowed per ruleset."
      }
    }

    enum :target, { repository_name: 1, repository_id: 2, repository_property: 3, organization_name: 4, organization_id: 5, organization_property: 6 }

    validate :ensure_valid_configuration
    after_initialize :transform_parameters

    sig { override.returns(T.nilable(RuleEngine::IRuleset)) }
    def ruleset
      actions_ruleset
    end

    sig { override.returns(T.nilable(RuleEngine::Conditions::ConditionTarget::TargetObject)) }
    def target_object
      target_evaluator&.target_object
    end

    sig { returns(T::Boolean) }
    def supports_source?
      ActionsRuleCondition.supports_source?(self, T.must(actions_ruleset).source)
    end

    sig { returns(T::Boolean) }
    def supports_ruleset_target?
      ActionsRuleCondition.supports_ruleset_target?(self, T.must(actions_ruleset).target)
    end

    sig { override.returns(T.nilable(RuleEngine::Conditions::ConditionTarget)) }
    def target_evaluator
      RuleEngine::Conditions::Evaluator::TARGET_TYPES[target]
    end

    sig do
      params(
        condition: ActionsRuleCondition,
        source: RuleEngine::Types::RuleSource
      ).returns(T::Boolean)
    end
    def self.supports_source?(condition, source)
      !!condition.target_evaluator&.supported_sources&.include?(source.class.name&.downcase&.to_sym)
    end

    sig do
      params(
        condition: ActionsRuleCondition,
        target: String
      ).returns(T::Boolean)
    end
    def self.supports_ruleset_target?(condition, target)
      !!condition.target_evaluator&.supported_ruleset_targets&.include?(target.to_sym)
    end

    def parameter_errors
      root = {
        "ruleset_id": actions_ruleset_id,
        "ruleset_source": T.must(actions_ruleset).source,
        "ruleset_target": T.must(actions_ruleset).target,
      }.with_indifferent_access.freeze

      target_evaluator&.validate_parameterized(self, root: root)
    end

    def event_payload
      {
        id: id,
        target: target,
        parameters: parameters
      }
    end

    private

    def transform_parameters
      return unless parameters
      return unless (schema = target_evaluator&.parameter_schema)

      target_evaluator&.transform_parameters!(parameters)
      schema.apply_defaults_for_source(nil, parameters, on_load: true)
    end

    def ensure_valid_configuration
      impl = target_evaluator
      if impl.nil? || actions_ruleset&.source_type.nil?
        errors.add(:target, "is not supported")
      elsif !supports_source?
        errors.add(:target, "#{target} is not supported for #{actions_ruleset&.display_source_type} rulesets")
      elsif !supports_ruleset_target?
        errors.add(:target, "#{target} is not supported for #{actions_ruleset&.target} rulesets")
      elsif parameter_errors.any?
        errors.add(:parameters, "are invalid for this target: #{parameter_errors.map { |e| e[:message] }.join(', ')}")
      end
    end
  end
end
