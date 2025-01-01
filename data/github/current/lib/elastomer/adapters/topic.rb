# typed: false
# frozen_string_literal: true

module Elastomer::Adapters
  class Topic < ::Elastomer::Adapter
    # Public: Returns the name of the Index class responsible for storing the generated documents.
    def self.index_name
      "Topics"
    end

    def self.mysql_cluster
      ::Topic.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does not map to any row in
    # the database, then `nil` is returned.
    #
    # Returns the data model instance.
    def model
      return @model if defined? @model
      @model = ::Topic.find_by_id(document_id)
    end

    # Public: Construct a document suitable for indexing in ElasticSearch and return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing,
          "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash
      repository_count = model.applied_repository_topics.on_public_repositories.limit(model.public_repo_count_max).size
      if repository_count == model.public_repo_count_max
        repository_count = model.applied_count
      end
      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        name: model.name,
        display_name: model.display_name,
        short_description: model.short_description,
        description: model.description,
        created_by: model.created_by,
        released: model.released,
        created_at: model.created_at,
        updated_at: model.updated_at,
        featured: model.featured?,
        curated: model.curated?,
        repository_count: repository_count,
        aliases: model.alias_names,
        related: model.related_topic_names,
      }
    end
  end
end
