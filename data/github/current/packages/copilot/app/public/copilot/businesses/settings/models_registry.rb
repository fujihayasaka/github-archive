# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Settings
      module ModelsRegistry
        extend T::Helpers
        include Copilot::Businesses::Signatures
        include HasConfiguration

        abstract!

        sig { params(model_key: String).returns(String) }
        def model_policy(model_key)
          business = Copilot::Business.new(business_object)
          models = Copilot::ModelsRegistryCache.for_enterprise(business)
          model = models.find { |m| m.model_key == model_key }

          return "unconfigured" unless model.present?

          if business.feature_flag_enabled_include_parents?(:use_setting_rules_copilot_models, default: false)
            CopilotDomain.domain.settings.get_effective_value(business, Copilot::Settings::CopilotModelSetting,
              "copilot.models.supported_models.#{model_key}").serialize
          else
            configuration.model_policy(model_key)
          end
        end

        sig { params(model_key: String).returns(T::Boolean) }
        def model_enabled?(model_key)
          model_policy(model_key) == "enabled"
        end

        sig { params(model_key: String).returns(T::Boolean) }
        def model_disabled?(model_key)
          model_policy(model_key) == "disabled"
        end

        sig { params(model_key: String).returns(T::Boolean) }
        def model_no_policy?(model_key)
          model_policy(model_key) == "no_policy"
        end

        sig { params(model_key: String).returns(T::Boolean) }
        def model_unconfigured?(model_key)
          model_policy(model_key) == "unconfigured"
        end

        # Batch-loads settings for all registry models in a single call to avoid
        # the N+1 that would result from calling model_enabled? per model.
        sig { returns(Integer) }
        def enabled_registry_models_count
          business = Copilot::Business.new(business_object)
          registry_models = Copilot::ModelsRegistryCache.for_enterprise(business)
          return 0 unless registry_models.any?

          setting_names = registry_models.map { |m| "copilot.models.supported_models.#{m.model_key}" }
          loaded_settings = CopilotDomain.domain.settings.load_settings([business], setting_names)
          loaded_settings.count { |s| s.value == "enabled" }
        end

        sig { params(model_key: String).void }
        def model_enabled!(model_key)
          update_model_configuration!(model_key, "enabled")
        end

        sig { params(model_key: String).void }
        def model_disabled!(model_key)
          update_model_configuration!(model_key, "disabled")
        end

        sig { params(model_key: String).void }
        def model_no_policy!(model_key)
          update_model_configuration!(model_key, "no_policy")
        end

        private

        sig { params(model_key: String, value: String).void }
        def update_model_configuration!(model_key, value)
          return unless %w[enabled disabled no_policy].include?(value)
          business = Copilot::Business.new(business_object)
          return if value == "no_policy" && business.is_standalone_business?

          models = Copilot::ModelsRegistryCache.for_enterprise(business)
          model = models.find { |m| m.model_key == model_key }
          return unless model.present?

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.set_model_policy(model_key, value)
          end

          GitHub.dogstats.increment(
            "copilot.settings.#{model_key}_#{value}",
            tags: ["type:business"],
          )

          propagate_organization_settings!
          Copilot::BatchUpdateEnterpriseUserSettingsJob.perform_later(business_object)
        end
      end
    end
  end
end
