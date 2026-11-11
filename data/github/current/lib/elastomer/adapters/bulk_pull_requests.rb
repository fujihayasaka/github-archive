# typed: true
# frozen_string_literal: true

module Elastomer::Adapters

  # The BulkPullRequests adapter is used to operate on all the pull requests
  # associated with a repository in bulk. The model for this adapter is a
  # Repository. The pull requests for the repository can be deleted
  # from the search index, or they can be added to the search index using this
  # adapter type.
  class BulkPullRequests < RepositoryItemReconciler

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "PullRequests"
    end

    def self.mysql_cluster
      ::PullRequest.cluster_name
    end

    # Configure the adapter with options passed in from the job.
    def initialize(*args)
      T.bind(self, T.untyped)
      super(*args)
      reconcile_fields "updated_at"
    end

    # Public: Iterate over each pull request for the repository and
    # yield an indexing action (:index or :delete) along with a document Hash
    # corresponding to that action.
    #
    # Returns this adapter instance.
    def each(&block)
      return self if repo.spammy?
      reconcile("pull_request", { skip_commit_info_on_failure: true }, &block)
      self
    end

    # Public: Create a query hash that can be used to delete all pull requests
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
      opts  = { type: %w[pull_request], routing: document_routing }

      [query, opts]
    end

    # Raises RuntimeError because you shouldn't use this method.
    def to_hash
      raise RuntimeError, "PullRequests indexing does not support single hash indexing - use the `each` method."
    end

  end  # BulkPullRequests
end  # Elastomer::Adapters
