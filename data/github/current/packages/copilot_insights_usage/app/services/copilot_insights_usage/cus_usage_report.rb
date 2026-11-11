# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  # Report class that fetches usage data from the Copilot Usage Service (CUS)
  # HTTP endpoints. Implements the same interface as the other report classes
  # (fetch) so DashboardService can use it as a drop-in.
  class CusUsageReport
    sig { params(enterprise_id: T.nilable(Integer), organization_id: T.nilable(Integer)).void }
    def initialize(enterprise_id: nil, organization_id: nil)
      if enterprise_id.nil? && organization_id.nil?
        raise ArgumentError, "Either enterprise_id or organization_id must be provided"
      end

      @enterprise_id = T.let(enterprise_id, T.nilable(Integer))
      @organization_id = T.let(organization_id, T.nilable(Integer))
      @cached_response = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
      @fetched = T.let(false, T::Boolean)
    end

    # Returns the day_totals array from the CUS response, sorted by day.
    # Applies a defensive client-side sort to ensure chronological order.
    # Any malformed response is wrapped as InvalidDataFormatError so
    # DashboardService's rescue blocks handle it.
    sig { params(date: T.nilable(Date), include_unknown_models: T::Boolean).returns(T::Array[T::Hash[String, T.untyped]]) }
    def fetch(date: nil, include_unknown_models: false)
      response = fetch_response
      day_totals = response.fetch("day_totals", [])
      day_totals.sort_by { |r| r.fetch("day", "").to_s }
    rescue ::Copilot::Metrics::UsageReport::Error
      raise
    rescue => e
      raise ::Copilot::Metrics::UsageReport::InvalidDataFormatError,
        "Unexpected CUS response format: #{e.class} - #{e.message}"
    end

    private

    # Fetches and memoizes the CUS response so repeated fetch calls
    # only make one HTTP call.
    sig { returns(T::Hash[String, T.untyped]) }
    def fetch_response
      return T.must(@cached_response) if @fetched

      response = if @organization_id
        DashboardReportsService.fetch_organization_latest_28_day(
          organization_id: @organization_id,
          enterprise_id: @enterprise_id
        )
      else
        DashboardReportsService.fetch_enterprise_latest_28_day(
          enterprise_id: T.must(@enterprise_id)
        )
      end

      if response.nil?
        raise ::Copilot::Metrics::UsageReport::NoDataAvailableError,
          "No dashboard report available from CUS"
      end

      @fetched = true
      @cached_response = response
    rescue DashboardReportsService::RequestError => e
      raise ::Copilot::Metrics::UsageReport::Error, e.message
    end
  end
end
