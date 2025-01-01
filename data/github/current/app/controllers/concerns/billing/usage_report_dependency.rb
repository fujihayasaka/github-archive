# typed: strict
# frozen_string_literal: true

module Billing
  module UsageReportDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    include Billing::Platform::Api::Utils
    include UsageDependency

    requires_ancestor { ApplicationController }

    abstract!

    sig { params(usage_report_request: ::Billing::MeteredUsage::UsageReportRequest).void }
    def create_usage_report_request(usage_report_request:)
      entity = usage_report_request.entity
      period = usage_report_request.period
      start_date = usage_report_request.start_date
      end_date = usage_report_request.end_date

      legacy_report_from_vnext_enabled = entity.feature_enabled?(:billing_vnext_legacy_usage_report)

      # If this is a legacy report from meuse, run the meuse export job and return early. Remove this if section once we have
      # enabled legacy reports from vNext
      if usage_report_request.is_legacy_report? && !legacy_report_from_vnext_enabled
        Billing::MeteredReportExportJob.perform_later(current_user, entity, Billing::UsageDependency::MEUSE_REPORT_WINDOW,
          start_date: (Time.now.utc - Billing::UsageDependency::MEUSE_REPORT_WINDOW.days).to_datetime,
          end_date: (entity.customer&.vnext_migration_date || DateTime.now.utc).to_datetime
        )
        audit_log_payload = {
          actor: current_user,
          business: entity,
          customer_id: entity.customer&.id.to_s,
          period: period,
          days: Billing::UsageDependency::MEUSE_REPORT_WINDOW,
          start_date: (Time.now.utc - Billing::UsageDependency::MEUSE_REPORT_WINDOW.days).to_datetime,
          end_date: (entity.customer&.vnext_migration_date || DateTime.now.utc).to_datetime
        }

        GitHub.instrument("billing.usage_report_create", audit_log_payload)
        return render json: { success: true }, status: 200
      end

      report_params = {
        customer_id: entity.customer&.id,
        start_date: start_date,
        end_date: end_date,
        actor_id: current_user&.id,
      }

      legacy_report_params = {
        legacy_report: usage_report_request.is_legacy_report?,
        billable_owner_type: usage_report_request.is_legacy_report? ? billable_owner_type(entity) : nil,
        billable_owner_id: usage_report_request.is_legacy_report? ? entity.billable_owner.id : nil,
      }

      report_params.merge!({ organization_ids: get_org_ids_for_org_admin(entity, current_user) }) if !usage_report_request.is_stafftools && should_filter_for_org_admin?(entity, current_user)
      report_params.merge!(legacy_report_params) if legacy_report_from_vnext_enabled && usage_report_request.is_legacy_report?

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
        business: entity,
        customer_id: entity.customer&.id.to_s,
        period: period,
      }

      GitHub.instrument("billing.usage_report_create", audit_log_payload)
      GitHub.dogstats.increment("billing.usage_report.creation.count", tags: ["period:#{period}", "is_stafftools:#{usage_report_request.is_stafftools}"])
      render json: { success: true }, status: 200
    end

    sig { returns(Billing::Platform::Api::Client) }
    def billing_platform_client
      Billing::Platform::Api::Client.new
    end
  end
end
