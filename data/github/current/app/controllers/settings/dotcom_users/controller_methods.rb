# typed: true
# frozen_string_literal: true

module Settings::DotcomUsers::ControllerMethods
  extend ActiveSupport::Concern
  include GitHub::Memoizer
  extend T::Helpers

  requires_ancestor { ApplicationController }

  private

  memoize def dotcom_user
    DotcomUser.for(current_user)
  end

  memoize def dotcom_connection
    ::DotcomConnection.new
  end

  def github_connect_authenticator
    dotcom_connection.authenticator
  end

  def require_connected_instance
    case dotcom_connection.check_status
    when :not_connected, :unfinished
      render_404
    when :unverifiable, :disconnected
      redirect_to settings_dotcom_user_path, flash: { error: "Failed to connect to #{GitHub.dotcom_host_name_string}. Please try again later, or ask your administrator to check the GitHub Connect status." }
    end
  end

  def ensure_dotcom_user_connection_enabled
    render_404 unless GitHub.dotcom_user_connection_enabled?
  end

  memoize def oauth_info
    github_connect_authenticator.request_oauth_application
  end

  def oauth_client_id
    oauth_info["client_id"]
  end

  def oauth_scope
    GitHub::Connect::Authenticator::OAUTH_SCOPES.join(",")
  end

  def user_login(token)
    github_connect_authenticator.request_oauth_user_info(token)["login"]
  end

  def generate_random_state
    session[:github_connect_user_state] = SecureRandom.hex(8)
  end

  def state_matches_session?
    !params[:state].blank? && params[:state] == session.delete(:github_connect_user_state)
  end

  def redirect_error
    Failbot.report(GitHub::Connect::ServiceUnavailableError.new("API Inaccessible"), { app: "dotcom-user-connection" })
    GitHub.stats.increment("dotcom_user_connection.error") if GitHub.enterprise?
    redirect_to settings_dotcom_user_path, flash: { error: "Failed to connect with your #{GitHub.dotcom_host_name_string} account. Please try again later." }
  end

  def dotcom_user_connection_url
    oauth_request_url(host: GitHub.dotcom_host_name, protocol: GitHub.dotcom_host_protocol, scope: oauth_scope, client_id: oauth_client_id, state: generate_random_state)
  end

  # CAP is not needed - these controllers are for syncing GHES contributions to a dotcom profile for the GHES user
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ensure_unified_connection_enabled
    if !GitHub::Connect.unified_contributions_enabled? &&
        !GitHub::Connect.unified_private_search_enabled?
      render_404
    end
  end
end
