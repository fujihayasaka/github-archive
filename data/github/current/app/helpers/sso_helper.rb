# typed: false
# frozen_string_literal: true

module SsoHelper
  SSO_SESSION_CHECK_THRESHOLD = 10.minutes

  # Public: Creates HTML head tags used by client side single-sign on helpers.
  # Their presence indicates that the current organization is SSO enforced for the user.
  #
  # See app/assets/modules/github/sso.js for usage.
  #
  # Returns a String.
  def sso_prompt_link_tags
    return unless current_saml_enforcement_policy.try(:enforced?) || current_session_enforcement_policy.try(:enforced?)
    current_session_enforcement_target = current_saml_enforcement_policy&.target || current_session_enforcement_policy&.target

    modal_url = get_modal_url(current_session_enforcement_target)
    modal_tag = tag(:link, rel: "sso-modal",   href: modal_url, "data-turbo-transient": true)

    session_url = get_session_url(current_session_enforcement_target)
    session_tag = tag(:link, rel: "sso-session", href: session_url, "data-turbo-transient": true)

    begin_sso_checks_at = sso_expires_around(current_session_enforcement_target)
    expiry_tag = tag(:meta, name: "sso-expires-around", content: begin_sso_checks_at.to_i, "data-turbo-transient": true)

    safe_join [modal_tag, session_tag, expiry_tag]
  end

  def sso_expires_around(target)
    sso_session = current_external_identity_session(target: target)
    expires_at = sso_session.try(:expires_at) || Time.now

    # allow forcing the SSO modal
    expires_at = Time.now if params[:fakestate] == "promptssomodal"

    expires_at - SSO_SESSION_CHECK_THRESHOLD
  end

  def restricted_sso_target_link(target, return_to: "", text: "", join_word: "within")
    if target.is_a?(Organization)
      target = target.business if target.sso_enabled_on_business?
    end
    path = if target.is_a?(Business)
      business_idm_sso_enterprise_path(target, return_to: return_to)
    else
      org_idm_sso_path(target, return_to: return_to)
    end
    link = link_to("Single sign-on", path)

    safe_join([
      link,
      text,
      (target.is_a?(Business) ? "for organizations #{join_word} the" : "#{join_word} the"),
      content_tag(:strong, target.is_a?(Business) ? target.name : target),
      (target.is_a?(Business) ? "enterprise." : "organization."),
    ], " ")
  end

  # given an Array of Organizations, it returns the parent Business if it exists, otherwise the Organization.
  # Used to make sure we don't prompt users more than once if multiple Organizations belong to a single Business.
  def targets_for(unauthorized_saml_organizations)
    unauthorized_saml_organizations.map do |org|
      if org.sso_enabled_on_business?
        org.business
      else
        org
      end
    end.uniq
  end

  # The resource URL path for an external identity target.
  #
  # target - An Organization or Business that is the target for an ExternalIdentity.
  #
  # Returns a String representing the URL path to the target resource.
  def external_identity_target_resource_path(target)
    case target
    when ::Business
      enterprise_path(target)
    when ::Organization
      user_path(target)
    else
      raise ArgumentError, "Unexpected target type: #{target.class.name}"
    end
  end

  # The SSO URL path for an external identity target.
  #
  # target - An Organization or Business that is the target for an ExternalIdentity.
  #
  # Returns a String representing the SSO URL path for the target.
  def external_identity_target_sso_path(target, **params)
    case target
    when ::Business
      business_idm_sso_enterprise_path(target, **params)
    when ::Organization
      org_idm_sso_path(target, **params)
    else
      raise ArgumentError, "Unexpected target type: #{target.class.name}"
    end
  end

  # The revoke SSO session URL path for an external identity target.
  #
  # target - An Organization or Business that is the target for an ExternalIdentity.
  #
  # Returns a String representing the revoke SSO session URL path for the target.
  def external_identity_target_sso_revoke_path(target)
    case target
    when ::Business
      if target.oidc_provider.present?
        idm_oidc_revoke_enterprise_path(target)
      else
        idm_saml_revoke_enterprise_path(target)
      end
    when ::Organization
      org_idm_saml_revoke_path(target)
    else
      raise ArgumentError, "Unexpected target type: #{target.class.name}"
    end
  end

  # Checks whether a user is logged in and is the same user as the user who is performing SSO.
  #
  # user - The user who is performing SSO.
  #
  # Returns Boolean.
  def same_user_logged_in?(user)
    return false unless user
    return false unless logged_in?
    return false if current_user.id != user.id

    true
  end

  private

  def get_modal_url(target)
    case target
    when ::Organization
      org_idm_sso_modal_path(target)
    when ::Business
      business_idm_sso_modal_enterprise_path(target)
    end
  end

  def get_session_url(target)
    case target
    when ::Organization
      org_idm_sso_status_path(target, format: :json, fakestate: params[:fakestate])
    when ::Business
      business_idm_sso_status_enterprise_path(target, format: :json, fakestate: params[:fakestate])
    end
  end

end
