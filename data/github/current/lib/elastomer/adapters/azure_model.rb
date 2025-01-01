# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  class AzureModel < ::Elastomer::Adapter

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "AzureModels"
    end

    def self.mysql_cluster
      ::AzureModels::CatalogItem.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      @model ||= ::AzureModels::CatalogItem.find_by(id: document_id)
    end

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing,
          "The data model has not been set, or the document ID does not exist in the database."
      end

      values = JSON.parse(model.value).deep_symbolize_keys[:model]

      return @hash if defined? @hash
      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        search_type: document_type,
        name: values[:friendly_name],
        categories: values[:tags].map(&:downcase),
        task: values[:task],
        model_family: values[:model_family].downcase,
        state: "listed"
      }
    end
  end
end
