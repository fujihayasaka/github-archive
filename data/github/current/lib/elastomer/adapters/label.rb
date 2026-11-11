# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  class Label < ::Elastomer::Adapter
    # Public: Returns the name of the Index class responsible for storing the generated documents.
    def self.index_name
      "Labels"
    end

    def self.mysql_cluster
      ::Label.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does not map to any row in
    # the database, then `nil` is returned.
    #
    # Returns the data model instance.
    def model
      return @model if defined? @model
      @model = ::Label.find_by(id: document_id)
    end

    # Document routing information used to co-locate all labels for a given
    # repository on a single shard in the search index.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def document_routing
      @document_routing ||= (model && model.repository_id)
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Public: Construct a document suitable for indexing in ElasticSearch and return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing,
          "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash
      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        _routing: document_routing,
        name: model.name,
        repo_id: model.repository_id,
        description: model.description,
        created_at: model.created_at,
        updated_at: model.updated_at,
      }
    end
  end
end
