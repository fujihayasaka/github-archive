# typed: strict
# frozen_string_literal: true

module Businesses
  module AiControls
    module Concerns
      module DefaultModels
        extend ActiveSupport::Concern
        extend T::Helpers

        include Businesses::Concerns::BusinessAccess

        # Data fetching

        sig { params(is_stafftools: T.nilable(T::Boolean)).returns(T::Hash[Symbol, T.untyped]) }
        def app_payload(is_stafftools: false)
          {
            canWrite: is_stafftools ? false : this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
            isAdmin: is_stafftools ? false : this_business&.adminable_by?(current_user) || false,
            isStafftools: is_stafftools,
            paths: {
              modelsPath: is_stafftools ? default_models_models_data_stafftools_copilot_path(this_business) : default_models_models_data_enterprise_ai_controls_enterprise_path(this_business),
              settingsPath: is_stafftools ? default_models_settings_data_stafftools_copilot_path(this_business) : default_models_settings_data_enterprise_ai_controls_enterprise_path(this_business),
              organizationsPath: is_stafftools ? default_models_organizations_data_stafftools_copilot_path(this_business) : default_models_organizations_data_enterprise_ai_controls_enterprise_path(this_business),
              defaultModelsPath: is_stafftools ? default_models_stafftools_copilot_path(this_business) : default_models_enterprise_ai_controls_enterprise_path(this_business),
              customModelsPath: enterprise_copilot_byok_custom_models_settings_path(this_business),
            }
          }
        end

        sig { returns(T::Array[Structs::CopilotModelResource]) }
        def organizations
          copilot_business.organizations.map do |org| Structs::CopilotModelResource.new(
              id: org.id,
              type: "Organization",
              name: org.display_login,
              primaryAvatarUrl: org.primary_avatar_url,
            )
          end
        end

        sig { returns(T::Array[Structs::CopilotModel]) }
        def models
          visible_models = ::Copilot::Policies::MODELS.filter { |model| model.viewable_by_business?(copilot_business) }
          serialized_models = visible_models.map do |model|
            next nil unless model.is_a?(::Copilot::Policies::Concerns::Model::Serializable)

            Structs::CopilotModel.new(
              name: model.config_name,
              displayName: model.display_name,
              publisher: model.publisher,
              category: model.category,
              isPreview: model.preview?(copilot_business),
            )
          end
          serialized_models = serialized_models.compact

          if copilot_business.feature_flag_enabled?(:copilot_model_registry_ui, default: false) && copilot_business.feature_flag_enabled?(:copilot_default_models_registry, default: false)
            ::Copilot::ModelsRegistryCache.for_enterprise(copilot_business).each do |model|
              serialized_models << Structs::CopilotModel.new(
                  name: model.model_key,
                  displayName: model.name,
                  publisher: nil,
                  category: nil,
                  isPreview: model.preview,
                )
            end
          end
          serialized_models
        end

        sig { returns(Structs::CopilotModelSetting) }
        def settings
          target = ::Copilot::Business.new(this_business)
          model_settings = [::Copilot::Settings::CopilotModelsGroup::NAME]
          model_settings.concat(::Copilot::Policies::MODELS.map { |m| "copilot.models.supported_models.#{m.config_name}" })
          model_settings.concat(::Copilot::ModelsRegistryCache.for_entity(target).map { |m| "copilot.models.supported_models.#{m.model_key}" })
          settings = CopilotDomain.domain.settings.load_settings([target], model_settings)

          configuration_settings = settings.filter { |s| s.provider_name == ::Copilot::Settings::CopilotModelsSettingProvider::NAME }
          rule_setting = settings.find { |s| s.provider_name == ::Copilot::Settings::CopilotSettingsDbProvider::NAME }

          combined_setting = translate_to_shared_setting(configuration_settings, rule_setting, target)
          setting_to_json(combined_setting)
        end

        # Translation helpers

        # Combines the setting with the "value" and the setting with the "rules" into a single setting
        # This is temporary to maintain compat with the UI which expects a single setting with both value and rules
        sig { params(value_settings: T::Array[SettingsCore::ISetting], rule_setting: T.nilable(SettingsCore::ISetting), target: Targeting::Targetable).returns(SettingsCore::ISetting) }
        def translate_to_shared_setting(value_settings, rule_setting, target)
          combined_configuration_value = value_settings.each_with_object({}) do |s, acc|
            acc[s.name.sub("copilot.models.supported_models.", "")] = s.value if s.name.start_with?("copilot.models.supported_models.")
          end
          SettingsCore::MemorySetting.new("copilot.models.supported_models", combined_configuration_value, target, "",
            rule_setting&.rules || [], id: rule_setting&.id)
        end

        sig { params(setting: SettingsCore::ISetting).returns(Structs::CopilotModelSetting) }
        def setting_to_json(setting)
          business = setting.targetable&.internal_record
          raise ArgumentError, "Setting targetable is not a Business" unless business.is_a?(Business)

          Structs::CopilotModelSetting.new(
            resource: Structs::CopilotModelResource.new(
              id: business.id,
              type: business.class.name || "Business",
              name: business.name,
              primaryAvatarUrl: business.primary_avatar_url
            ),
            id: setting.id,
            name: setting.name,
            value: setting.value,
            rules: setting.rules.map do |rule|
              Structs::CopilotModelRule.new(
                id: rule.id,
                ruleType: rule.rule_type,
                conditionExpression: Structs::CopilotModelConditionExpression.new(
                  id: rule.condition_expression.id,
                  targetableAttribute: rule.condition_expression.targetable_attribute,
                  operation: rule.condition_expression.operation,
                  value: rule.condition_expression.value,
                ),
                parameters: Structs::CopilotModelRuleParameter.new(
                  values: rule.parameters["values"],
                )
              )
            end
          )
        end

        # Methods from CopilotShared

        sig { returns(::Copilot::Business) }
        def copilot_business
          @copilot_business ||= T.let(::Copilot::Business.new(this_business), T.nilable(::Copilot::Business))
          @copilot_business
        end

        sig { returns(::Copilot::User) }
        def current_copilot_user
          @current_copilot_user ||= T.let(::Copilot::User.new(current_user), T.nilable(::Copilot::User))
          @current_copilot_user
        end

        sig { returns(String) }
        def get_features_for_data_retention
          return "" unless copilot_business.copilot_plan_business?

          features = []
          features << ::Copilot::COPILOT_IN_DOTCOM if copilot_business.has_copilot_enterprise_access? && !copilot_business.copilot_standalone?
          features << ::Copilot::COPILOT_CHAT_IN_MOBILE
          features << ::Copilot::COPILOT_SWE_AGENT if (!GitHub.multi_tenant_enterprise? || FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, this_business, default: false)) && !copilot_business.copilot_standalone?
          return "Enabling #{features.to_sentence} will collect additional data" if !features.empty?
          ""
        end

        sig { returns(T::Array[T.all(::Copilot::PolicyInterface, ::Copilot::Policies::Concerns::Mutable)]) }
        def available_models_for_business
          @available_models_for_business ||= T.let(
            ::Copilot::Policies::MODELS.select do |model|
              next false if model.config_name == "ofo" && !copilot_business.feature_flag_enabled?(:copilot_api_force_legacy_base_chat_model, default: false)
              next true unless model.respond_to?(:available_for?)

              model.available_for?(copilot_business)
            end,
            T.nilable(T::Array[T.all(::Copilot::PolicyInterface, ::Copilot::Policies::Concerns::Mutable)])
          )
        end

        # Hooks

        sig { void }
        def ensure_copilot_enabled
          render_404 unless copilot_business.copilot_enabled?
        end

        # New FGP check for React endpoints
        sig { void }
        def ai_controls_read_access_required
          if helpers.show_ai_controls?(this_business) &&
            FeatureFlag.vexi.enabled?(:enterprise_ai_controls_fine_grained_permissions, this_business, default: false)
            # Use fine-grained AI controls permissions
            render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
          else
            # Fall back to business owner requirement
            render_404 unless this_business&.owner?(current_user)
          end
        end

        sig { void }
        def ai_controls_write_access_required
          if helpers.show_ai_controls?(this_business) &&
            FeatureFlag.vexi.enabled?(:enterprise_ai_controls_fine_grained_permissions, this_business, default: false)
            # Use fine-grained AI controls permissions
            render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
          else
            # Fall back to business owner requirement
            render_404 unless this_business&.owner?(current_user)
          end
        end

        sig { void }
        def ensure_default_models_app_enabled
          redirect_to settings_copilot_models_enterprise_path(copilot_business) unless this_business.feature_flag_enabled?(:copilot_default_models_app, default: false)
        end

        module Structs
          class CopilotModelResource < T::Struct
            const :type, String # Enterprise in this controller scope
            const :id, Integer
            const :name, String
            const :primaryAvatarUrl, T.nilable(String)
          end

          class CopilotModelConditionExpression < T::Struct
            const :id, T.nilable(Integer)
            const :targetableAttribute, T.nilable(String)
            const :operation, String
            const :value, T.nilable(String)
          end

          class CopilotModelRuleParameter < T::Struct
            const :restriction, T.nilable(String) # not used by models
            const :values, T.nilable(T::Hash[String, String]) # this is true for models, but could be T.untyped generically
          end

          class CopilotModelRule < T::Struct
            const :id, T.nilable(Integer)
            const :ruleType, String
            const :conditionExpression, CopilotModelConditionExpression
            const :priority, T.nilable(Integer) # not used by models
            const :parameters, CopilotModelRuleParameter
          end

          class CopilotModelSetting < T::Struct
            const :id, T.nilable(Integer)
            const :resource, CopilotModelResource
            const :name, String # copilot.models.allowed_models
            const :value, T::Hash[String, String] # this is true for models, but could be T.untyped generically
            const :rules, T::Array[CopilotModelRule]
          end

          class CopilotModel < T::Struct
            const :name, String
            const :displayName, String
            const :publisher, T.nilable(::Copilot::Types::Models::Publisher)
            const :category, T.nilable(::Copilot::Types::Models::Category)
            const :isPreview, T::Boolean
          end
        end
      end
    end
  end
end
