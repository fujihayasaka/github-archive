# typed: strict
# frozen_string_literal: true

class Businesses::CopilotModelsSettingsController < Businesses::BusinessController
  before_action :dotcom_required
  before_action :ai_controls_read_access_required_legacy, only: [:index]
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled
  before_action :ensure_default_models_app_not_enabled, only: [:index]

  javascript_bundle :copilot

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include GitHub::Memoizer
  include Businesses::CopilotShared

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
    only: [:index]

  sig { void }
  def index
    render_index
  end

  private

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

  sig { void }
  def ensure_default_models_app_not_enabled
    if (
      this_business.feature_flag_enabled?(:copilot_default_models_app, default: false) && (
        !this_business.feature_flag_enabled?(:copilot_standalone_model_settings, default: false) ||
        !copilot_business.copilot_standalone?
      )
    )
      redirect_to default_models_enterprise_ai_controls_enterprise_path(this_business)
    end
  end

  # Original FGP check for legacy index page
  sig { void }
  def ai_controls_read_access_required_legacy
    if helpers.show_ai_controls?(this_business) &&
       FeatureFlag.vexi.enabled?(:enterprise_ai_controls_fine_grained_permissions, this_business, default: false)
      # Use fine-grained AI controls permissions
      render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
    else
      # Fall back to business owner requirement
      business_owner_required
    end
  end
end
