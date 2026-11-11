# typed: strict
# frozen_string_literal: true

class Businesses::CopilotModelsSettingsController < Businesses::BusinessController
  before_action :dotcom_required
  before_action :business_owner_required, except: [:index]
  before_action :ai_controls_read_access_required, only: [:index]
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled
  before_action :ensure_react_enabled, only: [:models, :organizations, :settings]

  javascript_bundle :copilot

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include GitHub::Memoizer
  include Businesses::CopilotShared

  allow_verified_fetch only: [:models, :organizations, :settings, :update_settings]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index, :organizations, :models, :settings]

  sig { void }
  def index
    render_index
  end

  sig { void }
  def organizations # rubocop:disable GitHub/UseRestfulActions
    render json: copilot_business.organizations.map { |org| CopilotModelResource.new(
        id: org.id,
        type: "Organization",
        name: org.display_login,
        primaryAvatarUrl: org.primary_avatar_url,
      )
    }
  end

  sig { void }
  def models # rubocop:disable GitHub/UseRestfulActions
    visible_models = Copilot::Policies::MODELS.filter { |model| model.viewable_by_business?(copilot_business) }
    render json: visible_models.map { |model|
      if model.respond_to?(:serialize)
        next T.cast(model, Copilot::Policies::Model).serialize(current_copilot_user, copilot_business)
      end
      nil
    }.compact
  end

  sig { void }
  def settings # rubocop:disable GitHub/UseRestfulActions
    target = Copilot::Business.new(this_business)
    settings = CopilotDomain.domain.settings.load_settings([target], Copilot::Settings::CopilotModelsGroup::NAME)

    configuration_setting = T.must(settings.find { |s| s.provider_name == Copilot::Settings::CopilotModelsSettingProvider::NAME })
    rule_setting = settings.find { |s| s.provider_name == Copilot::Settings::CopilotSettingsDbProvider::NAME }

    combined_setting = translate_to_shared_setting(configuration_setting, rule_setting)
    render json: setting_to_json(combined_setting)
  end

  sig { void }
  def update_settings # rubocop:disable GitHub/UseRestfulActions
    target = Copilot::Business.new(this_business)
    begin
      setting_json = JSON.parse(request&.body.read)
    rescue JSON::ParserError
      render json: { error: "Malformed JSON" }, status: :bad_request
      return
    end

    unless setting_json.is_a?(Hash)
      render json: { error: "Invalid parameters" }, status: :unprocessable_entity
      return
    end

    # temp: the UI handles just a single Setting value with both "value" and "rules"
    # We need to split this into two separate settings, one for the "value" which is handled by
    # the CopilotModelsSettingProvider, and one for the "rules" which is handled by the DB provider
    configuration_setting = SettingsCore::MemorySetting.new(
      "copilot.models.supported_models",
      nil,
      target,
      Copilot::Settings::CopilotModelsSettingProvider::NAME,
      []
    )
    if setting_json["value"].is_a?(Hash)
      # temp: The UI also doesn't know about groups yet. So decompose the single value hash into multiple settings
      configuration_setting.group_settings = setting_json["value"].map do |model_name, status|
        SettingsCore::MemorySetting.new("copilot.models.supported_models.#{model_name}", status, target, configuration_setting.provider_name)
      end
    end

    setting_json["value"] = nil # clear value since we only want values to be saved in the legacy provider
    rule_setting = SettingsCore::MemorySetting.from_hash(setting_json, Copilot::Settings::CopilotSettingsDbProvider::NAME, target)

    [configuration_setting, rule_setting].compact.each do |setting|
      unless CopilotDomain.domain.settings.update_setting(setting, actor: current_user)
        render json: { error: "Failed to update setting: #{setting.name}" }, status: :unprocessable_entity
        return
      end
    end

    combined_setting = translate_to_shared_setting(configuration_setting, rule_setting)
    render json: setting_to_json(combined_setting)
  end

  private

  # Combines the setting with the "value" and the setting with the "rules" into a single setting
  # This is temporary to maintain compat with the UI which expects a single setting with both value and rules
  sig { params(value_setting: SettingsCore::ISetting, rule_setting: T.nilable(SettingsCore::ISetting)).returns(SettingsCore::ISetting) }
  def translate_to_shared_setting(value_setting, rule_setting)
    combined_configuration_value = value_setting.group_settings.each_with_object({}) do |s, acc|
      acc[s.name.sub("copilot.models.supported_models.", "")] = s.value if s.name.start_with?("copilot.models.supported_models.")
    end
    SettingsCore::MemorySetting.new("copilot.models.supported_models", combined_configuration_value, T.must(value_setting.targetable), "",
      rule_setting&.rules || [], id: rule_setting&.id)
  end

  sig { params(setting: SettingsCore::ISetting).returns(CopilotModelSetting) }
  def setting_to_json(setting)
    business = setting.targetable&.internal_record
    raise ArgumentError, "Setting targetable is not a Business" unless business.is_a?(Business)

    CopilotModelSetting.new(
      resource: CopilotModelResource.new(
        id: business.id,
        type: business.class.name || "Business",
        name: business.name,
        primaryAvatarUrl: business.primary_avatar_url
      ),
      id: setting.id,
      name: setting.name,
      value: setting.value,
      rules: setting.rules.map do |rule|
        CopilotModelRule.new(
          id: rule.id,
          ruleType: rule.rule_type,
          conditionExpression: CopilotModelConditionExpression.new(
            id: rule.condition_expression.id,
            targetableAttribute: rule.condition_expression.targetable_attribute,
            operation: rule.condition_expression.operation,
            value: rule.condition_expression.value,
          ),
          parameters: CopilotModelRuleParameter.new(
            values: rule.parameters["values"],
          )
        )
      end
    )
  end

  sig { params(error: T.nilable(String)).void }
  def render_index(error: nil)
    can_write = this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false
    is_admin = this_business&.adminable_by?(current_user) || false

    if helpers.show_ai_controls?(this_business)
      render "businesses/ai_controls/copilot/models/index", locals: {
        copilot_business: copilot_business,
        title: "Models",
        error: error,
        copilot_custom_models: this_business.feature_flag_enabled?(:copilot_custom_models, default: false),
        features_for_data_retention: get_features_for_data_retention,
        available_models: available_models_for_business,
        can_write: can_write,
        is_admin: is_admin
      }
    else
      render "businesses/copilot_settings/models/index", locals: {
        copilot_business: copilot_business,
        title: "Models",
        error: error,
        copilot_custom_models: this_business.feature_flag_enabled?(:copilot_custom_models, default: false),
        features_for_data_retention: get_features_for_data_retention,
        available_models: available_models_for_business,
        can_write: can_write,
        is_admin: is_admin
      }
    end
  end

  sig { void }
  def ensure_copilot_enabled
    render_404 unless copilot_business.copilot_enabled?
  end

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

  sig { returns(T::Boolean) }
  def copilot_model_settings_react_enabled?
    this_business.feature_flag_enabled?(:copilot_model_settings_react, default: false)
  end

  sig { void }
  def ensure_react_enabled
    render_404 unless copilot_model_settings_react_enabled?
  end

  sig { void }
  def ai_controls_read_access_required
    if helpers.show_ai_controls?(this_business) && FeatureFlag.vexi.enabled?(:enterprise_ai_controls_fine_grained_permissions, this_business, default: false)
      # Use fine-grained AI controls permissions
      render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
    else
      # Fall back to business owner requirement
      business_owner_required
    end
  end
end
