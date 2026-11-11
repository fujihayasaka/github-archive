# typed: true
# frozen_string_literal: true

class Businesses::DotcomConnectionController < Businesses::BusinessController
  include Businesses::DotcomConnection::ControllerMethods

  before_action :business_owner_required
  before_action :require_dotcom_connection_enabled

  before_action :add_csp_exceptions, only: :index
  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  CSP_EXCEPTIONS = {
    form_action: ["#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}"],
    preserve_schemes: GitHub.dotcom_host_protocol != "https",
  }.freeze

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

  def update
    case params[:setting].to_s
    when "search"
      change_search
    when "private_search"
      change_private_search
    when "actions_download_archive"
      change_actions_download_archive
    when "contributions"
      change_contributions
    when "license_usage_sync"
      change_license_usage_sync
    when "content_analysis"
      change_content_analysis
    when "usage_metrics"
      change_usage_metrics
    when "dependabot_access"
      change_dependabot_access
    else
      render_404
    end
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

  private

  def change_search
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

  def change_private_search
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

  def change_actions_download_archive
    return render_404 unless GitHub.actions_enabled?

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

  def change_contributions
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

  def change_license_usage_sync
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

  def change_content_analysis
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

  def change_usage_metrics
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

  def change_dependabot_access
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
end
