# typed: true
# frozen_string_literal: true

module Elastomer::Adapters

  # The BulkIssues adapter is used to operate on all the issues
  # associated with a repository in bulk. The model for this adapter is a
  # Repository. The issues for the repository can be deleted
  # from the search index, or they can be added to the search index using this
  # adapter type.
  class BulkIssues < RepositoryItemReconciler

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Issues"
    end

    def self.mysql_cluster
      ::Issue.cluster_name
    end

    # Configure the adapter with options passed in from the job.
    def initialize(*args)
      super(*T.unsafe(args))
      reconcile_fields %w[updated_at state]
    end

    # Public: Iterate over each issue for the repository and
    # yield an indexing action (:index or :delete) along with a document Hash
    # corresponding to that action.
    #
    # Returns this adapter instance.
    def each(&block)
      return self if !repo.has_issues? || repo.spammy?

      reconcile("issue", sql_conditions: "pull_request_id IS NULL", &block)

      self
    end

    # Public: Create a query hash that can be used to delete all issues
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

      query = { query: { term: { repo_id: document_id } } }
      opts  = { type: %w[issue], routing: document_routing }

      [query, opts]
    end

    # Raises RuntimeError because you shouldn't use this method.
    def to_hash
      raise RuntimeError, "Issues indexing does not support single hash indexing - use the `each` method."
    end

  end  # BulkIssues
end  # Elastomer::Adapters
