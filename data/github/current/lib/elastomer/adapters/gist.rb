# typed: false
# frozen_string_literal: true

module Elastomer::Adapters

  # The Gist adapter is used to transform a gist ActiveRecord object into a
  # Hash document that can be indexed in ElasticSearch.
  class Gist < ::Elastomer::Adapter
    TIMEOUT_IN_SECONDS = 5.minutes

    # This error is used to stop the indexing process when the maximum
    # indexing time is exceeded.
    IndexingTimeout = Class.new ::Elastomer::Error

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Gists"
    end

    def self.mysql_cluster
      ::Gist.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    def model
      @model ||= ::Gist.find_by_id(document_id)
    end
    alias :gist :model

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    def to_hash
      if gist.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined?(@hash)
      @hash = nil

      # Bail if we this gist shouldn't be indexed
      return unless gist.gist_is_searchable?

      @hash = {
        _id: document_id,
        _type: document_type,

        gist_id: gist.id,
        owner_id: gist.user_id,
        forks: gist.forks.count,
        fork: gist.fork?,
        public: gist.public?,
        stars: gist.stargazer_count,
        description: gist.description,
        created_at: gist.created_at,
        updated_at: gist.updated_at,
      }

      @hash.merge!(code_hash)
      @hash
    end

    private

    def code_hash
      return {} unless code_iterator.iterable?

      {
        head: "master",
        head_ref: code_iterator.head_commit_sha,
        code: code_documents,
      }
    end

    def code_documents
      docs = []
      code_iterator.each do |code_blob|
        next if code_blob.deleted?
        docs << blob_to_document(code_blob)
      end
      docs
    end

    def blob_to_document(code_blob)
      document = {
        filename: code_blob.name,
        extension: code_blob.extname,
        file: nil,
        file_size: code_blob.size,
        language: code_blob.language_default_alias,
        language_id: code_blob.language_id,
        timestamp: Time.now.utc,    # FIXME this should be the timestamp of the commit_sha
      }

      document[:file] = code_blob.data if code_blob.indexable?

      document
    end

    def code_iterator
      @code_iterator ||= Elastomer::Adapters::GitRepositoryCodeIterator.new(gist,
        timeout: TIMEOUT_IN_SECONDS,
        on_timeout_exceeded: -> { raise IndexingTimeout, "Maximum indexing time exceeded!" })
    end
  end
end
