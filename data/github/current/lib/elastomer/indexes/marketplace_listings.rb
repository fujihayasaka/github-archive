# typed: true
# frozen_string_literal: true

module Elastomer::Indexes
  # The MarketplaceListings index contains documents for GitHub Marketplace listings.
  #
  # These documents are searchable within this index.
  class MarketplaceListings < ::Elastomer::Index
    # Defines the mappings for the 'marketplace_listing' document type.
    #
    # Returns the Hash containing the document type mappings.
    def self.mappings_hook
      {
        marketplace_listing: {
          _all: { enabled: false },
          properties: {
            search_type: { type: "keyword" },
            name: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" },
                raw: { type: "keyword" }
              },
              analyzer: "texty"
            },
            short_description: { type: "text", analyzer: "texty" },
            full_description: { type: "text", analyzer: "texty" },
            description: { type: "text", analyzer: "texty" },
            created_at: { type: "date" },
            updated_at: { type: "date" },
            primary_category: { type: "keyword" },
            secondary_category: { type: "keyword" },
            categories: {
              type: "text",
              fields: {
                raw: { type: "keyword" }
              }
            },
            free: { type: "boolean" },
            offers_free_trial: { type: "boolean" },
            state: { type: "keyword" },
            marketplace_id: { type: "keyword" },
            installation_count: { type: "integer" }, #This field data is also displayed in UI view
            installation_count_last_month: { type: "integer" }, #This field data is also displayed in UI view
            is_verified_owner: { type: "boolean" }, #This field data is also displayed in UI view
            is_recommended: { type: "boolean" }, #This field data is also displayed in UI view
            is_trending: { type: "boolean" },
            owner_login: {
              type: "text",
              fields: {
                ngram: { type: "text", analyzer: "index_ngram_text", search_analyzer: "search_ngram_text" },
                raw: { type: "text", analyzer: "publisher_search" }
              },
              analyzer: "texty"
            }, #This field data is also displayed in UI view
            copilot_app: { type: "boolean" }
          }
        }
      }
    end

    # Settings for a MarketplaceListing search index.
    #
    # Returns the Hash containing the settings for this index.
    def self.settings_hook
      settings = {
        index: {
          number_of_shards:   GitHub.es_shard_count_for_marketplace_listings,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          "queries.cache.enabled": true,
        },
        analysis: {
          analyzer: {
            index_ngram_text: {
              tokenizer: "standard",
              filter:    %w[lowercase ngram_text],
            },
            search_ngram_text: {
              tokenizer: "standard",
              filter:    "lowercase",
            },
          },
          filter: {
            ngram_text: {
              type:     "edgeNGram",
              min_gram: 1,
              max_gram: 20,
              side:     "front",
            },
          },
        },
      }

      ::Elastomer::Analyzers.configure_texty settings
      settings
    end

    # Returns the Array of valid aliases for this index type.
    def self.aliases
      [::Elastomer.env.logical_index_name(self), ::Elastomer.env.index_name("marketplace-search")]
    end

    # Public: Returns a MarketplaceListings index configured to search the
    # `marketplace-search` alias. This alias spans the `marketplace-listings` search index and
    # the `non-marketplace-listings` search index enabling us to search both with one
    # query.
    #
    # name    - The index name as a String or Symbol
    # cluster - The cluster name as a String or Symbol
    #
    # Returns an MarketplaceListings search index instance.
    def self.searcher(name = ::Elastomer.env.index_name("marketplace-search"), cluster = nil)
      if cluster.nil? && name.start_with?("marketplace-search")
        cluster = ::Elastomer.router.
          cluster_for_index(name.sub(/\Amarketplace-search/, "marketplace-listings"))
      end
      new(name, cluster)
    end
  end
end
