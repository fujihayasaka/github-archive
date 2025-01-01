# typed: strict
# frozen_string_literal: true

module Elastomer::Adapters
  # Public: The BulkDependabotAlerts adapter is used to operate on all the Dependabot Alerts
  # associated with a repository in bulk. The model for this adapter is a
  # Repository. The dependabot alerts for the repository can be deleted from the
  # search index, or they can be added to the search index using this
  # adapter type.
  class BulkDependabotAlerts < RepositoryItemReconciler
    extend T::Helpers

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    sig { returns(String) }
    def self.index_name
      "DependabotAlerts"
    end

    # Public: Returns the database cluster name used to wait for replication
    # delay before indexing or deleting the adapter from Elasticsearch.
    sig { returns(String) }
    def self.mysql_cluster
      ::RepositoryVulnerabilityAlert.cluster_name
    end

    # Configure the adapter with options passed in from the job.
    sig { params(args: T.untyped).void }
    def initialize(*args)
      super
      reconcile_fields %w[search_index_updated_at]
    end

    # Public: Iterate over each dependabot alert for the repository and yield an
    # indexing action (:index or :delete) along with a document Hash
    # corresponding to that action.
    #
    # Returns this adapter instance.
    sig do
      params(
        block: T.nilable(T.proc.params(action: Symbol, data: T::Hash[Symbol, T.untyped]).void)
      ).returns(Elastomer::Adapters::BulkDependabotAlerts)
    end
    def each(&block)
      return self if !repo

      reconcile("repository_vulnerability_alert",
        es_type: "dependabot_alert",
        es_repo_id_field: :repository_id,
        &block)

      self
    end

    # Public: Create a query hash that can be used to delete all dependabot alerts
    # associated with the repository.
    #
    # Returns an Array containing the delete query Hash and the documents
    # types that should be deleted.
    #
    # Raises a RuntimeError if the document_id is not set.
    sig { returns([T::Hash[Symbol, T.untyped], T::Hash[Symbol, T.untyped]]) }
    def delete_query
      if document_id.nil?
        raise RuntimeError, "The Repository ID has not been set."
      end

      query = { query: { term: { repository_id: document_id } } }
      opts  = { type: "dependabot_alert", routing: document_routing }

      [query, opts]
    end

    # Public: Raises RuntimeError because you shouldn't use this method.
    sig { void }
    def to_hash
      raise RuntimeError, "Bulk Dependabot Alerts indexing does not support single hash indexing - use the `each` method."
    end

  end  # BulkDependabotAlerts
end  # Elastomer::Adapters
