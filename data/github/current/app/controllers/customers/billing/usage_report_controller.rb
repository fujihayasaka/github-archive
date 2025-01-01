# typed: strict
# frozen_string_literal: true

class Customers::Billing::UsageReportController < Customers::BillingController

  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Billing::UsageDependency
  include Billing::UsageReportDependency

  allow_verified_fetch only: [:create]
  before_action :parse_json_params, only: [:create]

  before_action :login_required
  before_action :ensure_billing_enabled
  before_action :validate_date_range, only: [:create]

  MEUSE_REPORT_WINDOW = 180

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    export = this_entity.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end

  sig { void }
  def create
    usage_report_request = ::Billing::MeteredUsage::UsageReportRequest.new(
      entity: this_entity,
      start_date: custom_range_start_date&.to_time,
      end_date: custom_range_end_date&.to_time,
      period: period_selection.to_i,
    )
    create_usage_report_request(usage_report_request: usage_report_request)
  end

  private

  sig { void }
  def ensure_target_is_billable
    render_404 unless this_entity.billable?
  end

  sig { void }
  def validate_date_range
    render json: { error: "Invalid date range" }, status: 400 unless valid_date_range?
  end

  sig { returns(T::Boolean) }
  def valid_date_range?
    return true if period_selection.to_i == usage_report_legacy_selection[:type] && this_entity.customer&.is_legacy_report_an_option?
    return is_custom_range_valid?(start_date: custom_range_start_date, end_date: custom_range_end_date, entity: this_entity) if is_custom_range?(period_selection.to_i)

    usage_report_selections.map { |p| p[:type] }.include?(period_selection.to_i)
  end

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
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
