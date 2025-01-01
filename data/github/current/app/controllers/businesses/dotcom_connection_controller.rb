# typed: true
# frozen_string_literal: true

class Businesses::DotcomConnectionController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :require_dotcom_connection_enabled
  before_action :require_actions_enabled, only: :change_actions_download_archive

  before_action :add_csp_exceptions, only: :index
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:complete]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:change_complete]

  CSP_EXCEPTIONS = {
    form_action: ["#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}"],
    preserve_schemes: GitHub.dotcom_host_protocol != "https",
  }.freeze

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

  def index
    render "businesses/settings/dotcom_connection", locals: {
      slug: this_business.slug,
    }
  end

  def create
    dotcom_connection.generate_keys
    if token = dotcom_connection.request_authentication_token
      redirect_to dotcom_enterprise_installation_url(token, generate_random_state)
    else
      redirect_error GitHub::Connect::Authenticator::AuthenticationError.new("invalid authentication token received")
    end
  rescue GitHub::Connect::Authenticator::ConnectionError => e
    redirect_error e
  rescue GitHub::Connect::Authenticator::AuthenticationError => e
    redirect_error e
  end

  def resume # rubocop:todo GitHub/UseRestfulActions
    if token = dotcom_connection.temp_authentication_token
      redirect_to dotcom_enterprise_installation_url(token, current_state)
    else
      redirect_error
    end
  end

  def complete # rubocop:todo GitHub/UseRestfulActions
    if dotcom_connection.temp_authentication_token && state_matches_session?
      ActiveRecord::Base.connected_to(role: :writing) do
        # The token is always refreshed before sending a request to GitHub.com
        # (see GitHub::Connect.github_app_authenticated) so it doesn't really matter the token we store when
        # connecting for the first time.
        # This makes it possible to receive the redirect after Connecting to GitHub.com without sending the
        # token as part of the URL.
        dotcom_connection.create "needs-refresh", params[:app_id], params[:installation_id], params[:client_secret]
        dotcom_connection.update_application_info
      end
      redirect_to admin_settings_dotcom_connection_enterprise_path(GitHub.global_business), notice: "Successfully connected your Enterprise instance to #{GitHub.dotcom_host_name_string}."
    else
      redirect_error
    end
  rescue GitHub::Connect::Authenticator::AuthenticationError => error
    redirect_error error
  end

  def destroy
    dotcom_connection.destroy
    GitHub.disable_dotcom_search(current_user)
    GitHub.disable_dotcom_contributions(current_user)
    GitHub.disable_dotcom_user_license_usage_upload(current_user)
    GitHub.disable_ghe_content_analysis(current_user)
    GitHub.disable_ghe_content_analysis_notifications(current_user)
    GitHub.disable_ghe_usage_metrics(current_user)
    GitHub.disable_ghe_dependabot_access_to_dotcom(current_user)
    redirect_to admin_settings_dotcom_connection_enterprise_path(GitHub.global_business), notice: "Successfully disconnected your Enterprise instance from #{GitHub.dotcom_host_name_string}."
  rescue GitHub::Connect::Authenticator::ConnectionError
    redirect_error
  rescue GitHub::Connect::Authenticator::AuthenticationError
    dotcom_connection.reset_tokens
    GitHub.disable_dotcom_search(current_user)
    GitHub.disable_dotcom_contributions(current_user)
    GitHub.disable_dotcom_user_license_usage_upload(current_user)
    GitHub.disable_ghe_content_analysis(current_user)
    GitHub.disable_ghe_content_analysis_notifications(current_user)
    GitHub.disable_ghe_usage_metrics(current_user)
    GitHub.disable_ghe_dependabot_access_to_dotcom(current_user)
    redirect_error
  end

  def change_search # rubocop:todo GitHub/UseRestfulActions
    val = params[:public_search_value]

    if val == "true"
      features_added = ["search"]
      features_removed = []
      dotcom_connection.clear_pending_features
      dotcom_connection.add_feature(features_added.first)
    elsif val == "false"
      features_added = []
      features_removed = %w(search private_search)
      dotcom_connection.clear_pending_features
      features_removed.each { |f| dotcom_connection.remove_feature(f) }
    end

    redirect_to dotcom_permission_upgrade_and_instrument_url(features_added: features_added, features_removed: features_removed)
  end

  def change_private_search # rubocop:todo GitHub/UseRestfulActions
    val = params[:private_search_value]

    # Private search is the only option when connected to proxima so we enable "public" search at the same time
    if val == "true"
      features_added = ["private_search"]
      features_added << "search" if GitHub.github_connect_ghe_com_enabled?
      features_removed = []
      dotcom_connection.clear_pending_features
      features_added.each { |f| dotcom_connection.add_feature(f) }
    elsif val == "false"
      features_added = []
      features_removed = ["private_search"]
      features_removed << "search" if GitHub.github_connect_ghe_com_enabled?
      dotcom_connection.clear_pending_features
      features_removed.each { |f| dotcom_connection.remove_feature(f) }
    end

    redirect_to dotcom_permission_upgrade_and_instrument_url(features_added: features_added, features_removed: features_removed)
  end

  def change_actions_download_archive # rubocop:todo GitHub/UseRestfulActions
    val = params[:actions_download_archive_value]

    if val == "true"
      features_added = ["actions_download_archive"]
      features_removed = []
      dotcom_connection.clear_pending_features
      dotcom_connection.add_feature(features_added.first)
    elsif val == "false"
      features_added = []
      features_removed = ["actions_download_archive"]
      dotcom_connection.clear_pending_features
      dotcom_connection.remove_feature(features_removed.first)
    end

    redirect_to dotcom_permission_upgrade_and_instrument_url(features_added: features_added, features_removed: features_removed)
  end

  def change_contributions # rubocop:todo GitHub/UseRestfulActions
    val = params[:contributions_sync_value]

    if val == "true"
      features_added = ["contributions"]
      features_removed = []
      dotcom_connection.clear_pending_features
      dotcom_connection.add_feature(features_added.first)
    elsif val == "false"
      features_added = []
      features_removed = ["contributions"]
      dotcom_connection.clear_pending_features
      dotcom_connection.authenticator.remove_all_contributions
      dotcom_connection.remove_feature(features_removed.first)
    end

    redirect_to dotcom_permission_upgrade_and_instrument_url(features_added: features_added, features_removed: features_removed)
  end

  def change_license_usage_sync # rubocop:todo GitHub/UseRestfulActions
    unless dotcom_connection.owner_type == "business"
      return redirect_to \
        admin_settings_dotcom_connection_enterprise_path(GitHub.global_business),
        flash: {
          error: "This feature may only be enabled when connected to a #{GitHub.dotcom_host_name_string} enterprise account.",
        }
    end

    val = params[:license_usage_sync_value]

    if val == "true"
      features_added = ["license_usage_sync"]
      features_removed = []
      dotcom_connection.clear_pending_features
      dotcom_connection.add_feature(features_added.first)
    elsif val == "false"
      features_added = []
      features_removed = ["license_usage_sync"]
      dotcom_connection.clear_pending_features
      dotcom_connection.remove_feature(features_removed.first)
    end

    redirect_to dotcom_permission_upgrade_and_instrument_url(features_added: features_added, features_removed: features_removed)
  end

  def change_content_analysis # rubocop:todo GitHub/UseRestfulActions
    case params[:content_analysis_value]
    when "enabled_with_notifications"
      features_added = %w(content_analysis content_analysis_notifications)
      features_removed = []
      dotcom_connection.clear_pending_features
      features_added.each { |f| dotcom_connection.add_feature(f) }
    when "enabled_without_notifications"
      features_added = ["content_analysis"]
      features_removed = ["content_analysis_notifications"]
      dotcom_connection.clear_pending_features
      dotcom_connection.add_feature(features_added.first)
      dotcom_connection.remove_feature(features_removed.first)
    when "disabled"
      features_added = []
      features_removed = %w(content_analysis content_analysis_notifications)
      dotcom_connection.clear_pending_features
      features_removed.each { |f| dotcom_connection.remove_feature(f) }
    end

    redirect_to dotcom_permission_upgrade_and_instrument_url(features_added: features_added, features_removed: features_removed)
  end

  def change_usage_metrics # rubocop:todo GitHub/UseRestfulActions
    val = params[:usage_metrics_value]

    if val == "true"
      features_added = ["usage_metrics"]
      features_removed = []
      dotcom_connection.clear_pending_features
      dotcom_connection.add_feature(features_added.first)
    elsif val == "false"
      features_added = []
      features_removed = ["usage_metrics"]
      dotcom_connection.clear_pending_features
      dotcom_connection.remove_feature(features_removed.first)
    end

    redirect_to dotcom_permission_upgrade_and_instrument_url(features_added: features_added, features_removed: features_removed)
  end

  def change_dependabot_access # rubocop:todo GitHub/UseRestfulActions
    render_404 and return unless GitHub.dependabot_enabled?

    val = params[:dependabot_access_value]

    if val == "true"
      features_added = ["dependabot_access"]
      features_removed = []
      dotcom_connection.clear_pending_features
      dotcom_connection.add_feature(features_added.first)
    elsif val == "false"
      features_added = []
      features_removed = ["dependabot_access"]
      dotcom_connection.clear_pending_features
      dotcom_connection.remove_feature(features_removed.first)
    end

    redirect_to dotcom_permission_upgrade_and_instrument_url(features_added: features_added, features_removed: features_removed)
  end

  def change_complete # rubocop:todo GitHub/UseRestfulActions
    if state_matches_session?
      ActiveRecord::Base.connected_to(role: :writing) do
        apply_pending_config_changes
      end
      redirect_to admin_settings_dotcom_connection_enterprise_path(GitHub.global_business)
    else
      ActiveRecord::Base.connected_to(role: :writing) do
        dotcom_connection.clear_pending_features
      end
      flash[:notice] = nil
      flash[:error] = params[:error]
      error = GitHub::Connect::ApiError.new(params[:error]) if params[:error]
      redirect_error(error)
    end
  end

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
        return_to: admin_settings_change_complete_enterprise_url(this_business),
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

  def require_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end

  def redirect_error(error = nil)
    error ||= GitHub::Connect::ServiceUnavailableError.new("API Inaccessible")
    Failbot.report(error , { app: "dotcom-connection" })
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
