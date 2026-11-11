# typed: true
# frozen_string_literal: true

class CopilotBusinessSignupTrialController < ApplicationController
  include Businesses::Concerns::BusinessAccess
  include WithParameterValidation

  depends_on_clusters ApplicationRecord::Mysql1,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Configurations,
                      only: [:index]

  before_action :redirect_to_signup
  before_action :dotcom_required
  before_action :require_feature_flag
  before_action :business_access_required
  before_action :require_trial_eligibility
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  layout "layouts/get_started"

  stylesheet_bundle "signup"

  sig { void }
  def index
    orgs = this_business.organizations.where(id: current_user.owned_organization_ids).order(:login)
    pre_selected_org = this_business.organization_for_advanced_security_trial(actor: current_user)
    show_skip_to_enable = this_business.advanced_security_metered_for_entity?
    benefit = extract_with_param(params)

    render "copilot_business_signup_trial/index", locals: {
      business: this_business,
      orgs: orgs,
      pre_selected_org: pre_selected_org,
      show_skip_to_enable: show_skip_to_enable,
      trial_days: this_business.new_advanced_security_trial_days,
      trial_post_path: advanced_security_trials_path(this_business),
      no_orgs_return_to: settings_security_analysis_enterprise_path(this_business),
      error_return_to: enterprise_licensing_path(this_business),
      with_param: benefit,
    }
  end

  private

  sig { returns(T.nilable(String)) }
  def slug_param
    params[:enterprise]
  end

  sig { void }
  def require_trial_eligibility
    render_404 unless this_business.eligible_for_self_serve_advanced_security_trial?
  end

  sig { void }
  def require_feature_flag
    render_404 unless FeatureFlag.vexi.enabled?(:ghas_get_started_trial_flow, this_business, default: false)
  end

  sig { void }
  def redirect_to_signup
    redirect_to signup_path(return_to: request.url) unless logged_in?
  end
end
