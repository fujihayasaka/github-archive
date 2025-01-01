# typed: true
# frozen_string_literal: true

require "github/connect/kv"

# DotcomConnection represents a GitHub Connection from this Enterprise Server
# instance to GitHub.com, storing all the information needed to make API calls
# over the bridge.
class DotcomConnection
  include Instrumentation::Model

  class UploadFailed < StandardError; end
  class UploadProcessingFailed < StandardError; end

  # Time in which the admin must complete the connection (before the temporary
  # token expires), measured both in the Enterprise Server (see below) and in
  # dotcom (see EnterpriseInstallationsController#create)
  TEMP_TOKEN_TTL = 5.minutes

  attr_accessor :actor

  def event_context(prefix: event_prefix)
    {
      prefix.to_sym => true,
    }
  end

  def event_payload
    {
      dotcom_connection: self,
      actor: actor,
    }
  end

  # enterprise_server_version is only set for post-EAP installations.
  # This will indicate to admins of EAP installations that they need to reconnect.
  def require_reconnect?
    enterprise_server_version.blank?
  end

  def authentication_token?
    !!authentication_token
  end

  def authenticator
    @github_connect_authenticator ||= GitHub::Connect::Authenticator.new
  end

  def authenticator_with_license
    @github_connect_authenticator_license ||= begin
      auth = GitHub::Connect::Authenticator.new
      auth.license_file_path = GitHub.license_path
      auth
    end
  end

  # Public: Effectively establishes the GitHub Connection to dotcom
  def create(token, app_id = nil, installation_id = nil, client_secret = nil)
    self.temp_authentication_token = nil
    self.authentication_token = token
    self.client_secret = client_secret
    Connect::KV.store.set("ghe-install-iss", app_id) if app_id
    Connect::KV.store.set("ghe-install-id", installation_id) if installation_id
    Connect::KV.store.set("ghe-install-version", GitHub.version_number)
    instrument :create
  end

  # Public: Disconnects this Enterprise Instance from dotcom
  def destroy
    remove_enterprise_installation
    reset_tokens
    Connect::KV.store.del("ghe-install-key")
    Connect::KV.store.del("ghe-install-client-secret")
    Connect::KV.store.del("ghe-install-upload-id")
    DotcomUser.update_all(token: nil)
    DotcomUser.destroy_all
    instrument :destroy
  end

  def remove_enterprise_installation
    authentication_token? && authenticator.remove_enterprise_installation
  end

  def reset_tokens
    self.temp_authentication_token = nil
    self.authentication_token = nil
    self.client_secret = nil
  end

  def generate_keys
    private_key = authenticator_with_license.generate_keys
    Connect::KV.store.set("ghe-install-key", private_key)
    private_key
  end

  def request_authentication_token
    if token = authenticator_with_license.request_authentication_token
      self.temp_authentication_token = token
      return token
    end
    nil
  end

  # Public: Requests information about this installation from dotcom
  #         and persists what we need
  def update_application_info
    info = authenticator.request_oauth_application
    Connect::KV.store.set("ghe-install-owner-type", info["owner_type"])
    Connect::KV.store.set("ghe-install-owner-identifier", info["owner_identifier"])
  end

  # Public: A unique identifier for this server installation
  def server_id
    Connect::KV.store.get("ghe-install-server-id").value { nil } || reset_server_id
  end

  # Public: Reset the unique identifier for this server installation
  def reset_server_id
    id = SecureRandom.uuid
    ActiveRecord::Base.connected_to(role: :writing) do
      Connect::KV.store.set("ghe-install-server-id", id)
    end
    id
  end

  # Public: Reset all GitHub Connect information back to a clean unconfigured state.
  #         This only resets the local state and does not change anything on dotcom.
  #         This is only useful for testing and used by backup-utils when restoring.
  #
  # user - user that will be used to apply the changes (e.g., current_user)
  def reset(user)
    reset_tokens
    reset_server_id
    DotcomUser.update_all(token: nil)
    DotcomUser.destroy_all
    Connect::KV.store.set("ghe-install-requested-features", "")
    apply_pending_feature_changes(user)
    Connect::KV.store.del("ghe-install-key")
    Connect::KV.store.del("ghe-install-iss")
    Connect::KV.store.del("ghe-install-id")
    Connect::KV.store.del("ghe-install-owner-type")
    Connect::KV.store.del("ghe-install-owner-identifier")
  end

  # Public: ID of Integration (aka GitHub App) on dotcom
  def installation_issuer
    Connect::KV.store.get("ghe-install-iss").value { nil }
  end

  # Public: ID of the IntegrationInstallation on dotcom
  def installation_id
    Connect::KV.store.get("ghe-install-id").value { nil }
  end

  # Public: Version of Enterprise Server used when the connection was created.
  #
  # Useful for upgrading when breaking changes require user or API action
  # (see #require_reconnect for an example)
  def enterprise_server_version
    Connect::KV.store.get("ghe-install-version").value { nil }
  end

  # Public: Private key (PEM-encoded) used to build the bearer token passed
  #         in the "Authorization: Bearer <jwt>" header when the authentication
  #         token needs to be refreshed
  def bearer_encoding_key
    Connect::KV.store.get("ghe-install-key").value { nil }
  end

  # Public: Server-to-Server token passed in the authentication header
  # ("Authorization: token <authentication_token>") on app-scoped (as opposed to
  # user-scoped) requests to dotcom made over this connection.
  #
  # This token is what confirms that a GitHub Connection has been made.
  #
  # Returns String.
  def authentication_token
    Connect::KV.store.get("ghe-install-token").value { nil }
  end

  # Public: Client id for OAuth operations from the connection.
  def client_secret
    Connect::KV.store.get("ghe-install-client-secret").value { nil }
  end

  # Public: Server-to-Server token passed in the authentication header
  # ("Authorization: token <authentication_token>") on app-scoped (as opposed to
  # user-scoped) requests to dotcom made over this connection.
  #
  # This token is what confirms that a GitHub Connection has been made,
  # skipping any query caches.
  #
  # Returns String.
  def uncached_authentication_token
    Connect::KV.store.connection.uncached { authentication_token }
  end

  # Public: Updates or deletes the server-to-server token
  def authentication_token=(token)
    if token.nil?
      Connect::KV.store.del("ghe-install-token")
    else
      Connect::KV.store.set("ghe-install-token", token)
    end
  end

  # Public: Updates or deletes the client secret
  def client_secret=(secret)
    if secret.nil?
      Connect::KV.store.del("ghe-install-client-secret")
    else
      Connect::KV.store.set("ghe-install-client-secret", secret)
    end
  end

  # Public: Temporary token generated when the admin clicks "GitHub Connect".
  #         It self-destructs after time specified by TEMP_TOKEN_TTL
  def temp_authentication_token
    Connect::KV.store.get("ghe-install-temp-token").value { nil }
  end

  # Public: How much time we have left before the temporary token expires
  def temp_authentication_token_expires_at
    Connect::KV.store.ttl("ghe-install-temp-token").value { nil }
  end

  # Public: Updates (using the time-to-live set on TEMP_TOKEN_TTL) or deletes
  #         the temporary token
  def temp_authentication_token=(token)
    if token.nil?
      Connect::KV.store.del("ghe-install-temp-token")
    else
      Connect::KV.store.set("ghe-install-temp-token", token, expires: TEMP_TOKEN_TTL.from_now)
    end
  end

  # Public: Returns the identifier of the enterprise installation owner on GitHub.com
  def owner_identifier
    # prefer `owner-identifier`
    identifier = Connect::KV.store.get("ghe-install-owner-identifier").value { nil }
    return identifier if identifier

    # default to legacy `organization-login`
    Connect::KV.store.get("ghe-install-organization-login").value { nil }
  end

  # Public: Type of GitHub.com entity that we are connected to
  #
  # Returns: One of "org" or "business"
  def owner_type
    Connect::KV.store.get("ghe-install-owner-type").value { nil } || "org"
  end

  # Public: Returns the URL to the profile/home page of whatever we linked
  #         against (an organization or a business) on GitHub.com
  def dotcom_profile_url
    case owner_type
    when "business"
      UrlHelpers.enterprise_url(owner_identifier, protocol: GitHub.dotcom_host_protocol, host: GitHub.dotcom_host_name)
    else
      UrlHelpers.user_url(owner_identifier, protocol: GitHub.dotcom_host_protocol, host: GitHub.dotcom_host_name)
    end
  end

  # Public: Returns the URL to the enterprise licensing page on GitHub.com if we linked to a business
  def dotcom_enterprise_licensing_url
    return unless owner_type == "business"
    dotcom_profile_url + "/enterprise_licensing"
  end

  # Public: Registers that an admin wants to enable a config (so permissions get
  #         properly upgraded and, once it happens, the config is enabled)
  #
  # feature - string for the feature (one listed in #current_features)
  def add_feature(feature)
    features = requested_features + [feature]
    Connect::KV.store.set("ghe-install-requested-features", features.join(","))
  end

  # Public: Registers that an admin wants to disable a config (so permissions get
  #         properly downgraded and, once it happens, the config is disabled)
  #
  # feature - string for the feature (one listed in #current_features)
  def remove_feature(feature)
    features = requested_features - [feature]
    Connect::KV.store.set("ghe-install-requested-features", features.join(","))
  end

  # Public: Clears any registered request for a config to be enabled/disabled,
  #         so previous requests do not affect a new/future one.
  def clear_pending_features
    Connect::KV.store.del("ghe-install-requested-features")
  end

  # Public: Changes registered via #add_feature (that haven't been applied yet)
  def added_features
    requested_features - current_features
  end

  # Public: Changes registered via #remove_feature (that haven't been applied yet)
  def removed_features
    current_features - requested_features
  end

  # Public: Checks on dotcom if the instance needs a permissions
  #         upgrade/downgrade for the requested features
  #
  # Returns the path for the upgrade/downgrade request, nil if permissions are good
  def update_permissions
    authenticator.request_permissions(requested_features)
  end

  # Public: Applies any pending feature configuration changes
  #
  # Callers should first ensure that permissions are properly set
  #
  # user - user that will be used to apply the changes (e.g., current_user)
  #
  def apply_pending_feature_changes(user)
    added = added_features
    removed = removed_features

    GitHub.enable_dotcom_contributions(user)               if added.include? "contributions"
    GitHub.enable_dotcom_search(user)                      if added.include? "search"
    GitHub.enable_dotcom_private_search(user)              if added.include? "private_search"
    GitHub.enable_dotcom_user_license_usage_upload(user)   if added.include? "license_usage_sync"
    GitHub.enable_ghe_content_analysis(user)               if added.include? "content_analysis"
    GitHub.enable_ghe_content_analysis_notifications(user) if added.include? "content_analysis_notifications"
    GitHub.enable_dotcom_download_actions_archive(user)    if added.include? "actions_download_archive"
    GitHub.enable_ghe_usage_metrics(user)                  if added.include? "usage_metrics"
    GitHub.enable_ghe_dependabot_access_to_dotcom(user)    if added.include? "dependabot_access"

    GitHub.disable_dotcom_contributions(user)               if removed.include? "contributions"
    GitHub.disable_dotcom_search(user)                      if removed.include? "search"
    GitHub.disable_dotcom_private_search(user)              if removed.include? "private_search"
    GitHub.disable_dotcom_user_license_usage_upload(user)   if removed.include? "license_usage_sync"
    GitHub.disable_ghe_content_analysis(user)               if removed.include? "content_analysis"
    GitHub.disable_ghe_content_analysis_notifications(user) if removed.include? "content_analysis_notifications"
    GitHub.disable_dotcom_download_actions_archive(user)    if removed.include? "actions_download_archive"
    GitHub.disable_ghe_usage_metrics(user)                  if removed.include? "usage_metrics"
    GitHub.disable_ghe_dependabot_access_to_dotcom(user)    if removed.include? "dependabot_access"

    clear_pending_features

    if added.include? "license_usage_sync"
      UploadEnterpriseServerUserAccountsJob.perform_later
    end

    if added.include? "usage_metrics"
      UploadConnectMetricsJob.perform_later
    end

    if added.include?("content_analysis") || added.include?("content_analysis_notifications")
      EnterpriseAdvisoryDatabaseSyncJob.perform_later
    end

    # If content_analysis was added or removed run a background job to sync Security Configuration states:
    if added.include?("content_analysis") || added.include?("content_analysis_notifications") ||
      removed.include?("content_analysis") || removed.include?("content_analysis_notifications")
      EnterpriseUpdateSecurityConfigurationApplicationsJob.perform_later
    end

    # Always kick off the UpdateConnectInstallationInfo job to ensure we have the latest info as some of these settings
    # don't result in a permissions change so we won't know until the weekly job next runs.
    UpdateConnectInstallationInfo.perform_later
  end

  # Public: Checks the current status of the current GitHub-to-GitHub
  # connection, connecting to dotcom if necessary.
  #
  # Returns one of:
  #   :not_connected - initial state
  #   :unfinished    - admin started connecting, but didn't finish it (we have a temp token)
  #   :unverifiable  - we believe to be connected, but can't talk to dotcom to check
  #   :disconnected  - we believe to be connected, but dotcom says we aren't
  #   :connected     - we are connected and dotcom confirms that
  def check_status
    return :unfinished if temp_authentication_token
    return :not_connected unless authentication_token?

    authenticator = GitHub::Connect::Authenticator.new
    application = authenticator.request_oauth_application
    return :unverifiable if application.nil?
    application["client_id"] ? :connected : :disconnected
  rescue GitHub::Connect::Authenticator::ConnectionError,
         GitHub::Connect::Authenticator::AuthenticationError
    :unverifiable
  end

  # Public: Checks the current status of the current GitHub-to-GitHub connection.
  #
  # Returns a boolean indicating whether the instance is connected to Cloud or not.
  def is_connected?
    check_status == :connected
  end

  # Public: Returns license and instance information to be sent to Enterprise
  # Cloud for business user license validation.
  #
  # include_users          - Setting this to false will omit the user section in the output.
  # include_full_user_info - Setting this to true will include additional personal user information in the output.
  # encrypt_users          - Encrypt the user section in the output if included.
  # include_instance       - Setting this to false will omit the instance section in the output.
  #
  # Returns a Hash.
  def license_info(include_users: true, include_full_user_info: false, encrypt_users: true, include_instance: true)
    out = { version: 1 }
    out[:instance] = authenticator_with_license.authentication_request_info if include_instance
    if include_users
      gen = UserLicenseListGenerator.new(include_full_user_info: include_full_user_info)
      out[:users] = if encrypt_users
        encrypt_license_info(gen.run)
      else
        gen.run
      end
    end
    out
  end

  def upload_license_info(data = license_info)
    return unless owner_type == "business"
    Connect::KV.store.del("ghe-install-upload-id")
    result = authenticator_with_license.upload_license_usage(owner_identifier, data.to_json)
    upload_id = result["id"]
    raise UploadFailed unless upload_id
    Connect::KV.store.set("ghe-install-upload-id", upload_id.to_s)
    result = authenticator_with_license.complete_license_info_upload(owner_identifier, upload_id)
    raise UploadProcessingFailed unless result["sync_state"]

    instrument :upload_license_usage

    {
      id: upload_id,
      state: result["sync_state"],
      updated_at: result["updated_at"],
    }
  end

  def license_info_upload_status
    return if owner_type != "business"
    upload_id = Connect::KV.store.get("ghe-install-upload-id").value { nil }
    return unless upload_id
    result = authenticator.license_usage_upload_info(owner_identifier, upload_id)
    {
      id: upload_id,
      state: result["sync_state"],
      updated_at: result["updated_at"],
    }
  end

  def upload_connect_metrics
    result = authenticator_with_license.upload_connect_metrics

    instrument :upload_usage_metrics if result[:sent] && !result[:sent].empty?

    result
  end

  # Features currently enabled on connection settings
  def current_features
    features = []
    features << "contributions"       if GitHub.dotcom_contributions_enabled?
    features << "search"              if GitHub.dotcom_search_enabled?
    features << "private_search"      if GitHub.dotcom_private_search_enabled?
    features << "license_usage_sync"  if GitHub.dotcom_user_license_usage_upload_enabled?
    features << "content_analysis"    if GitHub.ghe_content_analysis_enabled?
    features << "content_analysis_notifications" if GitHub.ghe_content_analysis_notifications_enabled?
    features << "actions_download_archive" if GitHub.dotcom_download_actions_archive_enabled?
    features << "usage_metrics"       if GitHub.ghe_usage_metrics_enabled?
    features << "dependabot_access"   if GitHub.ghe_dependabot_access_to_dotcom_enabled?
    features
  end

  private

  # Private: encrypts data for the license info output
  def encrypt_license_info(data)
    authenticator_with_license.encrypt_message(data.to_json)
  end

  # Private: Features the admin wants to have (but may need permissions up/downgrade)
  #
  # Defaults to the current features
  def requested_features
    value = Connect::KV.store.get("ghe-install-requested-features").value { nil }
    value&.split(",") || current_features
  end
end
