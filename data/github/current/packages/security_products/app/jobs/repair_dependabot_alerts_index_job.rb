# typed: true
# frozen_string_literal: true

class RepairDependabotAlertsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk
  retry_on_dirty_exit

  FILTERS = {
    repository: {
      model_scope: ->(id) { RepositoryVulnerabilityAlert.where(repository_id: id) },
      elasticsearch_query: ->(id, document_id_range) { elasticsearch_query_for_named_filter(:repository_id, id, document_id_range) }
    },
    vulnerability: {
      model_scope: ->(id) { RepositoryVulnerabilityAlert.where(vulnerability_id: id) },
      elasticsearch_query: ->(id, document_id_range) { elasticsearch_query_for_named_filter(:vulnerability_id, id, document_id_range) }
    },
    vulnerable_version_range: {
      model_scope: ->(id) { RepositoryVulnerabilityAlert.where(vulnerable_version_range_id: id) },
      elasticsearch_query: ->(id, document_id_range) { elasticsearch_query_for_named_filter(:vulnerable_version_range_id, id, document_id_range) }
    },
  }.freeze

  reconcile "dependabot_alert",
    model_class: RepositoryVulnerabilityAlert,
    named_scopes: FILTERS.transform_values { |v| v[:model_scope] },
    named_elasticsearch_queries: FILTERS.transform_values { |v| v[:elasticsearch_query] },
    prefills: [:searchable?],
    fields: %w[search_index_updated_at],
    accept: :searchable?,
    limit: 250

  # Build a query for Elasticsearch that matches documents based on a specific field name and value,
  # within a given range of document IDs.
  #
  # Returns a Hash representing the Elasticsearch query.
  sig { params(field_name: Symbol, field_value: T.untyped, document_id_range: T::Range[Integer]).returns(T::Hash[Symbol, T.untyped]) }
  def self.elasticsearch_query_for_named_filter(field_name, field_value, document_id_range)
    {
      query: {
        bool: {
          must: [
            { term: { field_name => field_value } },
            { range: { id: { gte: document_id_range.first, lte: document_id_range.last } } }
          ]
        }
      },
      sort: [{ id: { order: "asc" } }]
    }
  end
end
