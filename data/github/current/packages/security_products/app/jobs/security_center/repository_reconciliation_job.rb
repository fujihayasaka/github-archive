# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class RepositoryReconciliationJob < RepositorySyncJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    # Same job as +RepositorySyncJob+ but with lower priority.
    queue_as :security_center_reconciliation

    sig do
      params(
        repository_id: Integer,
        source_event: String,
        feature_type: T.nilable(String), # unused
        event_timestamp: T.nilable(T.any(Float, Integer)), # unused
      )
      .void
    end
    def perform(repository_id:, source_event:, feature_type: nil, event_timestamp: nil)
      super(
        repository_id:,
        source_event:,
        feature_type: RepositorySyncJob::ALL_FEATURES_TYPE,
        event_timestamp: nil
      )
    end
  end
end
