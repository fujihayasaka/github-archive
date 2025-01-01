# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class PushProtectionMetrics < T::Struct
      const :total_block_count, Integer, default: 0
      const :successful_block_count, Integer, default: 0
      const :bypassed_alert_count, Integer, default: 0
      const :bypass_requests_count, Integer, default: 0
      const :mean_response_time, Integer, default: 0

      const :blocks_by_token_type_counts, T::Array[TokenTypeCountMetric], default: []
      const :bypasses_by_token_type_counts, T::Array[TokenTypeCountMetric], default: []

      const :blocks_by_repository_counts, T::Array[RepoCountMetric], default: []
      const :bypasses_by_repository_counts, T::Array[RepoCountMetric], default: []

      const :bypasses_by_reason_counts, T::Array[BypassReasonCountMetric], default: []

      const :bypasses_by_request_status_counts, T::Array[BypassRequestStatusCountMetric], default: []
    end
  end
end
