# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Settings
      module ModelsRegistry
        extend T::Helpers
        include Copilot::Users::Signatures
        include Copilot::Users::Settings::Policies
        include GitHub::Memoizer

        abstract!

        include HasConfiguration

        sig { override.returns(T::Array[ModelsRegistryCache]) }
        memoize def registry_models
          Copilot::ModelsRegistryCache.for_user(copilot_user_object)
        end

        sig { params(model_key: String).returns(String) }
        def model_policy(model_key)
          model = registry_models.find { |m| m.model_key == model_key }

          return "unconfigured" unless model.present?

          # Check for limited access users (e.g., Copilot Free)
          return "enabled" if has_limited_access? && !model.inline_approval_enabled?

          if has_cfb_access?
            if CopilotDomain.domain.settings.definition_by_name("copilot.models.supported_models.#{model_key}").present?
              result = CopilotDomain.domain.settings.get_effective_value(copilot_user_object, Copilot::Settings::CopilotModelSetting, "copilot.models.supported_models.#{model_key}")
              case result
              when Copilot::Settings::CopilotModelSetting::Value::NO_POLICY
                fallback_policy = registry_model_ea_user_fallback_policy(model_key, copilot_user_object)
                return fallback_policy if fallback_policy
                return "disabled"
              when Copilot::Settings::CopilotModelSetting::Value::UNCONFIGURED
                return "disabled"
              else
                return result.serialize
              end
            else
              # Most restrictive at enterprise level - if any business disables, user gets disabled
              return "disabled" if copilot_businesses.any? { |b| b.model_disabled?(model_key) }
              # If any business explicitly enables it, user gets enabled (unconfigured businesses are ignored)
              return "enabled" if copilot_businesses.any? { |b| b.model_enabled?(model_key) }
              # Least restrictive at org level - if any org enables, user gets enabled
              if copilot_user_object.feature_flag_enabled_include_parents?(:copilot_unconfigured_is_inherited, default: false) && copilot_user_object.feature_flag_enabled_include_parents?(:copilot_unconfigured_is_inherited_evaluate, default: false)
                # Unconfigured is inherited from business to org. Ignore enabled orgs with unconfigured businesses.
                return "enabled" if copilot_organizations.any? { |org| org.model_enabled?(model_key) && !org.copilot_business&.model_unconfigured?(model_key) }
              else
                return "enabled" if copilot_organizations.any? { |org| org.model_enabled?(model_key) }
              end
              # EA user fallback: if user is enterprise-assigned and business has no_policy,
              # check the ea_user_fallback_policy setting
              fallback_policy = registry_model_ea_user_fallback_policy(model_key, copilot_user_object)
              return fallback_policy if fallback_policy
              # If no businesses or orgs enable it, user gets disabled
              return "disabled"
            end
          end

          # Check for users with individual licenses (CFI)
          if has_cfi_access? || has_limited_access?
            # Check if model is available in their plan
            if registry_models.any? { |m| m.model_key == model_key }
              return "enabled"
            end
          end

          # Model not available for this user or no access
          "unconfigured"
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

        sig { params(model_key: String, copilot_user_object: Copilot::User).returns(T.nilable(String)) }
        def registry_model_ea_user_fallback_policy(model_key, copilot_user_object)
          return nil unless copilot_user_object.is_enterprise_assigned_user?

          provider = T.cast(copilot_user_object.copilot_seat_provider, Copilot::Business)
          return nil unless provider.model_no_policy?(model_key)

          Copilot::Policies::EaUserFallback.value(provider)
        end

        sig { params(model_key: String, value: String).void }
        def update_model_configuration!(model_key, value)
          return unless %w[enabled disabled].include?(value)
          model = registry_models.find { |m| m.model_key == model_key }
          return unless model.present?

          ActiveRecord::Base.connected_to(role: :writing) do
            configuration.set_model_policy(model_key, value)
          end

          GitHub.dogstats.increment(
            "copilot.settings.#{model_key}_#{value}",
            tags: ["type:user"],
          )
        end
      end
    end
  end
end
