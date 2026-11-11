# typed: strict
# frozen_string_literal: true

module RuleEngine
  module RuleConditionBase
    extend T::Helpers
    extend ActiveSupport::Concern
    include IRuleCondition

    requires_ancestor { ActiveRecord::Base }

    abstract!

    included do
      T.bind(self, T.all(ClassMethods, T.class_of(ApplicationRecord::Base)))

      belongs_to impl_payload.ruleset_association_name.to_sym, class_name: impl_payload.ruleset_class
      validates impl_payload.ruleset_association_name.to_sym, presence: true

      before_validation :transform_parameters

      validate :ensure_valid_configuration
      after_initialize :transform_parameters
    end

    sig { abstract.returns(T.nilable(RulesetBase)) }
    def ruleset; end

    sig { override.returns(T.nilable(RuleEngine::Conditions::ConditionTarget::TargetObject)) }
    def target_object
      target_evaluator&.target_object
    end

    sig { returns(T::Boolean) }
    def supports_source?
      IRuleCondition.supports_source?(self, T.must(ruleset).source)
    end

    sig { returns(T::Boolean) }
    def supports_ruleset_target?
      IRuleCondition.supports_ruleset_target?(self, T.must(ruleset).target)
    end

    sig { override.returns(T.nilable(RuleEngine::Conditions::ConditionTarget)) }
    def target_evaluator
      RuleEngine::Conditions::Evaluator::TARGET_TYPES[target]
    end

    # Returns parameters with invalid object references (Node IDs) removed
    sig { returns(T::Hash[String, T.untyped]) }
    def visible_parameters
      return parameters unless (impl = target_evaluator)

      visible_params = parameters.deep_dup
      schema = impl.parameter_schema
      ParameterSchema::Object.batch_delete_invalid_node_ids({ schema => visible_params })
      visible_params
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def parameter_errors
      root = {
        "ruleset_id": T.must(ruleset).id,
        "ruleset_source": T.must(ruleset).source,
        "ruleset_target": T.must(ruleset).target,
      }.with_indifferent_access.freeze

      target_evaluator&.validate_parameterized(self, root: root) || []
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def event_payload
      {
        id: id,
        target: target,
        parameters: parameters
      }
    end

    AUDITABLE_FIELDS = %i[target parameters].freeze

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

    private

    sig { void }
    def transform_parameters
      return unless T.unsafe(parameters)
      return unless (schema = target_evaluator&.parameter_schema)

      target_evaluator&.transform_parameters!(parameters)
      schema.apply_defaults_for_source(nil, parameters, on_load: true)
    end

    sig { void }
    def ensure_valid_configuration
      impl = target_evaluator
      if impl.nil? || ruleset&.source_type.nil?
        errors.add(:target, "is not supported")
      elsif !supports_source?
        errors.add(:target, "#{target} is not supported for #{ruleset&.display_source_type} rulesets")
      elsif !supports_ruleset_target?
        errors.add(:target, "#{target} is not supported for #{ruleset&.target} rulesets")
      elsif (param_errors = parameter_errors).any?
        errors.add(:parameters, "are invalid for this target: #{param_errors.map { |e| e[:message] }.join(', ')}")
      end
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
