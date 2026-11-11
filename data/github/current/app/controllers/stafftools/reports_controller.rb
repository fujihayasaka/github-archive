# typed: true
# frozen_string_literal: true

class Stafftools::ReportsController < StafftoolsController
  before_action :ensure_feature_enabled
  before_action :block_suspended_users
  skip_before_action :site_admin_only, if: :trusted_port?
  before_action :require_admin_frontend, unless: :trusted_port?
  before_action :login_required, unless: :trusted_port?
  before_action :conditional_sudo_filter, unless: :trusted_port?

  skip_before_action :sudo_filter

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:all_users]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def authentication_methods # rubocop:todo GitHub/UseRestfulActions
    login_from_signed_auth_token("StafftoolsReports") ||
    login_from_authorization_header_auth ||
    super
  end

  # Gets the port the request is coming in on. This is so we
  # can limit particular API namespaces to only work for requests
  # coming in on trusted ports.
  #
  # Returns a String port.
  def server_port # rubocop:todo GitHub/UseRestfulActions
    env["SERVER_PORT"]
  end

  # Determines whether the port the request is coming in on
  # is a trusted port.
  def trusted_port? # rubocop:todo GitHub/UseRestfulActions
    GitHub.trusted_ports_enabled? && GitHub.trusted_ports.include?(server_port) && %w(127.0.0.1 ::1).include?(request.remote_ip)
  end

  def index
    render "stafftools/reports/index"
  end

  def active_users # rubocop:todo GitHub/UseRestfulActions
    if csv?
      send_report_data(:active_users, active_users_stafftools_reports_url(report_options({})))
    else
      cache_report(:active_users, active_users_stafftools_reports_url(report_options))
    end
  end

  def all_users # rubocop:todo GitHub/UseRestfulActions
    if csv?
      send_report_data(:all_users, all_users_stafftools_reports_url(report_options({})))
    else
      cache_report(:all_users, all_users_stafftools_reports_url(report_options))
    end
  end

  def dormant_users # rubocop:todo GitHub/UseRestfulActions
    if csv?
      send_report_data(:dormant_users, dormant_users_stafftools_reports_url(report_options({})))
    else
      cache_report(:dormant_users, dormant_users_stafftools_reports_url(report_options))
    end
  end

  def suspended_users # rubocop:todo GitHub/UseRestfulActions
    if csv?
      send_report_data(:suspended_users, suspended_users_stafftools_reports_url(report_options({})))
    else
      cache_report(:suspended_users, suspended_users_stafftools_reports_url(report_options))
    end
  end

  def all_organizations # rubocop:todo GitHub/UseRestfulActions
    if csv?
      send_report_data(:all_organizations, all_organizations_stafftools_reports_url(report_options({})))
    else
      cache_report(:all_organizations, all_organizations_stafftools_reports_url(report_options))
    end
  end

  def all_repositories # rubocop:todo GitHub/UseRestfulActions
    if csv?
      send_report_data(:all_repositories, all_repositories_stafftools_reports_url(report_options({})))
    else
      cache_report(:all_repositories, all_repositories_stafftools_reports_url(report_options))
    end
  end

  def token_request_format? # rubocop:todo GitHub/UseRestfulActions
    true
  end

  private

  def ensure_feature_enabled
    render_404 unless GitHub.reports_enabled?
  end

  def block_suspended_users
    render_404 if logged_in? && current_user.suspended?
  end

  def csv?
    request.format && request.format.csv?
  end

  def send_report_data(report, report_path)
    if data = GitHub::Reports.send(report)
      send_data data, type: "text/csv; charset=iso-8859-1; header=present",
                      disposition: "attachment;filename=#{report.to_s.gsub(/_/, '-')}-#{Time.now.to_i}.csv"
    else
      redirect_to report_path
    end
  end

  def cache_report(report, data_path)
    result = GitHub::Reports.send(report)

    if request.xhr?
      if result
        head 200, location: data_path, content_type: Mime[:html]
      else
        head 202, content_type: Mime[:html]
      end
    else
      if result
        head 303, location: data_path
      else
        head 202
      end
    end
  end

  def report_options(options = { format: "csv" })
    if GitHub.private_mode_enabled? && logged_in?
      options[:token] = current_user.signed_auth_token(
        scope: "StafftoolsReports",
        expires: 50.years.from_now,
      )
    end
    options
  end

  def conditional_sudo_filter
    return if authorization_header_authed? || signed_token_authed?
    sudo_filter
  end

  def required_oauth_scopes
    %w(site_admin).freeze
  end
end
