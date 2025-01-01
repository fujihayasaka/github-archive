# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UsageReportController < Stafftools::Businesses::BillingController
  extend T::Sig

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ReactHelper

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
    if !valid_date_range?
      return render json: { error: "Invalid date range" }, status: 400
    end

    start_date = get_start_date_for_period(params[:period].to_i)
    end_date = get_end_date_for_period(params[:period].to_i)

    usage_report_response = billing_platform_client.queue_usage_report_export(
      customer_id: this_business.customer.id,
      start_date: start_date.to_i,
      end_date: end_date.to_i,
      actor_id: current_user&.id,
    )

    if usage_report_response.is_a?(::Billing::Platform::Api::Error)
      if usage_report_response.original_error&.code == :already_exists
        return render json: { error: "User already has a pending usage report request" }, status: 409
      else
        return render json: { error: "Unable to request usage report export" }, status: 500
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
  def valid_date_range?
    usage_report_selections.map { |p| p[:type] }.include?(params[:period].to_i)
  end
end
