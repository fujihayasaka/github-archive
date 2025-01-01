# typed: true
# frozen_string_literal: true

module Elastomer::Adapters

  # The BulkReleases adapter is used to operate on all the releases
  # associated with a repository in bulk. The model for this adapter is a
  # Repository. The releases for the repository can be deleted
  # from the search index, or they can be added to the search index using this
  # adapter type.
  class BulkReleases < RepositoryItemReconciler

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Releases"
    end

    def self.mysql_cluster
      ::Release.cluster_name
    end

    # Configure the adapter with options passed in from the job.
    def initialize(*args)
      super(*T.unsafe(args))
      reconcile_fields %w[updated_at]
    end

    # Public: Iterate over each release for the repository and
    # yield an indexing action (:index or :delete) along with a document Hash
    # corresponding to that action.
    #
    # Returns this adapter instance.
    def each(&block)
      return self if !repo || repo.spammy?

      reconcile("release", &block)

      self
    end

    # Public: Create a query hash that can be used to delete all release associated
    # with the repository.
    #
    # Returns an Array containing the delete query Hash and the documents
    # types that should be deleted.
    #
    # Raises a RuntimeError if the document_id is not set.
    def delete_query
      if document_id.nil?
        raise RuntimeError, "The Repository ID has not been set."
      end

      query = { query: { term: { repo_id: document_id } } }
      opts  = { type: "release", routing: document_routing }

      [query, opts]
    end

    # Raises RuntimeError because you shouldn't use this method.
    def to_hash
      raise RuntimeError, "Releases indexing does not support single hash indexing - use the `each` method."
    end

  end  # BulkReleases
end  # Elastomer::Adapters
