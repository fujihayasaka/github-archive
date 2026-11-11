# typed: strict
# frozen_string_literal: true

# Provides redirect-back-to-VS-Code support for Copilot signup controllers.
#
# When a user initiates a Copilot plan upgrade from VS Code, VS Code opens
# the signup URL with a `return_to` parameter pointing at vscode.dev.
# This concern captures that URL in the session and, after the upgrade
# succeeds, redirects the user back so VS Code can refresh its state.
module Copilot::VscodeRedirectConcern
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  VSCODE_REDIRECT_HOSTS = T.let(
    %w[vscode.dev insiders.vscode.dev].freeze,
    T::Array[String],
  )

  private

  # Attempts to redirect the user to the VS Code return URL stored in the
  # session. Returns `true` when a redirect was performed so the caller can
  # short-circuit, `false` otherwise.
  sig { params(fallback: T.nilable(String)).returns(T::Boolean) }
  def redirect_to_vscode_if_needed(fallback: nil)
    return false unless current_user.feature_flag_enabled?(:copilot_vscode_upgrade_redirect, default: false)

    url = session.delete(:copilot_vscode_return_to)
    return false if url.blank?

    safe_redirect_to(
      url,
      fallback: fallback || copilot_immersive_path,
      allow_hosts: VSCODE_REDIRECT_HOSTS,
      allow_query: true,
      allow_fragment: true,
    )
    true
  end

  # Appends `vscode.dev` hosts to the CSP `form-action` directive so the
  # browser allows the post-signup redirect to VS Code.  Chrome enforces
  # `form-action` against redirect targets from form submissions, so the
  # page that renders the signup form needs vscode.dev in its CSP.
  sig { void }
  def add_vscode_form_action_csp
    return unless session[:copilot_vscode_return_to].present?

    hosts = VSCODE_REDIRECT_HOSTS.map { |h| "https://#{h}" }
    SecureHeaders.append_content_security_policy_directives(request, { form_action: hosts })
  end

  # Stores a validated VS Code return URL from `params[:return_to]` into the
  # session so it survives across the multi-step signup flow.
  sig { void }
  def set_vscode_return_to
    return unless params[:return_to].present?

    url = params[:return_to].to_s
    parsed = Addressable::URI.parse(url)
    return unless parsed.scheme == "https"
    return unless VSCODE_REDIRECT_HOSTS.include?(parsed.host)

    session[:copilot_vscode_return_to] = url
  rescue Addressable::URI::InvalidURIError
    # Ignore malformed URLs silently
  end
end
