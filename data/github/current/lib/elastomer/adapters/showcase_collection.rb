# typed: false
# frozen_string_literal: true

module Elastomer::Adapters

  # The ShowcaseCollection adapter is used to transform a showcase collection ActiveRecord object into
  # a Hash document that can be indexed in ElasticSearch.
  #
  class ShowcaseCollection < ::Elastomer::Adapter

    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "Showcases"
    end

    def self.mysql_cluster
      ::Showcase::Collection.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      @model ||= ::Showcase::Collection.find_by_id(document_id)
    end
    alias :showcase_collection :model

    # Public: Construct a document suitable for indexing in ElasticSearch and
    # return it as a Hash.
    #
    # Returns the ElasticSearch document as a Hash.
    #
    def to_hash
      if model.nil?
        raise Elastomer::ModelMissing, "The data model has not been set, or the document ID does not exist in the database."
      end

      return @hash if defined? @hash

      @hash = {
        _id: document_id.to_s,
        _type: document_type,
        name: model.name,
        slug: model.slug,
        body: ::Search.clean_and_sanitize(model.body),
        published: model.published,
        created_at: model.created_at,
        updated_at: model.updated_at,
      }

      @hash[:items] = model.items.map do |item|
        h = {
          item_id: item.id,
          item_name: nil,
          item_description: nil,
          body: ::Search.clean_and_sanitize(item.body),
          created_at: item.created_at,
          updated_at: item.updated_at,
        }
        if item.item
          h[:item_name]        = item.item.name
          h[:item_description] = item.item.description
        end
        h
      end

      @hash
    end
  end  # ShowcaseCollection
end  # Elastomer::Index
