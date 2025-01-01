# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UsageReportController < Stafftools::Businesses::BillingController

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ReactHelper
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
    if this_business.feature_enabled?(:billing_custom_date_range_usage_report)
      usage_report_request = ::Billing::MeteredUsage::UsageReportRequest.new(
        entity: this_business,
        start_date: custom_range_start_date&.to_time,
        end_date: custom_range_end_date&.to_time,
        period: period_selection.to_i,
        is_stafftools: true,
      )
      create_usage_report_request(usage_report_request: usage_report_request)
    else
      legacy_report_from_vnext_enabled = this_business.feature_enabled?(:billing_vnext_legacy_usage_report)

      # If this is a legacy report from meuse, run the meuse export job and return early. Remove this if section once we have
      # enabled legacy reports from vNext
      if is_legacy_report?(period_selection.to_i) && !legacy_report_from_vnext_enabled
        Billing::MeteredReportExportJob.perform_later(current_user, this_business, MEUSE_REPORT_WINDOW,
          start_date: get_start_date_for_legacy_period,
          end_date: (this_business.customer.vnext_migration_date || DateTime.now.utc).to_datetime
        )
        audit_log_payload = {
          actor: current_user,
          business: this_business,
          customer_id: this_business.customer_id.to_s,
          period: period_selection,
          days: MEUSE_REPORT_WINDOW,
          start_date: get_start_date_for_legacy_period,
          end_date: (this_business.customer.vnext_migration_date || DateTime.now.utc).to_datetime,
        }

        GitHub.instrument("billing.usage_report_create", audit_log_payload)
        return render json: { success: true }, status: 200
      end

      if is_legacy_report?(period_selection.to_i)
        start_date = get_start_date_for_legacy_period
        end_date = get_end_date_for_legacy_period(this_business.customer)
      else
        start_date = get_start_date_for_period(period_selection.to_i)
        end_date = get_end_date_for_period(period_selection.to_i)
      end

      report_params = {
        customer_id: this_business.customer.id,
        start_date: start_date.to_i,
        end_date: end_date.to_i,
        actor_id: current_user&.id,
      }

      legacy_report_params = {
        legacy_report: is_legacy_report?(period_selection.to_i),
        billable_owner_type: is_legacy_report?(period_selection.to_i) ? billable_owner_type(this_business) : nil,
        billable_owner_id: is_legacy_report?(period_selection.to_i) ? this_business.billable_owner.id : nil,
      }

      report_params.merge!(legacy_report_from_vnext_enabled ? legacy_report_params : {})

      usage_report_response = billing_platform_client.queue_usage_report_export(
        **report_params
      )

      if usage_report_response.is_a?(::Billing::Platform::Api::Error)
        if usage_report_response.try(:original_error)&.code == :already_exists
          return render json: { error: "User already has a pending usage report request" }, status: 409
        else
          return render json: { error: "Unable to request usage report export" }, status: 500
        end
      end

      audit_log_payload = {
        actor: current_user,
        business: this_business,
        customer_id: this_business.customer_id.to_s,
        period: period_selection,
      }
      GitHub.instrument("billing.usage_report_create", audit_log_payload)
      render json: { success: true }, status: 200
    end
  end

  private

  sig { returns(T::Boolean) }
  def valid_date_range?
    return true if period_selection.to_i == usage_report_legacy_selection[:type] && this_business.customer.is_legacy_report_an_option?
    return true if is_custom_range?(period_selection.to_i) && is_custom_range_valid?(start_date: custom_range_start_date, end_date: custom_range_end_date, entity: this_business)

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
