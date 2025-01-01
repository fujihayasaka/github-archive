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
        created_at: alert.created_at&.utc&.iso8601(3),
        manifest_path: alert.vulnerable_manifest_path,
        dependency_scope: alert.dependency_scope,
        state: alert.alert_state,
        resolution: alert.resolution,
        last_state_change_at: alert.last_state_change_at&.utc&.iso8601(3),
        updated_at: alert.updated_at&.utc&.iso8601(3),
        search_index_updated_at: alert.search_index_updated_at&.utc&.iso8601(3),

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
    memoize def document_routing
      model&.repository_id
    end

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
