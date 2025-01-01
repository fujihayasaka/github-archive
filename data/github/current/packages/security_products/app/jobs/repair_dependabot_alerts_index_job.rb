# typed: true
# frozen_string_literal: true

class RepairDependabotAlertsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk
  retry_on_dirty_exit

  reconcile "dependabot_alert",
    model_class: RepositoryVulnerabilityAlert,
    prefills: [:searchable?],
    fields: %w[search_index_updated_at],
    accept: :searchable?,
    limit: 250
end
