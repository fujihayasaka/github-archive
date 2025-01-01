# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UsageReportController < Stafftools::Businesses::BillingController

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include Billing::UsageDependency
  include Billing::UsageReportDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  allow_verified_fetch only: [:create]

  before_action :parse_json_params, only: [:create]
  before_action :validate_date_range, only: [:create]

  def self.react_bundle_name
    "billing-app"
  end

  sig { void }
  def show
    export = this_business.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end

  sig { void }
  def create
    usage_report_request = ::Billing::MeteredUsage::UsageReportRequest.new(
      entity: this_business,
      start_date: custom_range_start_date&.to_time,
      end_date: custom_range_end_date&.to_time,
      period: period_selection.to_i,
      is_stafftools: true,
    )
    create_usage_report_request(usage_report_request: usage_report_request)
  end

  private

  sig { returns(T::Boolean) }
  def valid_date_range?
    return true if period_selection.to_i == usage_report_legacy_selection[:type] && this_business.customer.is_legacy_report_an_option?
    return is_custom_range_valid?(start_date: custom_range_start_date, end_date: custom_range_end_date, entity: this_business) if is_custom_range?(period_selection.to_i)

    usage_report_selections.map { |p| p[:type] }.include?(period_selection.to_i)
  end

  sig { void }
  def validate_date_range
    render json: { error: "Invalid date range" }, status: 400 unless valid_date_range?
  end

  sig { returns(T.nilable(String)) }
  def custom_range_start_date
    params[:start]
  end

  sig { returns(T.nilable(String)) }
  def custom_range_end_date
    params[:end]
  end

  sig { returns(T.nilable(String)) }
  def period_selection
    params[:period]
  end
end
