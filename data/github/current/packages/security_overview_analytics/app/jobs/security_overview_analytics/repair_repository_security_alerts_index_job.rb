# typed: true
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class RepairRepositorySecurityAlertsIndexJob < Elastomer::RepairJob
    queue_as :index_bulk

    retry_on_dirty_exit

    reconcile T.must(Elastomer::Adapters::RepositorySecurityAlertMetadata.name).demodulize.underscore,
      model_class: FeatureStatusRevision,
      prefills: [:search_index_signature, :searchable?],
      fields: %w[search_index_signature],
      accept: :searchable?,
      limit: 500

    reconcile T.must(Elastomer::Adapters::RepositoryDependabotAlertRevision.name).demodulize.underscore,
      model_class: DependabotAlertRevision,
      prefills: [:search_index_signature, :searchable?],
      fields: %w[search_index_signature],
      accept: :searchable?,
      limit: 500

  end
end
