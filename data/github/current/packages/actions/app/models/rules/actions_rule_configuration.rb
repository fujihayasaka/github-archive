# typed: true
# frozen_string_literal: true

module Rules
  class ActionsRuleConfiguration < ApplicationRecord::ActionsEnvironments
    include RuleEngine::IRuleConfig

    self.table_name = "actions_rule_configurations"

    sig { returns(RuleEngine::RulesetImplementationPayload) }
    def self.impl_payload
      ActionsRuleset.impl_payload
    end
    include RuleEngine::RuleConfigurationBase

    before_validation :transform_parameters
    validate :ensure_valid_configuration

    validates :rule_type, presence: true, length: { maximum: 100 }, uniqueness: { scope: [:actions_ruleset],
      message: ->(object, _data) {
        "'#{object.rule_type}' is already used for this ruleset. Only one instance of this type is allowed per ruleset."
      }
    }

    after_initialize :initialize_parameters
    after_initialize :transform_parameters
    before_save :normalize_parameters
    after_save :initialize_parameters
    after_destroy :initialize_parameters

    sig { override.returns(T.nilable(T::Array[RuleEngine::RuleEvent::EventAction])) }
    attr_accessor :matching_event_actions
    sig { override.returns(T.nilable(T::Array[String])) }
    attr_accessor :matching_ref_names

    sig { override.returns(RuleEngine::RuleProvider) }
    def provider
      actions_ruleset&.rule_provider || T.must(RuleEngine::Evaluator::RULE_PROVIDERS.find { |rp| rp.identifier == "ref_ruleset" })
    end

    sig { override.returns(String) }
    def provider_name
      provider.identifier
    end

    sig { override.returns(T.nilable(Integer)) }
    def provider_id
      actions_ruleset_id
    end

    sig { override.returns(T.nilable(Integer)) }
    def history_id
      actions_ruleset&.latest_history_id
    end

    sig { override.params(parameter_name: String).returns(T.untyped) }
    def param(parameter_name)
      parameters[parameter_name]
    end

    sig { override.params(parameter_name: String).returns(T::Boolean) }
    def has_param(parameter_name) # rubocop:disable Naming/PredicatePrefix
      parameters.has_key?(parameter_name)
    end

    def visible_parameters
      ruleset_source = actions_ruleset&.source
      return {} unless ruleset_source

      rule_impl = evaluator
      return {} unless rule_impl

      parameter_schema = rule_impl.parameter_schema_for_source(ruleset_source)

      visible_parameters_for_schema(parameters, parameter_schema.fields)
    end

    def visible_parameters_for_schema(parameters, schema_fields)
      visible_params = {}

      schema_fields.each do |field|
        key = field.name
        next unless parameters.key?(key)

        if field.respond_to?(:content_object) && !field.content_object.nil? && parameters[key].is_a?(Enumerable)
          visible_params[key] = parameters[key].map do |child_params|
            child_fields = field.content_object.fields
            visible_parameters_for_schema(child_params, child_fields)
          end
        else
          visible_params[key] = parameters[key]
        end
      end

      visible_params
    end

    sig { override.returns(T::Boolean) }
    def enabled?
      actions_ruleset&.enabled? || false
    end

    sig { override.returns(T::Boolean) }
    def evaluate_mode?
      actions_ruleset&.evaluate? || false
    end

    sig { override.returns(T.untyped) }
    def source
      actions_ruleset&.source
    end

    def ruleset_ui_metadata
      evaluator&.ruleset_ui_metadata(self)
    end

    def parameter_errors
      impl = evaluator
      return [] unless impl

      root = {
        "ruleset_id": actions_ruleset_id,
        "ruleset_source": T.must(actions_ruleset).source,
        "ruleset_target": T.must(actions_ruleset).target,
      }.with_indifferent_access.freeze

      impl.validate_parameterized(self, root: root)
    end

    def recognized_parameters
      return {} unless parameters
      return parameters unless (schema = evaluator&.parameter_schema)

      allowed_keys = schema.fields.map(&:name)
      parameters.select { |key, _value| allowed_keys.include?(key) }
    end

    private

    def transform_parameters
      return unless rule_type && parameters
      return unless (schema = evaluator&.parameter_schema)

      evaluator&.transform_parameters!(parameters)
      schema.apply_defaults_for_source(nil, parameters, on_load: true)
    end

    def ensure_valid_configuration
      impl = evaluator
      if impl.nil?
        errors.add(:rule_type, "does not have a registered rule implementation.")
      elsif !impl.is_feature_enabled?(actions_ruleset&.source) || !impl.is_user_configurable?(actions_ruleset&.source)
        errors.add(:rule_type, "is not supported by this ruleset.")
      elsif !impl.is_supported_by_source_type?(actions_ruleset&.source)
        errors.add(:source, "is invalid for this rule type.")
      elsif !impl.is_supported_by_target?(actions_ruleset&.target)
        errors.add(:rule_type, "#{rule_type} is not supported on rulesets that target #{actions_ruleset&.target&.pluralize}.")
      elsif !impl.is_supported_by_plan?(actions_ruleset&.source, allow_upsell: true)
        errors.add(:rule_type, "#{rule_type} is not supported on this plan. Please upgrade to enable this rule type.")
      else
        param_errors = parameter_errors
        if param_errors.any?
          errors.add(:parameters, "is invalid for this rule type: #{param_errors.map { |e| e[:message] }.join(', ')}")
        end
      end
    end

    def initialize_parameters
      self.parameters = {} if self.parameters.nil?
    end

    def normalize_parameters
      self.parameters = nil if self.parameters.nil? || self.parameters.empty?
    end
  end
end
