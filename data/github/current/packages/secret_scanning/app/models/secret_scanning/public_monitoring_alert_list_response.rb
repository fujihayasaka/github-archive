# typed: strict
# frozen_string_literal: true

module SecretScanning
  # Typed response for PublicMonitoringQueryService#list_alerts.
  class PublicMonitoringAlertListResponse < T::Struct
    class Status < T::Enum
      enums do
        Ok = new
        ServiceError = new
        CursorNotFound = new
      end
    end

    const :alerts, T::Array[PublicMonitoringAlert]
    const :total_count, Integer
    const :next_cursor, T.nilable(String)
    const :previous_cursor, T.nilable(String)
    const :status, Status, default: Status::Ok

    sig { params(status: Status).returns(PublicMonitoringAlertListResponse) }
    def self.empty(status: Status::Ok)
      new(alerts: [], total_count: 0, next_cursor: nil, previous_cursor: nil, status: status)
    end

    sig { returns(T::Boolean) }
    def service_error?
      status == Status::ServiceError
    end

    sig { returns(T::Boolean) }
    def cursor_not_found?
      status == Status::CursorNotFound
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def serialize_ui
      {
        alerts: alerts.map(&:serialize_ui),
        totalCount: total_count,
        nextCursor: next_cursor,
        previousCursor: previous_cursor,
        serviceError: service_error?,
      }
    end
  end
end
