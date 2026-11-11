# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::DefaultModelsController < Businesses::BusinessController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include GitHub::Memoizer
  include Businesses::AiControls::Concerns::DefaultModels

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing, only: [:index]

  before_action :login_required
  before_action :dotcom_required
  before_action :ai_controls_read_access_required, except: [:update]
  before_action :ai_controls_write_access_required, only: [:update]
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled
  before_action :ensure_default_models_app_enabled, only: [:index]

  allow_verified_fetch except: [:index]

  sig { returns(String) }
  def self.react_bundle_name
    "default-model-settings"
  end

  sig { void }
  def index
    if !this_business.feature_flag_enabled?(:copilot_default_models_app, default: false)
      can_write = this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false
      is_admin = this_business&.adminable_by?(current_user) || false
      render "businesses/ai_controls/copilot/models/index", locals: {
        copilot_business:,
        title: "Models",
        copilot_custom_models: this_business.feature_flag_enabled?(:copilot_custom_models, default: false),
        features_for_data_retention: get_features_for_data_retention,
        available_models: available_models_for_business,
        can_write:,
        is_admin:,
      }
    else
      add_client_feature_flag([:use_setting_rules_copilot_models], entity: this_business)
      respond_with_react(
        payload: OverviewRoutePayload.new,
        title: "GitHub Copilot Models",
        layout: "layouts/react_business",
        app_payload_generator: -> { app_payload },
        page_data: {
          selected_link: :businesses_ai_controls_copilot,
          sidebar: :ai_controls,
          stafftools: default_models_stafftools_copilot_path(this_business),
        },
      )
    end
  end

  sig { void }
  def update
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
    configuration_settings = []
    if setting_json["value"].is_a?(Hash)
      setting_json["value"].each do |model_name, status|
        configuration_settings << SettingsCore::MemorySetting.new("copilot.models.supported_models.#{model_name}", status, target, Copilot::Settings::CopilotModelsSettingProvider::NAME)
      end
    end

    setting_json["value"] = nil # clear value since we only want values to be saved in the legacy provider
    rule_setting = SettingsCore::MemorySetting.from_hash(setting_json, Copilot::Settings::CopilotSettingsDbProvider::NAME, target)

    unless CopilotDomain.domain.settings.update_settings(configuration_settings + [rule_setting], actor: current_user)
      render json: { error: "Failed to update setting: #{rule_setting.name}" }, status: :unprocessable_entity
      return
    end

    combined_setting = translate_to_shared_setting(configuration_settings, rule_setting, target)
    render json: setting_to_json(combined_setting)
  end

  sig { void }
  def organizations_data # rubocop:disable GitHub/UseRestfulActions
    render json: organizations
  end

  sig { void }
  def models_data # rubocop:disable GitHub/UseRestfulActions
    render json: models
  end

  sig { void }
  def settings_data # rubocop:disable GitHub/UseRestfulActions
    render json: settings
  end

  class OverviewRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "overviewRoute"
    end

    sig { void }
    def initialize; end

    sig do
      override.returns(T::Hash[String, T.untyped])
    end
    def payload
      {}
    end
  end
end
