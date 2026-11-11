# typed: strict
# frozen_string_literal: true

module SecretScanning
  # Typed response for PublicMonitoringQueryService#list_alerts.
  class PublicMonitoringAlertListResponse < T::Struct
    const :alerts, T::Array[PublicMonitoringAlert]
    const :total_count, Integer
    const :next_cursor, T.nilable(String)
    const :previous_cursor, T.nilable(String)

    sig { returns(PublicMonitoringAlertListResponse) }
    def self.empty
      new(alerts: [], total_count: 0, next_cursor: nil, previous_cursor: nil)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def serialize_ui
      {
        alerts: alerts.map(&:serialize_ui),
        totalCount: total_count,
        nextCursor: next_cursor,
        previousCursor: previous_cursor,
      }
    end
  end
end
