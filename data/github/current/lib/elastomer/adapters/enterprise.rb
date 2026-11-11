# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  class Enterprise < ::Elastomer::Adapter
    def self.index_name
      "Enterprises"
    end

    def self.mysql_cluster
      ::Business.cluster_name
    end

    def model
      return @model if defined? @model

      @model = ::Business.find_by id: document_id
    end

    # Public: Construct a document suitable for indexing in Elasticsearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash

      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        slug: model.slug,
        name: model.name,
        created_at: model.created_at,
        updated_at: model.updated_at,
      }
    end
  end
end
