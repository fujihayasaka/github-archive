# typed: true
# frozen_string_literal: true

class Businesses::TeamSyncController < Businesses::BusinessController

  # allowed for CAP skip as it is a simple redirect to help docs
  # Team-Sync beta signup controller is being disabled and should ultimately be removed
  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction
  before_action :this_business_required, except: [:azure_callback]
  before_action :business_owner_required, except: [:setup, :initiate, :azure_callback, :review]
  before_action :perform_conditional_access_checks, except: [:azure_callback] # rubocop:todo GitHub/DoNotSkipCapBeforeAction
  before_action :require_external_identity, except: [:azure_callback]
  before_action :ensure_no_error_with_azure_callback_team_sync_setup_flow, only: [:azure_callback]

  around_action :select_write_database, only: [:azure_callback]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:azure_callback]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:review]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:setup]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:azure_callback, :review], optional: true

  ERROR_MESSAGES = {
    invalid_state_transition: "Cannot do that right now. Check the current state and try again.",
    invalid_provider_type: "The selected identity provider is not supported. Select a valid identity provider and try again.",
    invalid_provider_id: "The identity provider was not detected or is not supported. Ensure your SAML SSO identity provider is correctly configured.",
    invalid_state: "There was an error reading the response. Try again.",
    registration_error: "There was an internal error. Try again.",
    admin_consent_failed: "Admin approval failed: [%s] %s",
    tenant_update_failed: "There was an error saving the settings. Try again.",
    token_not_found: "There was a problem with your setup token. Please try again.",
  }
  ERROR_MESSAGES.default = "An unknown error occurred. Please try again. (code: %s)"

  # If allowed set the state of the tenant locally and on group syncer to allow setup to occur.
  # This is a negotiation between the local state and the group syncer service to check if we are in a state
  # in which this is allowed and if so, make group syncer aware we are transitioning.
  def install # rubocop:todo GitHub/UseRestfulActions
    provider = ::TeamSync::Provider.detect(issuer: this_business.external_identity_session_owner.saml_provider.issuer)
    if provider.nil? || !provider.supported_for_business?(this_business)
      flash[:error] = ERROR_MESSAGES[:invalid_provider_type]
      redirect_to settings_security_enterprise_url(this_business)
      return
    end

    err, downstream_err = team_sync_setup_flow.initiate_setup(provider_type: provider.type, provider_id: provider.id)
    if err
      flash[:error] = ERROR_MESSAGES[err] % { err: err, provider_type: provider.type }
      redirect_to settings_security_enterprise_url(this_business)
      return
    end

    token, err = team_sync_setup_flow.generate_setup_lease_token
    if err
      flash[:error] = ERROR_MESSAGES[err] % { err: err, provider_type: provider.type }
      redirect_to settings_security_enterprise_url(this_business)
      return
    end

    redirect_to team_sync_setup_enterprise_path(this_business, token: token)
  end

  def setup # rubocop:todo GitHub/UseRestfulActions
    token = setup_params[:token]
    if token.nil? || !team_sync_setup_flow.get_token(token).valid?
      flash[:error] = ERROR_MESSAGES[:token_not_found]
      redirect_to settings_security_enterprise_url(this_business)
      return
    end

    if team_sync_setup_flow.review_required?
      redirect_to team_sync_review_enterprise_path(this_business, token: token)
      return
    end

    unless team_sync_setup_flow.pending?
      flash[:error] = ERROR_MESSAGES[:invalid_state_transition]
      redirect_to settings_security_enterprise_url(this_business)
      return
    end

    view = create_view_model(
      Businesses::SecuritySettings::TeamSync::InitiateSetupView,
      business: this_business,
      tenant: team_sync_setup_flow.tenant,
      token: setup_params[:token],
    )
    render "businesses/security_settings/team_sync/setup", layout: "layouts/session_authentication", locals: { view: view }
  end

  def initiate # rubocop:todo GitHub/UseRestfulActions
    token = initiate_params[:token]
    if token.nil? || !team_sync_setup_flow.get_token(token).valid?
      render_404
      return
    end

    unless team_sync_setup_flow.pending?
      flash[:error] = ERROR_MESSAGES[:invalid_state_transition]
      redirect_to settings_security_enterprise_url(this_business)
      return
    end

    setup_url = team_sync_setup_flow.setup_url(redirect_uri: enterprises_team_sync_azure_callback_url, token: token)
    redirect_url = setup_url.to_s
    render "businesses/security_settings/meta_redirect", locals: { redirect_url: redirect_url }, layout: "layouts/redirect"
  end

  def azure_callback # rubocop:todo GitHub/UseRestfulActions
    return if performed?

    perform_conditional_access_checks
    return if performed?

    require_external_identity
    return if performed?

    err = team_sync_setup_flow.setup_callback(
      provider_type: "azuread",
      params: azure_callback_params,
    )
    if err
      if err == :admin_consent_failed
        flash[:error] = ERROR_MESSAGES[:admin_consent_failed] % azure_callback_params.values_at("error", "error_description")
      else
        flash[:error] = ERROR_MESSAGES[err] % { err: err }
      end
      redirect_to team_sync_setup_enterprise_url(this_business)
      return
    end

    redirect_to team_sync_review_enterprise_path(this_business, token: azure_callback_token)
  end

  def review # rubocop:todo GitHub/UseRestfulActions
    token = review_params[:token]

    if viewer_is_non_business_owner?
      if token.nil? || !team_sync_setup_flow.get_token(token).valid?
        render_404
        return
      end

      if !team_sync_setup_flow.review_required?
        flash[:error] = ERROR_MESSAGES[:invalid_state_transition]
        redirect_to team_sync_setup_enterprise_url(this_business, token: token)
        return
      end

      view = create_view_model(
        Businesses::SecuritySettings::TeamSync::ReviewPendingAssignmentView,
        team_sync_setup_flow: team_sync_setup_flow,
        business: this_business,
        business_name: this_business.name,
        tenant_name: team_sync_setup_flow.provider_id,
        token: token,
      )
      render "businesses/security_settings/team_sync/review_unprivileged", layout: "layouts/session_authentication", locals: { view: view }
      return
    end

    if !team_sync_setup_flow.review_required?
      flash[:error] = ERROR_MESSAGES[:invalid_state_transition]
      redirect_to team_sync_setup_enterprise_url(this_business, token: token)
      return
    end

    view = create_view_model(
      Businesses::SecuritySettings::TeamSync::ReviewPendingAssignmentView,
      team_sync_setup_flow: team_sync_setup_flow,
      business: this_business,
      business_name: this_business.name,
      tenant_name: team_sync_setup_flow.provider_id,
    )
    render "businesses/security_settings/team_sync/review", layout: "layouts/session_authentication", locals: { view: view }
  end

  def approve # rubocop:todo GitHub/UseRestfulActions
    err = team_sync_setup_flow.approve
    if err
      flash[:error] = ERROR_MESSAGES[err] % { err: err }
      redirect_to team_sync_review_enterprise_url(this_business)
      return
    end
    redirect_to settings_security_enterprise_url(this_business)
  end

  def cancel # rubocop:todo GitHub/UseRestfulActions
    err = team_sync_setup_flow.cancel
    if err
      flash[:error] = ERROR_MESSAGES[err] % { err: err }
      redirect_to team_sync_review_enterprise_url(this_business)
      return
    end
    flash[:notice] = "Team synchronization setup has been cancelled"
    redirect_to settings_security_enterprise_url(this_business)
  end

  def disable # rubocop:todo GitHub/UseRestfulActions
    err = team_sync_setup_flow.disable
    if err
      flash[:error] = ERROR_MESSAGES[err] % { err: err }
      redirect_to team_sync_review_enterprise_url(this_business)
      return
    end
    flash[:notice] = "Team synchronization setup has been disabled"
    redirect_to settings_security_enterprise_url(this_business)
  end

  def update
    # Toggle the forbid_organization_invites flag on the tenant
    forbidden = params["team_sync_forbid_organization_invites"] == "on"
    ts_tenant = this_business.team_sync_tenant
    if ts_tenant.present? && ts_tenant.update(forbid_organization_invites: forbidden)
      flash[:notice] = "Team synchronization settings have been updated"
    else
      flash[:error] = ERROR_MESSAGES[:tenant_update_failed]
    end

    redirect_to settings_security_enterprise_url(this_business)
  end

  private

  def ensure_no_error_with_azure_callback_team_sync_setup_flow
    setup_flow, err = azure_callback_team_sync_setup_flow_and_error
    return unless err

    flash[:error] = ERROR_MESSAGES[err] % { err: err }
    if setup_flow.present?
      redirect_to team_sync_setup_enterprise_url(setup_flow.business, token: azure_callback_token)
    else
      render_404
    end
  end

  memoize def this_business
    if params[:action] == "azure_callback"
      team_sync_setup_flow&.business
    else
      super # Businesses::BusinessController#this_business
    end
  end

  def viewer_is_non_business_owner?
    return true if !logged_in?
    !this_business.owner?(current_user)
  end

  def azure_callback_params
    params.permit("admin_consent", "tenant", "state", "error", "error_description")
  end

  memoize def azure_callback_token
    azure_callback_params["state"]
  end

  memoize def azure_callback_team_sync_setup_flow_and_error
    setup_flow, err = ::TeamSync::SetupFlow.callback(
      token: azure_callback_token,
      provider_id: azure_callback_params["tenant"],
      actor: current_user, # may be nil
    )
    [setup_flow, err]
  end

  def setup_params
    params.permit("token", "slug")
  end

  def initiate_params
    params.permit("token", "utf8", "authenticity_token", "slug")
  end

  def review_params
    params.permit("token", "slug")
  end

  memoize def team_sync_setup_flow
    if params[:action] == "azure_callback"
      setup_flow, _ = azure_callback_team_sync_setup_flow_and_error
      setup_flow
    else
      ::TeamSync::SetupFlow.new(business: this_business, actor: current_user)
    end
  end

  def require_external_identity
    return unless GitHub.external_identity_session_enforcement_enabled?
    return unless logged_in?
    return unless this_business.member?(current_user)
    return if current_external_identity(target: this_business).present?

    if request.xhr?
      head :unauthorized
    else
      render_external_identity_session_required
    end
  end

  # Internal: This before_action renders a standard 404 page if
  # `this_business` is nil.
  #
  # Returns nothing.
  def this_business_required
    render_404 if this_business.nil?
  end
end
