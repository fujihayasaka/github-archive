# typed: true
# frozen_string_literal: true

class Orgs::IdentityManagementController < Orgs::Controller
  before_action :dotcom_required
  # ordering of these three before_actions is important.
  # :redirect_to_business_saml_sso needs to come first
  before_action :redirect_to_business_saml_sso, only: [:sso]
  before_action :business_saml_sso_prohibited, except: [:sso]
  before_action :sso_provider_required
  before_action :require_valid_credential_lifetime, only: [:sso]

  javascript_bundle :signup

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:sso]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Permissions,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:sso_sign_up]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:sso_complete]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:sso_modal]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:sso_status]

  # The following actions do not require conditional access checks:
  # - sso: serves `/orgs/:org/sso`, serves as the prompt to SSO and create the
  #   require external identity session for protected endpoints.
  # - sso_sign_up: serves `/orgs/:org/sso/signup`, same as above but for
  #   users that need to sign up first.
  ACTIONS_EXCLUDED_FROM_CAP_CHECKS = %w(
    sso
    sso_sign_up
    sso_status
    sso_modal
    sso_complete
  )

  def sso # rubocop:todo GitHub/UseRestfulActions
    allow_external_redirect_after_post(provider: this_organization.saml_provider)

    url = org_idm_saml_initiate_url(this_organization,
      authorization_request: params[:authorization_request],
      return_to: params[:return_to],
    )

    view = create_view_model(
      Orgs::IdentityManagement::SingleSignOnView,
      organization: this_organization,
      initiate_sso_url: url,
      credential_authorization_request: credential_authorization_request,
    )

    render "orgs/identity_management/sso", layout: "layouts/session_authentication", locals: { view: view }
  end

  def sso_sign_up # rubocop:todo GitHub/UseRestfulActions
    unless session[:saml_user_data]
      redirect_to org_idm_sso_path(this_organization)
      return
    end

    if logged_in?
      saml_user_data = Platform::Provisioning::SamlUserData.get(session.delete(:saml_user_data))
      return_to = session.delete(:sso_return_to) || user_path(this_organization)
      sso_invitation_token = session.delete(:sso_invitation_token)

      ActiveRecord::Base.connected_to(role: :writing) do
        result = Platform::Provisioning::OrganizationIdentityProvisioner.provision_and_add_member \
          organization_id: this_organization.id,
          user_id: current_user.id,
          user_data: saml_user_data,
          mapper: Platform::Provisioning::SamlMapper,
          sso_invitation_token: sso_invitation_token

        if result.success?
          update_or_create_external_identity_session result.external_identity,
            expires_at: session[:unlinked_session_expires_at]

          flash[:notice] = "Welcome to the #{ this_organization.safe_profile_name } organization."
        elsif result.two_factor_requirement_not_met_error?
          flash[:notice] = "You must enable two factor authentication before joining the #{ this_organization.safe_profile_name } organization."
          # Restore the previous state so it can be resumed after the 2FA flow.
          session[:sso_return_to] = return_to
          session[:sso_invitation_token] = sso_invitation_token if sso_invitation_token
          session[:return_to] = org_idm_sso_sign_up_path(this_organization)
          if this_organization.feature_enabled?(:saml_user_data_persistence)
            session[:saml_user_data] = Platform::Provisioning::SamlUserData.persist(saml_user_data) if saml_user_data
          else
            session[:saml_user_data] = saml_user_data if saml_user_data
          end
          return redirect_to settings_user_2fa_intro_path
        # Here check if we got an error because the email invite was not verified
        elsif result.email_not_associated_with_logged_in_user?
          # redirect to the email verification page so user can add and verify their email
          # make sure there's a link back to the invitation on the page
          session[:show_email_not_verified_error_message] = true
          session[:url_to_return_to_invite] = org_show_invitation_url(this_organization, invitation_token: sso_invitation_token, via_email: "1")
          session[:inviting_organization_id] = this_organization.id
          current_user.reset_notice("show_link_to_org_invite")
          return redirect_to settings_email_preferences_path
        else
          flash[:error] = "There was an issue joining the organization: #{ result.errors.full_messages.to_sentence }"
        end
      end

      redirect_to_return_to(fallback: return_to)
    else
      view = create_view_model(
        Orgs::IdentityManagement::SingleSignOnView,
        organization: this_organization,
      )
      render "orgs/identity_management/sign_up_via_sso", layout: "layouts/session_authentication", locals: { view: view }
    end
  end

  # Action: Renders a partial prompting the user to renew their single sign-on
  # session. This will be shown to the user via a dialog when attempting an
  # XHR action with an expired SSO session.
  def sso_modal # rubocop:todo GitHub/UseRestfulActions
    url = org_idm_saml_initiate_url(this_organization, return_to: org_idm_sso_complete_path(this_organization))

    view = create_view_model(
      Orgs::IdentityManagement::SingleSignOnView,
      organization: this_organization,
      initiate_sso_url: url,
    )
    render "orgs/identity_management/sso_modal", layout: false, locals: { view: view }
  end

  # Action: The landing page users are redirected to after completing
  # SSO initiated from a client-side modal.
  #
  # Since SSO takes place in a new window, this page is responsible for
  # communicating status with the original window and closing itself.
  #
  # If communication with original window fails, the window will try to
  # automatically redirect to a fallback URL. If that too fails, the user will
  # be asked to click a link directing them to the fallback URL.
  def sso_complete # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Orgs::IdentityManagement::SingleSignOnCompleteView,
      organization: this_organization,
      saml_error: flash[:saml_error],
      fallback_url: user_path(this_organization),
    )
    render "orgs/identity_management/sso_complete", layout: "layouts/session_authentication", locals: { view: view }
  end

  # Action: Returns a JSON response indicating whether or not the current user
  # has a valid single sign on session for this organization.
  def sso_status # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.format.json?

    session_present =
      if params[:fakestate] == "promptssomodal"
        false
      else
        required_external_identity_session_present?(target: this_organization)
      end

    render json: session_present
  end

  private

  def sso_provider_required
    render_404 unless this_organization.saml_sso_enabled?
  end

  def business_saml_sso_prohibited
    render_404 if this_organization.business&.saml_sso_enabled?
  end

  def redirect_to_business_saml_sso
    return unless this_organization.business&.saml_sso_enabled?

    redirect_params = request.query_parameters
    # if there's no return to url already set, return the user to the org landing page
    redirect_params[:return_to] ||= user_url(this_organization)
    redirect_to business_idm_sso_enterprise_path(this_organization.business, redirect_params)
  end

  def credential_authorization_request
    return unless token = params[:authorization_request].presence

    Organization::CredentialAuthorization.consume_request(
      target: this_organization,
      token: token,
      actor: current_user,
    )
  end

  # Opt-out of IP allow list conditional access check
  def ip_allowlist_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    super
  end

  # opt-out of SAML conditional access check
  def require_active_external_identity_session?
    return false if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    true
  end

  # opt-out of 2FA conditional access check
  def two_factor_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    :yes
  end

  def require_valid_credential_lifetime
    return unless credential_authorization_request
    return unless this_organization.feature_enabled?(:personal_access_token_expiration_limit)
    return if this_organization.personal_access_token_classic_expiration_limit_exempted_for?(current_user)

    credential_type = credential_authorization_request.data["credential_type"]
    credential = credential_type.constantize.find_by_id(credential_authorization_request.data["credential_id"])
    return unless credential.is_a?(OauthAccess)

    render_404 unless credential.pat_adheres_by_targets_expiration_limit?(this_organization)
  end
end
