# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::UsageReportController < Stafftools::Users::BillingController
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
  before_action :validate_report_type, only: [:create]
  before_action :validate_date_range, only: [:create]

  sig { void }
  def create
    usage_report_request = ::Billing::MeteredUsage::UsageReportRequest.new(
      entity: this_user,
      start_date: custom_range_start_date&.to_time,
      end_date: custom_range_end_date&.to_time,
      period: period_selection.to_i,
      is_stafftools: true,
      type: type_selection,
    )
    create_usage_report_request(usage_report_request: usage_report_request)
  end

  sig { void }
  def show
    export = this_user.customer.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end

  private

  sig { void }
  def validate_report_type
    validate_report_type_for_entity(entity: this_user, type_selection: type_selection)
  end

  sig { void }
  def validate_date_range
    render json: { error: "Invalid date range" }, status: 400 unless valid_date_range?(
      period_selection: period_selection,
      custom_range_start_date: custom_range_start_date,
      custom_range_end_date: custom_range_end_date,
      entity: this_user,
      type: type_selection,
    )
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
