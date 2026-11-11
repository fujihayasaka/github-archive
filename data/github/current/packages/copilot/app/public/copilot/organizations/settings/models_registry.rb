# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Settings
      module ModelsRegistry
        extend T::Helpers
        include Copilot::Organizations::Signatures

        abstract!

        include HasConfiguration

        sig { params(model_key: String).returns(String) }
        def model_policy(model_key)
          organization = Copilot::Organization.new(organization_object)
          models = Copilot::ModelsRegistryCache.for_organization(organization)
          model = models.find { |m| m.model_key == model_key }

          return "unconfigured" unless model.present?

          # Ideally, this method would just use CopilotDomain.domain.settings.get_effective_value
          # However, the registry model's "get value" here works differently than the built-in models
          # This actually "evaluates" inheritance differently (it evaluates the copilot_unconfigured_is_inherited FF's change in behavior)
          # Built-in models would return the org's configuration value even if a business is unconfigured wheras this would not
          if model_policy_inherited?(model_key)
            inherited_enabled = if organization.feature_flag_enabled_include_parents?(:use_setting_rules_copilot_models, default: false)
              CopilotDomain.domain.settings.get_inherited_value(organization, Copilot::Settings::CopilotModelSetting,
                "copilot.models.supported_models.#{model_key}").serialize == "enabled"
            else
              T.must(copilot_business).model_enabled?(model_key)
            end
            return "enabled" if inherited_enabled
            return "disabled"
          end

          configuration.model_policy(model_key)
        end

        sig { params(model_key: String).returns(T::Boolean) }
        def model_policy_inherited?(model_key)
          return false unless copilot_business
          org = Copilot::Organization.new(organization_object)
          if org.feature_flag_enabled_include_parents?(:use_setting_rules_copilot_models, default: false)
            inherited = CopilotDomain.domain.settings.get_inherited_value(org, Copilot::Settings::CopilotModelSetting,
              "copilot.models.supported_models.#{model_key}").serialize
            return inherited != "no_policy" if organization_object.feature_flag_enabled?(:copilot_unconfigured_is_inherited, default: false)
            inherited == "enabled" || inherited == "disabled"
          else
            return !T.must(copilot_business).model_no_policy?(model_key) if organization_object.feature_flag_enabled?(:copilot_unconfigured_is_inherited, default: false)
            T.must(copilot_business).model_enabled?(model_key) || T.must(copilot_business).model_disabled?(model_key)
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
        def model_unconfigured?(model_key)
          model_policy(model_key) == "unconfigured"
        end

        sig { params(model_key: String).void }
        def model_enabled!(model_key)
          update_model_configuration!(model_key, "enabled")
        end

        sig { params(model_key: String).void }
        def model_disabled!(model_key)
          update_model_configuration!(model_key, "disabled")
        end

        sig { params(model_key: String, value: String, force: T::Boolean).void }
        def update_model_configuration!(model_key, value, force: false)
          return if model_policy_inherited?(model_key) && !force
          return unless %w[enabled disabled].include?(value) # no_policy and unconfigured are invalid for orgs regardless of force
          organization = Copilot::Organization.new(organization_object)
          models = Copilot::ModelsRegistryCache.for_organization(organization)
          model = models.find { |m| m.model_key == model_key }
          return unless model.present?

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.set_model_policy(model_key, value)
          end

          Copilot::BatchUpdateUserSettingsJob.perform_later(organization_object.id)

          GitHub.dogstats.increment(
            "copilot.settings.#{model_key}_#{value}",
            tags: ["type:organization"],
          )
        end
      end
    end
  end
end
