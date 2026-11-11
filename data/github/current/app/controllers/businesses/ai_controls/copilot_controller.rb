# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::CopilotController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::CopilotShared

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot

  layout "layouts/react_business"

  allow_verified_fetch only: [:index]

  before_action :ensure_not_standalone_copilot_business
  before_action :ai_controls_enabled?
  before_action :ensure_trial_business_is_dfd_trial_or_contains_cfb_trial, only: [:index]
  before_action :handle_ai_controls_trial_entry_flow, only: [:index]
  before_action :ai_controls_read_required

  sig { void }
  def index
    enabled_models_count = available_models_for_business.count do |model|
      model.value(copilot_business) == "enabled"
    end

    render "businesses/ai_controls/copilot/index", locals: {
      copilot_business: copilot_business,
      can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
      is_admin: this_business&.adminable_by?(current_user) || false,
      title: "Copilot",
      selected_link: ai_controls_selected_link,
      copilot_custom_models: this_business.feature_flag_enabled?(:copilot_custom_models, default: false),
      features_for_data_retention: get_features_for_data_retention,
      render_copilot_feedback_opt_in_settings: render_copilot_feedback_opt_in_settings?,
      render_copilot_beta_features_opt_in_settings: render_copilot_beta_features_opt_in_settings?,
      render_copilot_swe_agent_settings: render_copilot_swe_agent_settings?,
      render_copilot_code_review_settings: render_copilot_code_review_settings?,
      render_copilot_code_review_beta_features_settings: render_copilot_code_review_beta_features_settings?,
      render_ccr_direct_org_billing_settings: render_ccr_direct_org_billing_settings?,
      enabled_models_text: "#{enabled_models_count} model#{'s' if enabled_models_count != 1} enabled",
    }
  end

  private

  sig { void }
  def ai_controls_enabled?
    if this_business.dunning? || this_business.trial_expired?
      return redirect_to enterprise_path(this_business)
    end
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_read_required
    render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
  end
end
