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

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing, only: [:create, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:create],
    optional: true

  allow_verified_fetch only: [:create]

  before_action :ensure_export_exists, only: [:show]
  before_action :current_user_can_view_exports?, only: [:show]
  before_action :parse_json_params, only: [:create]
  before_action :validate_report_type, only: [:create]
  before_action :validate_date_range, only: [:create]

  sig { void }
  def show
    redirect_to T.must(metered_usage_export).generate_expiring_url
  end

  sig { void }
  def create
    usage_report_request = ::Billing::MeteredUsage::UsageReportRequest.new(
      entity: this_business,
      start_date: custom_range_start_date&.to_time,
      end_date: custom_range_end_date&.to_time,
      period: period_selection.to_i,
      type: type_selection,
    )
    create_usage_report_request(usage_report_request: usage_report_request)
  end

  private

  sig { void }
  def validate_report_type
    validate_report_type_for_entity(entity: this_business, type_selection: type_selection)
  end

  sig { void }
  def validate_date_range
    render json: { error: "Invalid date range" }, status: 400 unless valid_date_range?(
      period_selection: period_selection,
      custom_range_start_date: custom_range_start_date,
      custom_range_end_date: custom_range_end_date,
      entity: this_business,
      type: type_selection)
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

  sig { void }
  def ensure_export_exists
    render_404 unless metered_usage_export
  end

  sig { void }
  def current_user_can_view_exports?
    return if this_business.can_manage_business?(current_user)

    # Export existence is guaranteed by ensure_export_exists before_action
    render_404 unless current_user == T.must(metered_usage_export).requester
  end

  # Helper method to memoize the export
  sig { returns(T.nilable(Billing::MeteredUsageExport)) }
  memoize def metered_usage_export
    T.let(
      this_business.metered_usage_exports.find_by(id: params[:id]),
      T.nilable(Billing::MeteredUsageExport),
    )
  end
end
