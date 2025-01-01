# typed: strict
# frozen_string_literal: true

class Orgs::UsageReportController < Orgs::Controller

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
    export = this_organization.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end

  sig { void }
  def create
    if this_organization.feature_enabled?(:billing_custom_date_range_usage_report)
      usage_report_request = ::Billing::MeteredUsage::UsageReportRequest.new(
        entity: this_organization,
        start_date: custom_range_start_date&.to_time,
        end_date: custom_range_end_date&.to_time,
        period: period_selection.to_i,
      )
      create_usage_report_request(usage_report_request: usage_report_request)
    else
      if period_selection.to_i == USAGE_REPORT_LEGACY
        Billing::MeteredReportExportJob.perform_later(current_user, this_organization, MEUSE_REPORT_WINDOW,
          start_date: get_start_date_for_legacy_period,
          end_date: (this_organization.customer.vnext_migration_date || DateTime.now.utc).to_datetime
        )
      else
        start_date = get_start_date_for_period(period_selection.to_i)
        end_date = get_end_date_for_period(period_selection.to_i)
        usage_report_response = billing_platform_client.queue_usage_report_export(
          customer_id: this_organization.customer.id,
          start_date: start_date.to_i,
          end_date: end_date.to_i,
          actor_id: current_user&.id,
          organization_ids: nil
        )
        if usage_report_response.is_a?(::Billing::Platform::Api::Error)
          if usage_report_response.try(:original_error)&.code == :already_exists
            return render json: { error: "User already has a pending usage report request" }, status: 409
          else
            return render json: { error: "Unable to request usage report export" }, status: 500
          end
        end
      end

      audit_log_payload = {
        actor: current_user,
        customer_id: this_organization.customer.id.to_s,
        period: period_selection,
      }
      GitHub.instrument("billing.usage_report_create", audit_log_payload)
      render json: { success: true }, status: 200
    end
  end

  private

  sig { void }
  def ensure_target_is_billable
    render_404 unless this_organization&.billable?
  end

  sig { void }
  def validate_date_range
    render json: { error: "Invalid date range" }, status: 400 unless valid_date_range?
  end

  sig { returns(T::Boolean) }
  def valid_date_range?
    return true if period_selection.to_i == usage_report_legacy_selection[:type] && this_organization.customer.is_legacy_report_an_option?
    return true if is_custom_range?(period_selection.to_i) && is_custom_range_valid?(start_date: custom_range_start_date, end_date: custom_range_end_date, entity: this_organization)

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
