# typed: strict
# frozen_string_literal: true

module Copilot
  module Usage
    # This module is used to send a request to Copilot Limiter to generate a CSV report of premium usage
    # for a specific entity (business, organization, or user).
    # It is included in the following controllers and tested by their respective test classes:
    # - Businesses::Billing::CopilotPremiumUsageReportController
    # - Customers::Billing::CopilotPremiumUsageReportController
    # - Orgs::CopilotPremiumUsageReportController
    # - Stafftools::Businesses::Billing::CopilotPremiumUsageReportController
    extend T::Helpers
    extend ActiveSupport::Concern
    requires_ancestor { ApplicationController }

    sig do
      params(
        entity: T.any(::Copilot::Business, ::Copilot::Organization, ::Copilot::User),
        user_id: Integer,
        start_date: T.nilable(T.any(Date, DateTime)),
        end_date: T.nilable(T.any(Date, DateTime))
      ).void
    end
    def premium_usage_csv_request(entity:, user_id:, start_date: nil, end_date: nil)
      if (start_date.nil? && !end_date.nil?) || (!start_date.nil? && end_date.nil?)
        return render json: {
          success: false,
          error: "Both start_date and end_date must be provided or both must be nil"
        }, status: :bad_request
      end

      if (
        start_date.nil? &&
        end_date.nil? &&
        FeatureFlag.vexi.enabled?("copilot_premium_usage_date_last_45d", current_user, default: false)
      )
        start_date = (Time.now.utc - 45.days).to_date
        end_date = Time.now.utc.to_date
      else
        start_date ||= get_entity_billing_cycle_date(entity, :start)
        end_date ||= get_entity_billing_cycle_date(entity, :end)
      end

      unless entity.can_export_premium_usage?
        return render json: {
          success: false,
          error: "Not authorized to export premium usage"
        }, status: :forbidden
      end

      if entity.premium_usage_csv(user_id: user_id, start_date: start_date, end_date: end_date)
        render json: {
          success: true,
          message: "CSV generation request processed successfully",
          date_range: {
            start_date: start_date.strftime("%B %d, %Y"),
            end_date: end_date.strftime("%B %d, %Y"),
          }
        }, status: :ok
      else
        render json: {
          success: false,
          error: "Failed to process CSV generation request"
        }, status: :internal_server_error
      end
    end

    sig do
      params(
        entity: T.any(::Copilot::Business, ::Copilot::Organization, ::Copilot::User),
        date_type: Symbol,
      ).returns(Date)
    end
    def get_entity_billing_cycle_date(entity, date_type)
      raise ArgumentError, "date_type must be :start or :end" unless [:start, :end].include?(date_type)

      entity_object = case entity
      when ::Copilot::Business
        entity.business_object
      when ::Copilot::Organization
        entity.organization_object
      when ::Copilot::User
        entity.user_object
      end

      if date_type == :start
        entity_object.current_metered_billing_cycle_starts_at.utc.to_date
      else
        entity_object.next_metered_billing_cycle_starts_at.utc.to_date
      end
    end
  end
end
