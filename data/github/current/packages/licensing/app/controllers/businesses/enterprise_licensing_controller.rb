# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseLicensingController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include BusinessLicenseConsumptionExportHelper
  include ReactHelper

  before_action :business_access_required

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: %i(show)
  before_action :enable_microsoft_analytics, only: %i(show)
  before_action :add_microsoft_analytics_csp_exceptions, only: %i(show)
  layout "enterprise_funnel", only: %i(show)

  allow_verified_fetch only: [:create_export, :export]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:export]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Copilot,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:download_active_committers]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    only: [:download_consumed_licenses]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:download_active_committers, :download_consumed_licenses], optional: true

  stylesheet_bundle :settings

  def show
    render "businesses/enterprise_licensing/show"
  end

  def download_consumed_licenses # rubocop:todo GitHub/UseRestfulActions
    send_data Business::LicenseCsvGenerator.new(this_business).generate,
      filename: "consumed_licenses.csv"
  end

  def export # rubocop:todo GitHub/UseRestfulActions
    export = this_business.license_consumption_exports.find_by_token!(params[:token])
    render_business_license_consumption_export(export)
  end

  def create_export # rubocop:todo GitHub/UseRestfulActions
    options = {
      actor: current_user,
      format: params[:export_format],
      triggered_via_stafftools: false,
    }

    export = this_business.license_consumption_exports.create(options)
    respond_with_business_license_consumption_export \
      export: export,
      export_url: export_enterprise_licensing_url(token: export.token, format: export.format)
  end

  def download_active_committers # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.advanced_security_purchased?

    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_business, committer_type: :ACTIVE_COMMITTERS),
      filename: "ghas_active_committers_#{this_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  def download_maximum_committers # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.advanced_security_purchased?

    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_business, committer_type: :MAXIMUM_COMMITTERS),
      filename: "ghas_maximum_committers_#{this_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end
end
