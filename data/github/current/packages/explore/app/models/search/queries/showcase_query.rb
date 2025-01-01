# typed: true
# frozen_string_literal: true

module Search
  module Queries

    # The ShowcaseQuery is used to search showcase collections.
    #
    class ShowcaseQuery < ::Search::Query

      # The set of fields that can be queried when performing a user search
      def self.field_list
        [:name, :body, "items.body", "items.item_description", "items.item_body", :created, :updated, :user].freeze
      end

      # Construct a new ShowcaseQuery instance that will highlight search results
      # by default.
      def initialize(opts = {}, &block)
        super(opts, &block)
        @index = Elastomer::Indexes::Showcases.new
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        { type: "showcase_collection" }
      end

      # Internal: Constructs the search query based on the `query` attribute.
      #
      # Returns the search query Hash.
      def query_doc
        return if escaped_query.empty?

        q = { query_string: {
          query: escaped_query,
          fields: %w[name^1.5 body items.body items.item_name items.item_description],
          phrase_slop: 10,
          default_operator: "AND",
          analyzer: "texty_search",
        } }

        { function_score: {
          query: q,
          # This function reduces the score of older documents. A 12 week old
          # document's score will be reduced by half.
          exp: { updated_at: {
            scale: "84d",
            offset: "14d",
            decay: 0.5,
          } },
        } }
      end

      # Internal: We need to use the same filters for the query and for the
      # aggregations with the exception of the language query. Since we are aggregationing
      # on language, applying a language filter would be most unhelpful.
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        unless current_user && (current_user.employee? || (current_user.site_admin? && GitHub.enterprise?))
          qualifiers[:published].must true
        end

        filters = {}

        filters[:created_at] = builder.date_range_filter(:created_at, :created)
        filters[:updated_at] = builder.date_range_filter(:updated_at, :updated)
        filters[:published]  = builder.term_filter(:published)

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        { encoder: :html,
          type: "plain",
          fields: {
          name: { number_of_fragments: 0 },  # force the whole title to be included in the fragment
          body: { number_of_fragments: 1, fragment_size: 160 },
        } }
      end

      # Internal: Transform and normalize the result hits from the
      # ElasticSearch index into ShowcaseResultView objects.
      #
      # results - An array of hit Hash objects.
      #
      # Returns the results Array.
      def normalize(results)
        results.map! { |h| ShowcaseResultView.new h }
      end

    end  # ShowcaseQuery
  end  # Queries
end  # Search
