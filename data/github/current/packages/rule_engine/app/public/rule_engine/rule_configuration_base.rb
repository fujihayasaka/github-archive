# typed: strict
# frozen_string_literal: true

module RuleEngine
  module RuleConfigurationBase
    extend T::Helpers
    extend ActiveSupport::Concern
    include RuleEngine::IRuleConfig

    requires_ancestor { ActiveRecord::Base }

    abstract!

    included do
      T.bind(self, T.all(ClassMethods, T.class_of(ApplicationRecord::Base)))

      belongs_to impl_payload.ruleset_association_name.to_sym, class_name: impl_payload.ruleset_class, inverse_of: :rule_configurations
      validates impl_payload.ruleset_association_name.to_sym, presence: true

      validate :ensure_valid_configuration

      after_initialize :initialize_parameters
      after_initialize :transform_parameters
      before_save :normalize_parameters
      after_save :initialize_parameters
      after_destroy :initialize_parameters

      before_validation :transform_parameters
    end

    sig { override.returns(T.nilable(T::Array[RuleEngine::RuleEvent::EventAction])) }
    attr_accessor :matching_event_actions
    sig { override.returns(T.nilable(T::Array[String])) }
    attr_accessor :matching_ref_names

    sig { abstract.returns(T.nilable(RuleEngine::RulesetBase)) }
    def ruleset; end

    sig { abstract.returns(T.nilable(Integer)) }
    def ruleset_id; end

    sig { abstract.params(parameters: T.nilable(T::Hash[String, T.untyped])).void }
    def parameters=(parameters); end

    sig { abstract.returns(DomainAccessorBase[T.untyped]) }
    def domain; end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def event_payload
      {
        id: id,
        type: rule_type,
        parameters: parameters
      }
    end

    AUDITABLE_FIELDS = %i[rule_type parameters].freeze

    sig { params(save: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
    def changes_payload(save: true)
      {}.tap do |changes|
        AUDITABLE_FIELDS.each do |field|
          if save
            changes["old_#{field}".to_sym] = attribute_before_last_save(field) if saved_change_to_attribute?(field)
          else
            changes["old_#{field}".to_sym] = attribute_change_to_be_saved(field) if will_save_change_to_attribute?(field)
          end
        end
      end
    end

    sig { override.returns(RuleEngine::RuleProvider) }
    def provider
      T.must(ruleset&.rule_provider)
    end

    sig { override.returns(String) }
    def provider_name
      provider.identifier
    end

    sig { override.returns(T.nilable(Integer)) }
    def provider_id
      ruleset_id
    end

    sig { override.returns(T.nilable(Integer)) }
    def history_id
      ruleset&.latest_history_id
    end

    sig { override.params(parameter_name: String).returns(T.untyped) }
    def param(parameter_name)
      parameters[parameter_name]
    end

    sig { override.params(parameter_name: String).returns(T::Boolean) }
    def has_param(parameter_name) # rubocop:disable Naming/PredicatePrefix
      parameters.has_key?(parameter_name)
    end

    # Filters parameters visible to a specific source
    # Also filters out invalid object references (Node IDs)
    sig { returns(T::Hash[String, T.untyped]) }
    def visible_parameters
      ruleset_source = ruleset&.source
      return {} unless ruleset_source

      rule_impl = evaluator
      return {} unless rule_impl

      visible_params = parameters.deep_dup
      schema = rule_impl.parameter_schema
      ParameterSchema::Object.batch_delete_invalid_node_ids({ schema => visible_params })

      parameter_schema = rule_impl.parameter_schema_for_source(ruleset_source)

      visible_parameters_for_schema(visible_params, parameter_schema.fields)
    end

    sig { params(parameters: T::Hash[String, T.untyped], schema_fields: T::Array[RuleEngine::ParameterSchema::Base]).returns(T::Hash[String, T.untyped]) }
    def visible_parameters_for_schema(parameters, schema_fields)
      visible_params = {}

      schema_fields.each do |field|
        key = field.name
        next unless parameters.key?(key)

        if field.is_a?(RuleEngine::ParameterSchema::Array) && !field.content_object.nil? && parameters[key].is_a?(Enumerable)
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
      ruleset&.enabled? || false
    end

    sig { override.returns(T::Boolean) }
    def evaluate_mode?
      ruleset&.evaluate? || false
    end

    sig { override.returns(T.untyped) }
    def source
      ruleset&.source
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def recognized_parameters
      return {} unless T.unsafe(parameters)
      return parameters unless (schema = evaluator&.parameter_schema)

      allowed_keys = schema.fields.map(&:name)
      parameters.select { |key, _value| allowed_keys.include?(key) }
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def parameter_errors
      impl = evaluator
      return [] unless impl

      # TODO: repository_ruleset should be non-nil but the database currently allows it to be nil
      root = {
        "ruleset_id": T.must(ruleset).id,
        "ruleset_source": T.must(ruleset).source,
        "ruleset_target": T.must(ruleset).target,
        "ruleset_ref_targets": T.must(ruleset).conditions.to_a.find { |c| c.target == "ref_name" }&.parameters&.dig("include"),
      }.with_indifferent_access.freeze

      impl.validate_parameterized(self, root: root)
    end

    sig { returns(T.nilable(RuleEngine::BaseRule)) }
    def evaluator
      domain.registry.rule_impl_for_rule_type(rule_type)
    end

    private

    sig { void }
    def ensure_valid_configuration
      impl = evaluator
      if impl.nil?
        errors.add(:rule_type, "does not have a registered rule implementation.")
      elsif !impl.is_feature_enabled?(ruleset&.source) || !impl.is_user_configurable?(ruleset&.source)
        errors.add(:rule_type, "is not supported by this ruleset.")
      elsif !impl.is_supported_by_source_type?(ruleset&.source)
        errors.add(:source, "is invalid for this rule type.")
      elsif !impl.is_supported_by_target?(ruleset&.target)
        errors.add(:rule_type, "#{rule_type} is not supported on rulesets that target #{ruleset&.target&.pluralize}.")
      elsif !impl.is_supported_by_plan?(ruleset&.source, allow_upsell: true)
        errors.add(:rule_type, "#{rule_type} is not supported on this plan. Please upgrade to enable this rule type.")
      else
        param_errors = parameter_errors
        if param_errors.any?
          errors.add(:parameters, "is invalid for this rule type: #{param_errors.map { |e| e[:message] }.join(', ')}")
        end
      end
    end

    sig { void }
    def transform_parameters
      return unless T.unsafe(rule_type) && parameters
      return unless (schema = evaluator&.parameter_schema)

      evaluator&.transform_parameters!(parameters)
      schema.apply_defaults_for_source(nil, parameters, on_load: true)
    end

    sig { void }
    def initialize_parameters
      self.parameters = {} if self.parameters.nil?
    end

    sig { void }
    def normalize_parameters
      self.parameters = nil if self.parameters.nil? || self.parameters.empty?
    end

    module ClassMethods
      include Kernel

      sig { returns(RulesetImplementationPayload) }
      def impl_payload
        raise NotImplementedError, "Subclass must implement class method `impl_payload`"
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
