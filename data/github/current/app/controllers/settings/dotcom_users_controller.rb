# typed: true
# frozen_string_literal: true

class Settings::DotcomUsersController < ApplicationController
  before_action :login_required
  before_action :require_dotcom_connection_enabled
  before_action :ensure_dotcom_user_connection_enabled
  before_action(
    :require_connected_instance,
    only: [:create, :destroy, :callback, :change_contributions],
  )
  before_action :ensure_unified_connection_enabled, only: [:show]

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:callback]

  def show
    SecureHeaders.append_content_security_policy_directives(
      request,
      form_action: ["#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}"],
      preserve_schemes: GitHub.dotcom_host_protocol != "https",
    )

    render "settings/dotcom_users/show"
  end

  def create
    redirect_to dotcom_user_connection_url

  rescue GitHub::Connect::Authenticator::ConnectionError
    redirect_error
  end

  def destroy
    if dotcom_user.destroy
      redirect_to settings_dotcom_user_path, notice: "Successfully disconnected your #{GitHub.dotcom_host_name_string} account."
    else
      redirect_error
    end
  rescue GitHub::Connect::Authenticator::ConnectionError,
         GitHub::Connect::ApiError
    redirect_error
  end

  def callback # rubocop:todo GitHub/UseRestfulActions
    if state_matches_session?
      token = github_connect_authenticator.request_oauth_token(params[:code], oauth_info, dotcom_connection.client_secret)
      dotcom_user.token = token
      dotcom_user.login = user_login(token)
      ActiveRecord::Base.connected_to(role: :writing) do
        dotcom_user.save
      end
      redirect_to settings_dotcom_user_path, notice: "Successfully connected with your #{GitHub.dotcom_host_name_string} account."
    else
      redirect_error
    end
  rescue GitHub::Connect::Authenticator::ConnectionError
    redirect_error
  end

  def change_contributions # rubocop:todo GitHub/UseRestfulActions
    bool_value = params[:user][:show_enterprise_contribution_counts_on_dotcom] == "1"
    if !bool_value && !dotcom_user.remove_user_contributions
      redirect_error
    else
      EnterpriseContribution.push_user_contributions_history(current_user) if bool_value
      current_user.show_enterprise_contribution_counts_on_dotcom = bool_value

      redirect_to settings_dotcom_user_path,
        notice: <<-END
          Your contribution counts have been
          #{ bool_value ? "updated on" : "removed from" }
          your #{GitHub.dotcom_host_name_string} profile and will
          #{"not" unless bool_value}
          be sent from now on.
        END
    end
  rescue GitHub::Connect::ConnectionError,
         GitHub::Connect::ApiError
    redirect_error
  end

  private

  def dotcom_user # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @dotcom_user ||= DotcomUser.for(current_user)
  end

  def dotcom_connection # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @dotcom_connection ||= ::DotcomConnection.new
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

  def oauth_info # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @oauth_info ||= github_connect_authenticator.request_oauth_application
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

  # CAP is not needed - these controllers are for syncing GHES contriubtions to a dotcom profile for the GHES user
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
