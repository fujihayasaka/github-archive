# typed: false
# frozen_string_literal: true

module Elastomer::Adapters
  # Public: The BulkDiscussions adapter is used to operate on all the Discussions
  # associated with a repository in bulk. The model for this adapter is a
  # Repository. The discussions for the repository can be deleted from the
  # search index, or they can be added to the search index using this
  # adapter type.
  class BulkDiscussions < RepositoryItemReconciler

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Discussions"
    end

    # Public: Returns the database cluster name used to wait for replication
    # delay before indexing or deleting the adapter from Elasticsearch.
    def self.mysql_cluster
      ::Discussion.cluster_name
    end

    # Configure the adapter with options passed in from the job.
    def initialize(*args)
      super(*args)
      reconcile_fields %w[updated_at]
    end

    # Public: Iterate over each discussion for the repository and yield an
    # indexing action (:index or :delete) along with a document Hash
    # corresponding to that action.
    #
    # Returns this adapter instance.
    def each(&block)
      return self if !repo || !repo.discussions_on? || repo.spammy?

      reconcile("discussion", &block)

      self
    end

    # Public: Create a query hash that can be used to delete all discussions
    # associated with the repository.
    #
    # Returns an Array containing the delete query Hash and the documents
    # types that should be deleted.
    #
    # Raises a RuntimeError if the document_id is not set.
    def delete_query
      if document_id.nil?
        raise RuntimeError, "The Repository ID has not been set."
      end

      query = { query: { term: { repository_id: document_id } } }
      opts  = { type: "discussion", routing: document_routing }

      [query, opts]
    end

    # Public: Raises RuntimeError because you shouldn't use this method.
    def to_hash
      raise RuntimeError, "Discussions indexing does not support single hash indexing - use the `each` method."
    end

  end  # BulkDiscussions
end  # Elastomer::Adapters
