# typed: false
# frozen_string_literal: true

module Elastomer::Adapters
  # The Commit adapter is used to read commits from the default branch of a
  # repository and index them into the commits index. What is needed for
  # this adapter to work is a Repository instance and the commit SHA to index
  # from. If two commit SHAs are given, then only that range will be indexed.
  class Commit < ::Elastomer::Adapter
    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Commits"
    end

    def self.mysql_cluster
      ::Repository.cluster_name
    end

    # This error is used to stop the indexing process when the maximum
    # indexing time is exceeded.
    IndexingTimeout = Class.new ::Elastomer::Error

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    def model
      return @model if defined?(@model) && !@model.nil?
      @model = if GitHub.flipper[:repos_domain_elastomer].enabled?
        ::Repositories.domain.by_id(document_id)
      else
        ::Repository.find_by(id: document_id)
      end
    end
    alias :repository :model

    # Document routing information used to co-locate all commits on a single
    # shard in the search index for a given repository.
    def document_routing
      document_id
    end

    # List commits that are reachable by following the parent links from
    # `include_hashes`, but exclude commits that are reachable from
    # `exclude_hashes`.
    #
    # This is a streaming version of CommitsCollection#except.
    #
    # include_hashes - Array of commit hashes
    # exclude_hashes - Array of commit hashes
    # batch_size - Number of commits to fetch in each batch
    # limit - Maximum number of commits to stream
    #
    # Returns an Enumerator of Commit objects.
    def stream_commits(include_hashes: [], exclude_hashes: [], batch_size: 10000, limit: 1000000)
      Enumerator.new do |y|
        args = include_hashes + exclude_hashes.map { |hash| "^#{hash}" }
        skip = 0

        loop do
          max_count = [batch_size, limit - skip].min
          options = {}
          options["exclude"] = exclude_hashes
          options["skip"] = skip
          options["max"] = max_count

          hashes = repository.rpc.list_revision_history_multiple(include_hashes, exclude: exclude_hashes, skip: skip, max: max_count)
          ::Commit.prefill_users(repository.commits.find(hashes)).each { |commit| y.yield(commit) }
          skip += hashes.length
          break if hashes == []
        end
      end
    end

    # Public: Iterate over each commit in the repository and yield
    # an indexing action (:index or :delete) along with a document Hash
    # corresponding to that action.
    def each
      if repository.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return self unless repository.commits_are_searchable?

      es_head_hash = index.indexed_head_hash(repository.id)

      begin
        repo_head_hash = repository.ref_to_sha(repository.default_branch)

        unless es_head_hash.nil?
          stream_commits(include_hashes: [es_head_hash], exclude_hashes: [repo_head_hash]).each do |commit|
            yield :delete, { _id: commit_document_id(commit.oid), _type: "commit", _routing: document_routing }
          end
        end

        stream_commits(include_hashes: [repo_head_hash], exclude_hashes: es_head_hash.nil? ? [] : [es_head_hash]).each do |commit|
          yield :index, commit_to_document(commit)
        end
      rescue GitRPC::InvalidFullOid => error
        GitHub.logger.error(
          "Invalid commit OID for Elastomer indexing", {
            :exception => error,
            "code.namespace" => self.class.name,
            "code.function" => "each",
            "gh.search.index.latest_oid" => es_head_hash,
            "gh.repo.head_oid" => repo_head_hash,
            "gh.repo.id" => repository.id,
            "gh.repo.head_branch" => repository.default_branch
          }
        )
        GitHub.dogstats.increment "search.commits.indexing.gitrpc_error.count", tags: datadog_tags(index)
      rescue IndexingTimeout => error
        Failbot.report(error, {
          "gh.repo.id": repository.id,
          "gh.repo.base_oid": es_head_hash,
          "gh.repo.head_oid": repo_head_hash,
        })
        GitHub.dogstats.increment "search.commits.indexing.timeout.count", tags: datadog_tags(index)
      ensure
        state_doc = index.get_metadata["has_commit_state_docs"] ? commit_state_document(repo_head_hash) : repository_document(repo_head_hash)
        yield :index, state_doc
      end
    end

    # Public: Create a query hash that can be used to delete all indexed
    # commits associated with the repository.
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
      opts  = { type: %w[commit repository], routing: document_routing }

      [query, opts]
    end

    # Raises RuntimeError because you shouldn"t use this method.
    def to_hash
      raise RuntimeError, "Commit indexing does not support single hash indexing - use the `each` method."
    end

    # Convert a commit into a document Hash that can be indexed in
    # Elasticsearch.
    #
    # commit - The Commit to convert to a document Hash.
    #
    # Returns a document Hash or nil if an error occurred.
    def commit_to_document(commit)
      {
        _id: commit_document_id(commit.oid),
        _type: "commit",
        _routing: document_routing,
        hash: commit.oid,
        parent_hashes: commit.parent_oids,
        tree_hash: commit.tree_oid,
        is_merge: commit.parent_oids.length > 1,
        author_id: commit.author.try(:id),
        author_name: commit.author_name,
        author_email: commit.author_email,
        author_date: commit.authored_date,
        committer_id: commit.committer.try(:id),
        committer_name: commit.committer_name,
        committer_email: commit.committer_email,
        committer_date: commit.committed_date,
        message: commit.message,
        public: repository.public?,
        repo_id: repository.id,
      }
    end

    def commit_document_id(hash)
      Digest::SHA1.hexdigest("#{repository.id}::#{hash}") # rubocop:disable GitHub/InsecureHashAlgorithm
    end

    def commit_state_document(repo_head_hash)
      {
        _id: repository.id,
        _type: "commit",
        _routing: document_routing,
        repo_id: repository.id,
        head_branch: repository.default_branch,
        hash: repo_head_hash,
        pushed_at: repository.pushed_at,
        public: repository.public?,
        is_commit_state_doc: true
      }
    end

    def repository_document(repo_head_hash)
      {
        _id: repository.id,
        _type: "repository",
        _routing: document_routing,
        repo_id: repository.id,
        head_branch: repository.default_branch,
        head_hash: repo_head_hash,
        pushed_at: repository.pushed_at,
        public: repository.public?,
      }
    end
  end
end
