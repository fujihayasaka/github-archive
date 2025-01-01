# typed: true
# frozen_string_literal: true

class Businesses::Settings::DotcomConnectionView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  def dotcom_temporary_token_expires_at
    dotcom_connection.temp_authentication_token_expires_at
  end

  def require_reconnect?
    dotcom_connection.require_reconnect?
  end

  def disconnected_features_message
    msg = []
    if GitHub.dotcom_search_enabled? # || GitHub.dotcom_private_search_enabled?
      msg << "searching content on GitHub.com"
    end
    if GitHub.dotcom_contributions_enabled?
      msg << "sharing Enterprise contribution counts on their GitHub.com profiles"
    end
    if GitHub.dependency_graph_enabled? && GitHub.ghe_content_analysis_enabled?
      msg << "scanning for vulnerable dependencies"
    end
    if GitHub.dependabot_enabled? && GitHub.ghe_dependabot_access_to_dotcom_enabled?
      msg << "easily fixing vulnerabilities in open source dependencies"
    end

    if GitHub.actions_enabled? && GitHub.dotcom_download_actions_archive_enabled?
      msg << "using actions from GitHub.com in their workflows"
    end

    if msg.any?
      "Disabling will prevent users from #{msg.to_sentence}."
    else
      ""
    end
  end

  def can_use_proxima?
    GitHub.github_connect_ghe_com_enabled?
  end

  def can_use_download_actions?
    GitHub.actions_enabled? && !can_use_proxima?
  end

  def dotcom_download_actions_archive_choices
    [
      %w[Enabled true],
      %w[Disabled false],
    ]
  end

  def dotcom_search_choices
    [
      %w[Enabled true],
      %w[Disabled false],
    ]
  end

  def dotcom_private_search_choices
    [
      %w[Enabled true],
      %w[Disabled false],
    ]
  end

  def dotcom_contributions_choices
    [
      %w[Enabled true],
      %w[Disabled false],
    ]
  end

  def ghe_usage_metrics_choices
    [
      %w[Enabled true],
      %w[Disabled false],
    ]
  end

  def ghe_vulnerabilities_choices
    {
      "enabled_with_notifications" => "Enable with notifications",
      "enabled_without_notifications" => "Enable without notifications",
      "disabled" => "Disable",
    }
  end

  def current_ghe_vulnerabilities_value
    if GitHub.ghe_content_analysis_enabled?
      if GitHub.ghe_content_analysis_notifications_enabled?
        "enabled_with_notifications"
      else
        "enabled_without_notifications"
      end
    else
      "disabled"
    end
  end

  def current_ghe_vulnerabilities_label
    ghe_vulnerabilities_choices.fetch(current_ghe_vulnerabilities_value)
  end

  def license_usage_sync_choices
    [
      %w[Enabled true],
      %w[Disabled false],
    ]
  end

  def owner_type
    type = dotcom_connection.owner_type
    case type
    when "org"
      "organization"
    when "business"
      "enterprise"
    else
      type
    end
  end

  def owner_identifier
    dotcom_connection.owner_identifier
  end

  def dotcom_profile_url
    dotcom_connection.dotcom_profile_url
  end

  def dotcom_contributions_change_path
    GitHub.dotcom_contributions_configurable? ? urls.admin_settings_update_dotcom_connection_enterprise_path(GitHub.global_business, "contributions") : "#"
  end

  def dotcom_contributions_request_url
    return "#" unless GitHub::Enterprise.license.valid?
    GitHub.enterprise_web_url +
      "/connection/access?feature=contributions" +
      "&version=" + GitHub.version_number +
      "&license_hash=" + Digest::SHA256.base64digest(GitHub::Enterprise.license.license_data)
  end

  def dotcom_connection_status
    @dotcom_connection_status ||= dotcom_connection.check_status
  end

  def dotcom_connected?
    dotcom_connection_status == :connected
  end

  def license_usage_sync_config_visible?
    dotcom_connection.owner_type == "business"
  end

  def usage_metrics_config_visible?
    !can_use_proxima?
  end

  def human_readable_license_usage_sync_interval
    UploadEnterpriseServerUserAccountsJob.human_readable_schedule_interval
  end

  private

  def dotcom_connection
    @dotcom_connection ||= ::DotcomConnection.new
  end
end
