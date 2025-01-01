# typed: true
# frozen_string_literal: true

class Businesses::IdentityManagementController < Businesses::BusinessController
  include BusinessesHelper

  before_action :dotcom_required
  before_action :sso_provider_required
  before_action :require_valid_credential_lifetime, only: [:sso]

  javascript_bundle :signup

  # The following actions do not require conditional access checks:
  # - sso: serves `/enterprises/:slug/sso`, serves as the prompt to SSO and create the
  #   require external identity session for protected endpoints.
  # - sso_sign_up: serves `/enterprises/:slug/sso/signup`, same as above but for
  #   users that need to sign up first.
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: %w(
    sso
    sso_sign_up
    sso_status
    sso_modal
    sso_complete
  )

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:sso]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    only: [:sso_complete]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:sso_modal]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:sso_sign_up]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:sso_status]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:sso], optional: true

  def sso # rubocop:todo GitHub/UseRestfulActions
    allow_external_redirect_after_post(provider: this_business.external_provider)

    adding_account = params[:add_account] == "1"
    if valid_sso_session_for_business? && !credential_authorization_request && !adding_account
      GitHub.dogstats.increment("enterprise_sso.valid_session_auto_forward")
      return redirect_to_return_to(fallback: "/")
    end

    url = if this_business.oidc_enabled?
      idm_oidc_initiate_enterprise_url(this_business,
        authorization_request: params[:authorization_request],
        return_to: params[:return_to] || enterprise_path(this_business),
        setup: params[:setup]
      )
    else
      idm_saml_initiate_enterprise_url(this_business,
        authorization_request: params[:authorization_request],
        return_to: params[:return_to]
      )
    end

    view = create_view_model(
      Businesses::IdentityManagement::SingleSignOnView,
      business: this_business,
      initiate_sso_url: url,
      credential_authorization_request: credential_authorization_request,
      account_switcher_helper: account_switcher_helper,
      return_to: return_to || enterprise_path(this_business),
    )

    render "businesses/identity_management/sso", layout: "layouts/session_authentication", locals: { view: view }
  end

  def sso_sign_up # rubocop:todo GitHub/UseRestfulActions
    unless session[:saml_user_data]
      redirect_to business_idm_sso_enterprise_path(this_business)
      return
    end

    if logged_in?
      saml_user_data = Platform::Provisioning::SamlUserData.get(session.delete(:saml_user_data))
      return_to = session.delete(:sso_return_to) || enterprise_path(this_business)

      ActiveRecord::Base.connected_to(role: :writing) do
        result = if this_business.feature_enabled?(:enterprise_idp_provisioning)
          Platform::Provisioning::IdentityProvisioner.provision_and_add_member \
            target: this_business,
            user_id: current_user.id,
            user_data: saml_user_data,
            mapper: Platform::Provisioning::SamlMapper
        else
          Platform::Provisioning::IdentityProvisioner.provision \
            target: this_business,
            user_id: current_user.id,
            user_data: saml_user_data,
            mapper: Platform::Provisioning::SamlMapper
        end

        if result.success?
          update_or_create_external_identity_session result.external_identity,
            expires_at: session[:unlinked_session_expires_at]

          flash[:notice] = "Welcome to the #{ this_business.name } enterprise."
        else
          flash[:error] = "There was an issue joining the enterprise: #{ result.errors.full_messages.to_sentence }"
        end
      end

      redirect_to_return_to(fallback: return_to)
    else
      view = create_view_model(Businesses::IdentityManagement::SingleSignOnView, business: this_business)
      render "businesses/identity_management/sign_up_via_sso", layout: "layouts/session_authentication", locals: { view: view }
    end
  end

  # Action: Renders a partial prompting the user to renew their single sign-on
  # session. This will be shown to the user via a dialog when attempting an
  # XHR action with an expired SSO session.
  def sso_modal # rubocop:todo GitHub/UseRestfulActions
    url = if this_business.oidc_enabled?
      idm_oidc_initiate_enterprise_url(this_business, return_to: business_idm_sso_complete_enterprise_url(this_business))
    else
      idm_saml_initiate_enterprise_url(this_business, return_to: business_idm_sso_complete_enterprise_url(this_business))
    end

    view = create_view_model(
      Businesses::IdentityManagement::SingleSignOnView,
      business: this_business,
      initiate_sso_url: url,
    )
    render "businesses/identity_management/sso_modal", layout: false, locals: { view: view }
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
      Businesses::IdentityManagement::SingleSignOnCompleteView,
      business: this_business,
      sso_error: flash[:saml_error] || flash[:oidc_error],
      fallback_url: enterprise_path(this_business),
    )
    render "businesses/identity_management/sso_complete", layout: "layouts/session_authentication", locals: { view: view }
  end

  # Action: Returns a JSON response indicating whether or not the current user
  # has a valid single sign on session for this organization.
  def sso_status # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.format.json?

    session_present =
      if params[:fakestate] == "promptssomodal"
        false
      else
        required_external_identity_session_present?(target: this_business)
      end

    render json: session_present
  end

  private

  def sso_provider_required
    render_404 unless this_business&.saml_sso_enabled? || this_business&.oidc_enabled?
  end

  def credential_authorization_request
    return unless token = params[:authorization_request].presence
    return unless logged_in?

    Organization::CredentialAuthorization.consume_request(
      target: this_business,
      token: token,
      actor: current_user,
    )
  end

  def valid_sso_session_for_business?
    return false unless logged_in?
    return false unless current_user.is_emu_and_not_first_owner?
    return false unless this_business&.saml_sso_enabled? || this_business&.oidc_enabled?

    current_user.external_identity_sessions.active.by_user_session(user_session).by_sso_provider(this_business.external_provider).exists?
  end

  def require_valid_credential_lifetime
    return unless credential_authorization_request
    return unless this_business.feature_enabled?(:personal_access_token_expiration_limit)
    return if this_business.personal_access_token_classic_expiration_limit_exempted_for?(current_user)

    credential_type = credential_authorization_request.data["credential_type"]
    credential = credential_type.constantize.find_by_id(credential_authorization_request.data["credential_id"])
    return unless credential.is_a?(OauthAccess)

    render_404 unless credential.pat_adheres_by_targets_expiration_limit?(this_business)
  end
end
