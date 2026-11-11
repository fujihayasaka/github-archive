# typed: false
# frozen_string_literal: true

module IdentityManagement::IdentityRelinkSamlControllerMethods
  private

  def get_target_type(target)
    target.is_a?(Business) ? "enterprise" : "organization"
  end

  def get_target_tags(target)
    ["target_name:#{target.name}", "target_id:#{target.id}"]
  end

  def emit_relink_metrics(target, identity_will_be_relinked)
    GitHub.dogstats.increment(
      "external_identities.#{get_target_type(target)}_saml_identity_relink",
      tags: [*get_target_tags(target), "identity_will_be_relinked:#{identity_will_be_relinked}"]
    )
  end

  def emit_relink_continue_metrics(target)
    GitHub.dogstats.increment(
      "external_identities.#{get_target_type(target)}_saml_identity_relink_continue",
      tags: get_target_tags(target)
    )
  end

  def get_relink_form_url(target)
    target.is_a?(Business) ? idm_saml_continue_enterprise_url(target) : org_idm_saml_continue_url(target)
  end

  def get_sso_url(target)
    target.is_a?(Business) ? business_idm_sso_sign_up_enterprise_path(target) : org_idm_sso_sign_up_path(target)
  end

  def check_for_identity_relink(target:, skip_identity_relink_checks:, auth_result:, relay_state:, provisioner:)
    return false if target.enterprise_managed_user_enabled?
    return false unless logged_in?
    return false unless auth_result.success?

    # if true, this indicates that the user has confirmed they want to relink their identity
    if skip_identity_relink_checks
      emit_relink_continue_metrics(target)
      return false
    end

    error = provisioner.validate_identity_relink \
      target: target,
      user_id: current_user.id,
      user_data: auth_result.user_data,
      mapper: Platform::Provisioning::SamlMapper

    identity_will_be_relinked = error.is_a?(Platform::Provisioning::IdentityRelinkError)
    emit_relink_metrics(target, identity_will_be_relinked)

    if identity_will_be_relinked
      initiate_relink_warning_flow \
        target: target,
        auth_result: auth_result,
        relay_state: relay_state,
        identity_relink_error: error,
        form_submit_url: get_relink_form_url(target),
        sso_url: get_sso_url(target)
    end

    identity_will_be_relinked
  end

  def validate_saml_continue_session(target)
    return false unless logged_in?

    session_token = params[:IdentityRelinkSessionToken]
    request_id = params[:RequestID]

    return false if session_token.nil? || request_id.nil?

    session_key = generate_identity_relink_session_key(request_id, target)

    Platform::Authentication::IdentityRelink.verify_session_token(session_key: session_key, session_token: session_token)
  end

  def generate_identity_relink_session_id(auth_result, target)
    # If SSO was SP initiated, we will have an InResponseTo attribute that we can use, otherwise fall back to a
    # generated ID.
    auth_result.assertion.in_response_to || SecureRandom.hex(32)
  end

  def generate_identity_relink_session_key(request_id, target)
    "#{current_user.id}-#{request_id}"
  end

  # Reinitiate the relay state
  # Why? Relay state would have already been consumed in the `saml_controller#consume` method by the time we got here.
  # At this point, we've identified that the user is attempting to link a different SAML identity than the one we
  # have persisted. There are two flows that can happen from here:
  #   1. The user confirms they want to relink their identity
  #   2. The user cancels the relink flow and goes back to SSO
  # In the first case, we will need the relay state again since we call back into the `saml_consume` method. Without
  # an unconsumed relay state, that method will fail. Since we've already consumed the original, we know that it was
  # valid and the identity that was passed in came from the original user.
  # In the second case, a new relay state will be generated prior to sending the user back to the IdP
  def reinitiate_relay_state(relay_state)
    relay_state.initiate(data: relay_state.data, expires: Platform::Authentication::SamlRelayState::DEFAULT_EXPIRY.from_now)

    # These cookies will be reconsumed by the `saml_controller#consume` method.
    # They are set here because they would've been deleted at this point.
    # see: app/controllers/orgs/identity_management/saml_controller.rb:546
    #   or
    # see: app/controllers/businesses/identity_management/saml_controller.rb:758
    cookies.encrypted[:saml_csrf_token] = saml_csrf_cookie(relay_state.digest)
    cookies.encrypted[:saml_csrf_token_legacy] = saml_csrf_cookie(relay_state.digest)
  end

  def initiate_relink_warning_flow(target:, auth_result:, relay_state:, identity_relink_error:, form_submit_url:, sso_url:)
    request_id = generate_identity_relink_session_id(auth_result, target)
    relink_session_key = generate_identity_relink_session_key(request_id, target)
    identity_relink_session_token = Platform::Authentication::IdentityRelink.generate_identity_relink_session_token(session_key: relink_session_key)

    reinitiate_relay_state(relay_state) if auth_result.assertion.in_response_to.present? && relay_state.present?

    view = create_view_model(
      IdentityManagement::IdentityRelinkWarningView,
      saml_response: params[:SAMLResponse],
      relay_state: params[:RelayState],
      identity_relink_session_token: identity_relink_session_token,
      request_id: request_id,
      target: target,
      identity_relink_error: identity_relink_error,
      form_submit_url: form_submit_url,
      sso_url: sso_url,
    )
    render "identity_management/identity_relink_warning", layout: "layouts/session_authentication", locals: { view: view }
  end
end
