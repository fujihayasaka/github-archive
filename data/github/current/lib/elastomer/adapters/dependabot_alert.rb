# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  class DependabotAlert < ::Elastomer::Adapter
    extend T::Helpers
    extend T::Sig
    include GitHub::Memoizer

    abstract!

    ModelType = T.type_alias do
      T.any(
        ::SecurityOverviewAnalytics::FeatureStatusRevision,
        ::SecurityOverviewAnalytics::DependabotAlertRevision
      )
    end

    sig(:final) { returns(String) }
    def self.index_name
      "DependabotAlerts"
    end

    sig(:final) { returns(T.any(Symbol, String)) }
    def self.mysql_cluster
      ::ApplicationRecord::SecurityOverviewAnalytics.cluster_name
    end

    sig { params(revisions: T::Array[ModelType]).void }
    def self.prefill_payload(revisions)
      GitHub::PrefillAssociations.prefill_batch_method(revisions, :searchable?)
    end

    sig do
      params(
        model: ModelType,
        payload: T.nilable(T::Hash[Symbol, T.untyped]),
      ).returns(T.nilable(String))
    end
    def self.generate_signature(model, payload: nil)
      return nil unless model.searchable?

      payload ||= create(model).payload
      Digest::SHA256.base64digest(GitHub::JSON.encode(payload))
    end

    sig { params(repository_id: Integer).returns(String) }
    def self.generate_parent_document_id(repository_id)
      "repository_metadata:#{repository_id}"
    end

    sig { abstract.returns(T.nilable(ModelType)) }
    def model; end

    sig { override.params(model: ModelType).void }
    def model=(model)
      @model = model

      if model.is_a?(::SecurityOverviewAnalytics::FeatureStatusRevision)
        # Repository metadata is a parent document to alert revisions thus it requires a predictable document_id
        # which a child document can create for their own payload.
        @document_id = self.class.generate_parent_document_id(model.repository_id)
      else
        # Overriding document_id to avoid primary key collisions since we are storing record from different tables (id spaces).
        @document_id = "#{model.class.table_name}:#{model.id}"
      end
    end

    sig { returns(T.nilable(Integer)) }
    memoize def document_routing
      model&.repository_id
    end

    sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
    def payload; end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    memoize def to_hash
      raise Elastomer::ModelMissing if model.nil?
      return nil unless T.must(model).searchable?

      # Elasticsearch metadata plus Dependabot alert data.
      hash = base_hash.merge(payload)

      # Any change in this signature means the alert should be reindexed.
      hash[:search_index_signature] = signature

      hash
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def base_hash
      {
        _id: document_id.to_s,
        _type: document_type,
        _routing: document_routing,
      }
    end

    private

    sig { returns(::SecurityOverviewAnalytics::Repository) }
    memoize def repository_metadata
      T.must_because(model&.repository_metadata) { "checked by revision.searchable?" }
    end

    sig { returns(T.nilable(String)) }
    memoize def signature
      self.class.generate_signature(T.must(model), payload: payload)
    end

    sig { params(value: T.nilable(ActiveSupport::TimeWithZone)).returns(T.nilable(String)) }
    def time(value)
      value&.utc&.iso8601(3)
    end
  end

  class RepositorySecurityAlertMetadata < DependabotAlert
    extend T::Sig

    Model = ::SecurityOverviewAnalytics::FeatureStatusRevision

    sig do
      override.params(
        model_or_id: T.any(ModelType, Integer, String),
        args: T.untyped
      ).returns(DependabotAlert)
    end
    def self.create(model_or_id, *args)
      obj = T.unsafe(self).new(*args)

      case model_or_id
      when String, Integer
        # Repository metadata is a parent document to alert revisions thus it requires a predictable document_id
        # which a child document can create for their own payload.
        repository_id = Model.where(id: model_or_id).pick(:repository_id)
        obj.document_id = self.generate_parent_document_id(repository_id)
      else
        obj.model = model_or_id
      end

      obj
    end

    sig { override.returns(T.nilable(Model)) }
    memoize def model
      return @model if defined? @model
      repository_id = T.cast(document_id, String).split(":").last
      @model = Model.find_by(repository_id:, next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID)
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def payload
      repository_feature_status = T.must(model)

      {
        # Shared fields
        repository_business_id: repository_metadata.business_id,
        repository_owner_id: repository_metadata.owner_id,
        repository_owner_type: repository_metadata.owner_type,
        repository_id: repository_metadata.repository_id,

        # Repository metadata
        repository_name: repository_metadata.name,
        repository_visibility: repository_metadata.visibility,
        repository_archived: repository_metadata.archived,
        dependabot_alerts_enabled: repository_feature_status.dependabot_alerts_enabled,
        code_scanning_enabled: repository_feature_status.code_scanning_enabled,
        secret_scanning_enabled: repository_feature_status.secret_scanning_enabled,

        # Join field
        repository_security_alert_join: "repository"
      }
    end
  end

  class RepositoryDependabotAlertRevision < DependabotAlert
    extend T::Sig

    Model = ::SecurityOverviewAnalytics::DependabotAlertRevision

    sig do
      override.params(
        model_or_id: T.any(ModelType, Integer, String),
        args: T.untyped
      ).returns(DependabotAlert)
    end
    def self.create(model_or_id, *args)
      obj = T.unsafe(self).new(*args)

      case model_or_id
      when String, Integer
        # Overriding document_id to avoid primary key collisions since we are storing record from different tables (id spaces).
        obj.document_id = "#{Model.table_name}:#{model_or_id}"
      else
        obj.model = model_or_id
      end

      obj
    end

    sig { override.returns(T.nilable(Model)) }
    def model
      return @model if defined? @model
      id = T.cast(document_id, String).split(":").last
      @model = Model.find_by(id:)
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def payload
      revision = T.must(model)

      {
        # Shared fields
        repository_business_id: repository_metadata.business_id,
        repository_owner_id: repository_metadata.owner_id,
        repository_owner_type: repository_metadata.owner_type,
        repository_id: repository_metadata.repository_id,

        ## Revision data
        alert_date_id: revision.date_id,
        alert_next_revision_date_id: revision.next_revision_date_id,

        ## Common alert fields
        alert_feature_type: revision.feature_type,
        alert_number: revision.alert_number,
        alert_severity: revision.alert_severity,
        alert_tool: "dependabot",
        alert_resolved: revision.alert_resolved,
        alert_resolution: revision.alert_resolution,
        alert_created_at: time(revision.alert_created_at),
        alert_updated_at: time(revision.alert_updated_at),
        alert_resolved_at: time(revision.alert_resolved_at),
        alert_reopened_at: time(revision.alert_reopened_at),

        # Dependabot fields
        dependabot_ghsa_id: revision.ghsa_id,
        dependabot_package_name: revision.package_name,
        dependabot_ecosystem: revision.ecosystem,
        dependabot_dependency_scope: revision.dependency_scope,

        # Join field
        repository_security_alert_join: {
          name: "security_alert",
          parent: self.class.generate_parent_document_id(revision.repository_id)
        }
      }
    end
  end
end
