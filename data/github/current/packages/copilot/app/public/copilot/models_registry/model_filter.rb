# typed: strict
# frozen_string_literal: true

module Copilot
  module ModelsRegistry
    class ModelFilter
      include GitHub::Memoizer

      sig { returns(Copilot::Types::CopilotEntity) }
      attr_reader :copilot_entity

      sig { returns(String) }
      attr_reader :plan

      sig { returns(T::Array[ModelsRegistryCache]) }
      attr_reader :all_models

      sig { params(copilot_entity: Copilot::Types::CopilotEntity, plan: String, all_models: T.nilable(T::Array[ModelsRegistryCache])).void }
      def initialize(copilot_entity, plan, all_models: nil)
        @copilot_entity = copilot_entity
        @plan = plan
        @all_models = T.let(all_models || Copilot::ModelsRegistryCache.all_cached, T::Array[ModelsRegistryCache])
      end

      sig { returns(T::Array[ModelsRegistryCache]) }
      def call
        return [] unless plan.present?

        preload_flags
        filtered_models
      end

      private

      sig { void }
      def preload_flags
        flags_to_preload = []
        all_models.each do |model|
          flags_to_preload << model.feature_flag if model.feature_flag.present?
          flags_to_preload << model.policy_pro_feature_flag if model.policy_pro_feature_flag.present?
        end
        flags_to_preload << :copilot_registry_internal_models_testing
        flags_to_preload.uniq!

        FeatureFlag.vexi.preload(flags_to_preload, instrumentation_properties: {
          "code.namespace": self.class.name&.underscore
        })
      end

      sig { returns(T::Array[ModelsRegistryCache]) }
      def filtered_models
        all_models
          .select { |model| model_eligible?(model) }
          .sort_by(&:name)
      end

      sig { params(model: ModelsRegistryCache).returns(T::Boolean) }
      def model_eligible?(model)
        return false unless feature_flag_enabled?(model.feature_flag, copilot_entity)
        return false unless model.plans.include?(plan)
        return false unless internal_model_visible?(model)
        return false unless policy_pro_flag_satisfied?(model)

        true
      end

      sig { params(model: ModelsRegistryCache).returns(T::Boolean) }
      def internal_model_visible?(model)
        !model.internal || show_internal_models?
      end

      # For Users and Orgs on 'pro' or 'business' plans, the model's policy_pro_feature_flag must be enabled.
      # Businesses are exempt from this check.
      sig { params(model: ModelsRegistryCache).returns(T::Boolean) }
      def policy_pro_flag_satisfied?(model)
        return true unless %w[pro business].include?(plan)
        return true if copilot_entity.is_a?(Copilot::Business)

        feature_flag_enabled?(model.policy_pro_feature_flag, copilot_entity)
      end

      sig { returns(T::Boolean) }
      memoize def show_internal_models?
        copilot_entity.feature_flag_enabled?(:copilot_registry_internal_models_testing, default: false)
      end

      sig { params(flag: T.any(String, Symbol, NilClass), copilot_entity: T.any(Copilot::Business, Copilot::Organization, Copilot::User)).returns(T::Boolean) }
      def feature_flag_enabled?(flag, copilot_entity)
        return true if flag.to_s.empty?
        copilot_entity.feature_flag_enabled?(flag.to_s.to_sym, default: false)
      end
    end
  end
end
