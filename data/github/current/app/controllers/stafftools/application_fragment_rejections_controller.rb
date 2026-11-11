# typed: true
# frozen_string_literal: true

class Stafftools::ApplicationFragmentRejectionsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_dotcom
  before_action :ensure_owner_exists
  before_action :load_application
  before_action :ensure_fragment_rejection_enabled

  def create
    # vexi_management is the only API for toggling per-actor feature flags from stafftools.
    # The cop discourages it because it's a legacy compatibility API, but stafftools-driven
    # per-app flag toggling is an accepted use case (see also: beta_signup_controller.rb).
    FeatureFlag.vexi_management.add_feature_flag_actors(:oauth_fragment_exempt, [@app]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
    FeatureFlag.vexi.clear_feature_flag_memoization(:oauth_fragment_exempt)
    instrument_exemption_change(action: "exempt")
    flash[:notice] = "Application exempted from fragment rejection."
    flash[:oauth_fragment_exempt_override] = true
    redirect_back fallback_location: stafftools_user_application_path(this_user, @app)
  end

  def destroy
    FeatureFlag.vexi_management.remove_feature_flag_actors(:oauth_fragment_exempt, [@app]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
    FeatureFlag.vexi.clear_feature_flag_memoization(:oauth_fragment_exempt)
    instrument_exemption_change(action: "enforce")
    flash[:notice] = "Fragment rejection enforcement restored for this application."
    flash[:oauth_fragment_exempt_override] = false
    redirect_back fallback_location: stafftools_user_application_path(this_user, @app)
  end

  private

  def ensure_dotcom
    render_404 unless GitHub.runtime.dotcom?
  end

  def ensure_owner_exists
    render_404 unless this_user.present?
  end

  def load_application
    @app = OauthAccessTokens.domain.oauth_applications.by_id!(params[:application_id])
  end

  def ensure_fragment_rejection_enabled
    return if @app && FeatureFlag.vexi.enabled?(:oauth_fragment_rejection, @app, default: false)
    render_404
  end

  def instrument_exemption_change(action:)
    GitHub.instrument(
      "oauth.fragment_rejection_exemption.stafftools_toggle",
      action: action,
      application_id: @app.id,
      application_name: @app.name,
      actor: current_user,
      actor_id: current_user.id,
      actor_login: current_user.login,
    )
  end
end
