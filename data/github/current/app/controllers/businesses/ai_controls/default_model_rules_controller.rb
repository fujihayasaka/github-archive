# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::DefaultModelRulesController < Businesses::BusinessController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include GitHub::Memoizer
  include Businesses::CopilotShared
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
    ApplicationRecord::Billing

  before_action :login_required
  before_action :dotcom_required
  before_action :ai_controls_read_access_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled
  before_action :ensure_default_models_app_enabled
  before_action :ensure_model_rules_enabled

  allow_verified_fetch except: [:index]

  sig { returns(String) }
  def self.react_bundle_name
    "default-model-settings"
  end

  sig { void }
  def index
    respond_with_react(
      payload: RuleRoutePayload.new,
      title: "GitHub Copilot Model Rule",
      layout: "layouts/react_business",
      app_payload_generator: -> { app_payload },
      page_data: {
        selected_link: :businesses_ai_controls_copilot,
        sidebar: :ai_controls,
        stafftools: default_model_rules_stafftools_copilot_path(this_business, params[:rule_id]),
      },
    )
  end

  private

  class RuleRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "ruleRoute"
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

  sig { void }
  def ensure_model_rules_enabled
    render_404 unless this_business.feature_flag_enabled?(:use_setting_rules_copilot_models, default: false)
  end
end
