# typed: true
# frozen_string_literal: true

class RepairDependabotAlertsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk
  retry_on_dirty_exit

  reconcile "dependabot_alert",
    model_class: RepositoryVulnerabilityAlert,
    prefills: [:search_index_signature, :searchable?],
    fields: %w[search_index_signature],
    accept: :searchable?,
    limit: 500
end
