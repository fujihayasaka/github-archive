# typed: strict
# frozen_string_literal: true

class Businesses::Billing::UsageReportController < Businesses::BillingsController
  extend T::Sig

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ReactHelper

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

  sig { void }
  def show
    export = this_business.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end

  sig { void }
  def create
    if !valid_date_range?
      return render json: { error: "Invalid date range" }, status: 400
    end

    if params[:period].to_i == USAGE_REPORT_LEGACY
      Billing::MeteredReportExportJob.perform_later(current_user, this_business, meuse_report_start_date)
    else
      start_date = get_start_date_for_period(params[:period].to_i)
      end_date = get_end_date_for_period(params[:period].to_i)
      usage_report_response = billing_platform_client.queue_usage_report_export(
        customer_id: this_business.customer.id,
        start_date: start_date.to_i,
        end_date: end_date.to_i,
        actor_id: current_user&.id,
        organization_ids: should_filter_for_org_admin? ? get_org_ids_for_org_admin : nil
      )
      if usage_report_response.is_a?(::Billing::Platform::Api::Error)
        if usage_report_response.original_error&.code == :already_exists
          return render json: { error: "User already has a pending usage report request" }, status: 409
        else
          return render json: { error: "Unable to request usage report export" }, status: 500
        end
      end
    end

    audit_log_payload = {
      actor: current_user,
      business: this_business,
      customer_id: this_business.customer_id.to_s,
      period: params[:period],
    }
    GitHub.instrument("billing.usage_report_create", audit_log_payload)
    render json: { success: true }, status: 200
  end

  private

  sig { returns(T::Boolean) }
  def should_filter_for_org_admin?
    # do not filter billing manager or business owner usage
    !this_business.billing_manager?(current_user) && !this_business.owner?(current_user)
  end

  sig { returns(T::Array[Integer]) }
  def get_org_ids_for_org_admin
    current_user&.owned_organization_ids & this_business.organization_ids
  end

  sig { returns(T::Boolean) }
  def valid_date_range?
    return true if params[:period].to_i == usage_report_legacy_selection[:type] && is_legacy_report_an_option?(this_business)

    usage_report_selections.map { |p| p[:type] }.include?(params[:period].to_i)
  end

  sig { returns(Integer) }
  def meuse_report_start_date
    MEUSE_REPORT_WINDOW - days_since_migration(this_business.customer.billing_platform_enabled_product.migration_date)
  end
end
