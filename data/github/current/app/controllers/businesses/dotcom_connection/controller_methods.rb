# typed: true
# frozen_string_literal: true

module Businesses::DotcomConnection::ControllerMethods
  extend ActiveSupport::Concern
  include GitHub::Memoizer
  extend T::Helpers

  requires_ancestor { Businesses::BusinessController }

  # The set of feature keywords MUST match DotcomConnection#current_features and #apply_pending_feature_changes
  FEATURE_ADDED_MESSAGES = {
    "contributions"    => "Contributions sharing with #{GitHub.dotcom_host_name_string} enabled.",
    "search"           => "Search on #{GitHub.dotcom_host_name_string} enabled.",
    "private_search"   => "Private repositories in the connected organization will be included in the #{GitHub.dotcom_host_name_string} search results.",
    "content_analysis" => "Content analysis enabled.",
    "content_analysis_notifications" => "Content analysis notifications enabled.",
    "license_usage_sync" => "User license usage will be uploaded to your Enterprise Cloud account.",
    "actions_download_archive" => "Utilizing actions from #{GitHub.dotcom_host_name_string} in workflow runs is enabled.",
    "usage_metrics" => "Usage metrics enabled.",
    "dependabot_access" => "Dependabot's access to public #{GitHub.dotcom_host_name_string} repositories has been expanded."
  }

  FEATURE_REMOVED_MESSAGES = {
    "contributions"    => "Contributions sharing with #{GitHub.dotcom_host_name_string} disabled.",
    "search"           => "Search on #{GitHub.dotcom_host_name_string} disabled.",
    "private_search"   => "Private repositories in the connected organization will not be included in the #{GitHub.dotcom_host_name_string} search results.",
    "content_analysis" => "Content analysis disabled.",
    "content_analysis_notifications" => "Content analysis notifications disabled.",
    "license_usage_sync" => "User license usage will not be uploaded to your Enterprise Cloud account.",
    "actions_download_archive" => "Utilizing actions from #{GitHub.dotcom_host_name_string} in workflow runs is disabled.",
    "usage_metrics" => "Usage metrics disabled.",
    "dependabot_access" => "Dependabot's access to public #{GitHub.dotcom_host_name_string} repositories has been restricted."
  }

  private

  # Private: URL to dotcom for permissions upgrade/downgrade if any is needed,
  #          or just to instrument the feature change if not. We send across
  #          the feature(s) and whether they are being enabled as parameters,
  #          which will be used for instrumentation when permission changes
  #          aren't needed.
  def dotcom_permission_upgrade_and_instrument_url(features_added: [], features_removed: [])
    result = dotcom_connection.update_permissions
    if !result["success"]
      dotcom_connection.clear_pending_features
      flash[:error] = "There was an error updating the GitHub Connect settings."
      admin_settings_dotcom_connection_enterprise_path(GitHub.global_business)
    else
      # 'path' below will be where we get redirected to when we hit EnterpriseInstallationController#upgrade
      # When we need to implement permission changes, it'll be result["url"], which is where we get sent
      # after clicking the confirmation button. When we don't need permission changes, we will just get
      # redirected straight back to admin_settings_dotcom_connection_enterprise_path as soon as we
      # instrument the feature changes.
      path = result["url"] || admin_settings_dotcom_connection_enterprise_path(GitHub.global_business)
      query_args = {
        state: generate_random_state,
        features_added: features_added,
        features_removed: features_removed,
        return_to: admin_settings_change_complete_enterprise_url(helpers.this_business),
      }
      url = Addressable::URI.new(
        scheme: GitHub.dotcom_host_protocol,
        host: GitHub.dotcom_host_name,
        path: path,
        query: query_args.to_query,
      )
      url.to_s
    end
  end

  def apply_pending_config_changes
    change_messages = (
      dotcom_connection.added_features.map   { |f| FEATURE_ADDED_MESSAGES[f] } +
      dotcom_connection.removed_features.map { |f| FEATURE_REMOVED_MESSAGES[f] }
    ).join(" ")
    dotcom_connection.apply_pending_feature_changes(current_user)
    flash[:notice] = change_messages if change_messages.present?
  end

  def redirect_error(error = nil)
    error ||= GitHub::Connect::ServiceUnavailableError.new("API Inaccessible")
    Failbot.report(error, { app: "dotcom-connection" })
    GitHub.stats.increment("dotcom_connection.error") if GitHub.enterprise?
    flash[:error] ||= "Failed to connect to #{GitHub.dotcom_host_name_string}, please try again."
    redirect_to admin_settings_dotcom_connection_enterprise_path(GitHub.global_business)
  end

  memoize def dotcom_connection
    result = ::DotcomConnection.new
    result.actor = current_user
    result
  end

  def dotcom_enterprise_installation_url(token, state)
    new_enterprise_installation_url(host: GitHub.dotcom_host_name, protocol: GitHub.dotcom_host_protocol, state: state, token: token)
  end

  def generate_random_state
    session[:github_connect_state] = SecureRandom.hex(8)
  end

  def current_state
    session[:github_connect_state]
  end

  def state_matches_session?
    params[:state].present? && SecurityUtils.secure_compare(params[:state], session.delete(:github_connect_state))
  end
end
