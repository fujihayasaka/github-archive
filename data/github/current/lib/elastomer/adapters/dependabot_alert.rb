# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  class DependabotAlert < ::Elastomer::Adapter
    include GitHub::Memoizer

    sig { returns(String) }
    def self.index_name
      "DependabotAlerts"
    end

    sig { returns(T.any(Symbol, String)) }
    def self.mysql_cluster
      ::RepositoryVulnerabilityAlert.cluster_name
    end

    # Serialize timestamps to Elasticsearch with microsecond precision, which is the max
    # that MySQL currently supports. This ensures that when we read timestamps back from
    # Elasticsearch, they can always be parsed to a ruby DateTime without losing precision
    # from what was originally stored in MySQL.
    sig { params(datetime: T.nilable(ActiveSupport::TimeWithZone)).returns(T.nilable(String)) }
    def self.serialize_timestamp(datetime)
      datetime&.utc&.iso8601(6)
    end

    sig { params(alerts: T::Array[::RepositoryVulnerabilityAlert]).void }
    def self.prefill_payload(alerts)
      GitHub::PrefillAssociations.prefill_associations(alerts, [{ repository: :owner }, { vulnerability: :vulnerability_references }, :vulnerable_version_range])

      GitHub::PrefillAssociations.prefill_batch_method(alerts, :searchable?)
      GitHub::PrefillAssociations.prefill_batch_method(alerts.map(&:vulnerability), :cve_epss)
    end

    sig { returns(T.nilable(::RepositoryVulnerabilityAlert)) }
    memoize def model
      # We intentionally double memoize here because this is how the base class
      # memoizes, and if we don't play along, Adapter.create will re-find a
      # pre-found alert.
      return @model if defined? @model

      ::RepositoryVulnerabilityAlert.find_by(id: document_id)
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    memoize def to_hash
      raise Elastomer::ModelMissing if model.nil?
      return nil unless alert.searchable?

      # Elasticsearch metadata plus Dependabot alert data.
      base_hash.merge(payload)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def base_hash
      {
        _id: document_id.to_s,
        _type: document_type,
        _routing: document_routing,
      }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def payload
      {
        risk_type: "dependabot-alert",
        relationship: alert.dependency_relationship,
        vulnerability_id: alert.vulnerability_id,
        vulnerable_version_range_id: alert.vulnerable_version_range_id,
        id: alert.id,
        created_at: self.class.serialize_timestamp(alert.created_at),
        manifest_path: alert.vulnerable_manifest_path,
        dependency_scope: alert.dependency_scope,
        state: alert.state,
        resolution: alert.resolution,
        last_state_change_at: self.class.serialize_timestamp(alert.last_state_change_at),
        updated_at: self.class.serialize_timestamp(alert.updated_at),
        search_index_updated_at: self.class.serialize_timestamp(alert.search_index_updated_at),

        # ecosystem, has_patch, package_name (affects)
        **vulnerable_version_range.dependabot_alert_fields,

        # description, summary, severity, severity_score
        **vulnerability.dependabot_alert_fields,

        # epss_percentage
        **(cve_epss&.dependabot_alert_fields || {}),

        # repository_id, owner_id
        **Search::DependabotAlerts::Repository.dependabot_alert_fields(repository),
      }
    end

    sig { returns(T.nilable(Integer)) }
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def document_routing
      @document_routing ||= model&.repository_id
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    private

    sig { returns(::RepositoryVulnerabilityAlert) }
    memoize def alert
      T.must(model)
    end

    sig { returns(::Repository) }
    memoize def repository
      T.must(alert.repository)
    end

    sig { returns(::Vulnerability) }
    memoize def vulnerability
      T.must(alert.vulnerability)
    end

    sig { returns(T.nilable(::CVEEPSS)) }
    memoize def cve_epss
      vulnerability.cve_epss
    end

    sig { returns(::VulnerableVersionRange) }
    memoize def vulnerable_version_range
      T.must(alert.vulnerable_version_range)
    end
  end
end
