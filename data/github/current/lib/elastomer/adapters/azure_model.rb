# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  class AzureModel < ::Elastomer::Adapter

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "AzureModels"
    end

    sig { returns Symbol }
    def self.mysql_cluster
      ::GitHubModels.domain.models.mysql_cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    sig { returns T.nilable(::GitHubModels::IModel) }
    def model
      @model ||= ::GitHubModels.domain.models.find(id: document_id)
    end

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    def to_hash
      model = self.model
      if model.nil?
        raise Elastomer::ModelMissing,
          "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash
      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        search_type: document_type,
        name: model.friendly_name,
        publisher: model.publisher&.downcase,
        summary: model.summary,
        notes: model.notes,
        created_at: model.created_at,
        popularity: model.popularity,
        updated_at: model.updated_at,
        categories: model.tags.map(&:downcase),
        supported_languages: model.supported_languages.map(&:downcase),
        supported_input_modalities: model.supported_input_modalities.map(&:downcase),
        supported_output_modalities: model.supported_output_modalities.map(&:downcase),
        task: model.task,
        state: model.readable_by?(nil) ? "listed" : "delisted",
        rate_limit_tier: model.rate_limit_tier&.downcase,
        max_output_tokens: model.max_output_tokens,
        max_input_tokens: model.max_input_tokens,
        description: model.description,
        license: model.license,
        license_description: model.license_description,
      }
    end
  end
end
