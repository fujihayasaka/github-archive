# typed: strict
# frozen_string_literal: true

class Businesses::Billing::UsageReportController < Businesses::BillingsController

  include Billing::Platform::Api::Utils
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include Billing::UsageDependency
  include Billing::UsageReportDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Businesses::Billing::UsageReportController#create"
  ].freeze, T::Array[String])

  MEUSE_REPORT_WINDOW = 180

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing, only: [:create]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:create],
    optional: true

  allow_verified_fetch only: [:create]

  before_action :parse_json_params, only: [:create]
  before_action :validate_date_range, only: [:create]

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
    )
    create_usage_report_request(usage_report_request: usage_report_request)
  end

  private

  sig { void }
  def validate_date_range
    render json: { error: "Invalid date range" }, status: 400 unless valid_date_range?(period_selection: period_selection, custom_range_start_date: custom_range_start_date, custom_range_end_date: custom_range_end_date, entity: this_business)
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
