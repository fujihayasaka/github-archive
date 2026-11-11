# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  class RepositoryAction < ::Elastomer::Adapter

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "RepositoryActions"
    end

    def self.mysql_cluster
      ::RepositoryAction.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      @model ||= ::RepositoryAction.find_by(id: document_id)
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

      return @hash if defined? @hash
      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        search_type: document_type,
        name: model.name,
        is_verified_owner: model.verified_owner?,
        owner_name: model.owner&.name,
        owner_login: model.owner&.display_login,
        created_at: model.created_at,
        description: ::Search.clean_and_sanitize(model.description&.force_encoding(Encoding::UTF_8)),
        featured: model.featured?,
        rank_multiplier: model.rank_multiplier,
        repository_id: model.repository_id,
        state: model.state,
        updated_at: model.updated_at,
        primary_category: regular_category_names.first,
        secondary_category: regular_category_names.second,
        categories: category_names,
        stars: model.repository.stargazer_count,
        dependents_count: model.dependents_count
      }
    end

    def category_names
      @category_names ||= model.categories.pluck(:name).map(&:downcase)
    end

    def regular_category_names
      @regular_category_names ||= model.regular_categories.pluck(:name)
    end
  end
end
