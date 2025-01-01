# typed: true
# frozen_string_literal: true

require "linguist"

module Elastomer::Adapters

  # The Code adapter is used to read commits from the default branch of a
  # repository and index them into the code search index. What is needed for
  # this adapter to work is a Repository instance and the commit SHA to index
  # from. If two commit SHAs are given, then only those files that have
  # changed between the two commits will be indexed.
  class Code < ::Elastomer::Adapter

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "CodeSearch"
    end

    def self.mysql_cluster
      ::Repository.cluster_name
    end

    # We truncate files at a byte size limit and cap the number at 500k due to
    # constraints of our sharding approach for repository file search.
    MAX_FILE_COUNT = 500_001  # do not index repositories with more than 500_000 files

    # This error is used to stop the indexing process when the maximum
    # indexing time is exceeded.
    IndexingTimeout = Class.new ::Elastomer::Error

    # Boolean flag used to force the full indexing of a repository that would
    # otherwise be ignore. Only use this option during testing.
    attr_accessor :force_indexing
    alias :force_indexing? :force_indexing

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      return @model if defined?(@model) && !@model.nil?
      @model = ::Repositories.domain.by_id(document_id)
    end
    alias :repository :model

    # Document routing information used to co-locate all source code on a single
    # shard in the search index for a given repository.
    def document_routing
      document_id
    end

    # Public: clear the `base_commit_sha` and `code_iterator` instance variables
    # so we can iterate over the source code files again.
    #
    # Returns this adapter.
    def reset!
      super
      remove_instance_variable :@base_commit_sha if defined? @base_commit_sha
      remove_instance_variable :@head_commit_sha if defined? @head_commit_sha
      remove_instance_variable :@code_iterator if defined? @code_iterator
      self
    end

    # Public: Iterate over each source code file in the repository and yield
    # an indexing action (:index or :delete) along with a document Hash
    # corresponding to that action.
    #
    # Returns this adapter instance.
    #
    def each(&block)
      if repository.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      # skip indexing if repository has been marked for deletion
      return self if repository.deleted?

      # skip repositories that should not be available in the search index
      # (spammy check is done in `code_is_searchable?`)
      unless force_indexing?
        return self unless repository.code_is_searchable?
        return self unless code_iterator.iterable?
      end

      perform_indexing(&block)
    end

    # Public: Create a query hash that can be used to delete all indexed
    # source code associated with the repository.
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
      opts  = { type: %w[code repository], routing: document_routing }

      [query, opts]
    end

    # Raises RuntimeError because you shouldn't use this method.
    def to_hash
      raise RuntimeError, "Code indexing does not support single hash indexing - use the `each` method."
    end

    # Set the base commit SHA to start iterating documents from. A `nil` commit
    # sha will cause iteration to start from the first commit in the repository.
    attr_writer :base_commit_sha

    # Accessor for specifying a head commit sha to index up to.
    attr_accessor :head_commit_sha

    # The latest commit sha used by the code iterator
    def iterated_head_commit_sha
      code_iterator.head_commit_sha
    end

    # Returns the current commit SHA for the repository from the search index
    # or `nil` if the repository is not present in the search index.
    def base_commit_sha
      return @base_commit_sha if defined? @base_commit_sha

      head_ref, _ = index.indexed_head(repository.id)
      @base_commit_sha = head_ref
    end

    # Convert a git blob into a document Hash that can be indexed in
    # ElasticSearch. If the blob is not indexable (a binary file for example)
    # then nil is returned.
    #
    # blob - The CodeBlob to convert to a document Hash.
    #
    # Returns a document Hash or nil if the blob is not indexable.
    def blob_to_document(blob)
      if blob.deleted?
        document = {
          _id: blob_document_id(blob),
          _type: "code",
          _routing: document_routing,
        }
        return [:delete, document]
      end

      document = {
        _id: blob_document_id(blob),
        _type: "code",
        _routing: document_routing,
        path: blob.dirname,
        filename: blob.basename,
        extension: blob.extname,
        file: nil,
        file_size: blob.size,
        repo_id: repository.id,
        public: repository.public?,
        language: blob.language_default_alias,
        language_id: blob.language_id,
        blob_sha: blob.sha,
        commit_sha: code_iterator.head_commit_sha, # FIXME this should be the commit SHA of the last time the file at path was modified
        timestamp: Time.now,                      # FIXME this should be the timestamp of the commit_sha
        fork: repository.fork?,
      }

      document[:file] = blob.data if blob.indexable?

      [:index, document]
    rescue StandardError => boom # rubocop:todo Lint/GenericRescue
      Failbot.report(boom.with_redacting!)
      nil
    end

    def blob_document_id(blob)
      str = "#{repository.id}::#{blob.name}"

      return str if index && !index.sha1_document_ids?
      Digest::SHA1.hexdigest(str) # rubocop:disable GitHub/InsecureHashAlgorithm
    end

    private

    def perform_indexing
      begin
        code_iterator.each do |code_blob|
          action, document = blob_to_document(code_blob)
          next unless action && document

          yield action, document
        end

      rescue IndexingTimeout => err
        Failbot.report err,
            "gh.repo.id": repository.id,
            "gh.repo.base_oid": code_iterator.base_commit_sha,
            "gh.repo.head_oid": code_iterator.head_commit_sha
        GitHub.dogstats.increment "search.code.indexing.timeout.count", tags: datadog_tags(index)

      ensure
        if code_iterator.head_commit_sha?
          if index.get_metadata["has_code_search_state_docs"]
            document = {
              _id: repository.id,
              _type: "code",
              _routing: document_routing,
              repo_id: repository.id,
              head: repository.default_branch,
              commit_sha: code_iterator.head_commit_sha,
              public: repository.public?,
              timestamp: Time.now,
              pushed_at: repository.pushed_at,
              is_code_search_state_doc: true
            }
          else
            document = {
              _id: repository.id,
              _type: "repository",
              _routing: document_routing,
              repo_id: repository.id,
              head: repository.default_branch,
              head_ref: code_iterator.head_commit_sha,
              public: repository.public?,
              timestamp: Time.now,
              pushed_at: repository.pushed_at,
            }
          end
          yield :index, document
          GitHub.dogstats.timing("search.code.indexing.elapsed", (code_iterator.elapsed_seconds * 1000).round, tags: datadog_tags(index))
        end
      end

      self
    end

    def code_iterator
      return @code_iterator if defined? @code_iterator

      base_sha = force_indexing? ? nil : base_commit_sha
      on_timeout = if force_indexing? || GitHub.enterprise?
        nil # Ignore timeouts when forced indexing or Enterprise
      else
        -> { raise IndexingTimeout, "Maximum indexing time exceeded!" }
      end

      @code_iterator = Elastomer::Adapters::GitRepositoryCodeIterator.new \
        repository,
        base_commit_sha: base_sha,
        head_commit_sha: head_commit_sha,
        on_timeout_exceeded: on_timeout
    end
  end
end
