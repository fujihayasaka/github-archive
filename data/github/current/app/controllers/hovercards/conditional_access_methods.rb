# typed: false
# frozen_string_literal: true
module Hovercards::ConditionalAccessMethods
  def ip_allowlist_enforce(target)
    return head :forbidden unless request.xhr?
    render "hovercards/ip_allowlist", locals: { target: target, type: target_type }, layout: false
    set_html_safe
  end

  def external_conditional_access_policy_enforce(target)
    return head :forbidden unless request.xhr?

    business = case target
    when Business
      target
    when Organization
      target.business
    when User
      target.enterprise_managed_business
    end

    render "hovercards/external_conditional_access", locals: { target: business }, layout: false
    set_html_safe
  end

  # opted out to be handled manually in show action to render a custom SAML SSO interstitial
  def require_active_external_identity_session?
    return false if action_name == "show"
    super
  end

  def two_factor_enforce(target)
    return head :forbidden unless request.xhr?
    render "hovercards/2fa", locals: { target: target, type: target_type }, layout: false
    set_html_safe
  end
end
