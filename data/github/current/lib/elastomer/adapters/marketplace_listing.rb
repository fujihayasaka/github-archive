# typed: true
# frozen_string_literal: true

module Elastomer::Adapters
  class MarketplaceListing < ::Elastomer::Adapter
    # Public: Returns the name of the Index class responsible for storing the
    # generated documents.
    def self.index_name
      "MarketplaceListings"
    end

    def self.mysql_cluster
      ::Marketplace::Listing.cluster_name
    end

    # Public: Accessor for the data model instance. If the `document_id` does
    # not map to any row in the database, then `nil` is returned.
    #
    # Returns the data model instance.
    #
    def model
      @model ||= ::Marketplace::Listing.find_by(id: document_id)
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
        short_description: model.short_description,
        full_description: ::Search.clean_and_sanitize(model.full_description),
        description: ::Search.clean_and_sanitize(model.description),
        created_at: model.created_at,
        updated_at: model.updated_at,
        primary_category: regular_category_names.first,
        secondary_category: regular_category_names.second,
        categories: category_names,
        free: !model.paid?,
        offers_free_trial: model.offers_free_trial?,
        state: model.current_state.name.to_s,
        marketplace_id: "mpl:#{document_id}",
        is_verified_owner: model.verified_owner?,
        installation_count: model.cached_installation_count,
        installation_count_last_month: model.cached_installation_count(since: Date.current - 1.month),
        is_recommended: model.async_is_recommended?.sync,
        owner_login: model.owner&.login,
        copilot_app: model.copilot_app,
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
