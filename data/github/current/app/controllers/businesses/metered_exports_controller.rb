# typed: true
# frozen_string_literal: true

class Businesses::MeteredExportsController < Businesses::BusinessController
  include BillingSettingsHelper

  before_action :ensure_billing_enabled
  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    export = this_business.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end

  def create
    if valid_date_range?
      Billing::MeteredReportExportJob.perform_later(current_user, this_business, params[:days].to_i)

      flash[:notice] = "We're preparing your report! We’ll send an email to #{Billing::MeteredUsageReportGenerator.email_for_export(requester: current_user, target: this_business)} when it’s ready."
    else
      flash[:error] = "Selected date range was invalid. Please contact support or try again later."
    end

    redirect_back fallback_location: settings_billing_enterprise_path(this_business)
  end

  private

  def valid_date_range?
    Billing::MeteredUsageReportGenerator::VALID_DURATIONS.include?(params[:days].to_i)
  end
end
