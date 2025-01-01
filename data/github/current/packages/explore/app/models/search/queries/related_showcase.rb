# typed: true
# frozen_string_literal: true

module Search
  module Queries

    # The RelatedShowcase is used to find related showcase collections.

    class RelatedShowcase

      attr_reader :index
      attr_reader :id
      # The search results page to return.
      attr_reader :page

      # Set the page number to the given value. We ensure the value is greater
      # than or equal to 1.
      def page=(value)
        value = value.to_i
        @page = (value < 1 ? 1 : value)
      end

      # The number of documents to return per page of results.
      attr_accessor :per_page

      FIELDS = %w[name body items.body items.item_description items.item_name].freeze

      # Standard number of results to show per page.
      def self.per_page_default
        2
      end

      def self.max_offset_default
        1000
      end

      def initialize(id, opts = {})
        self.page     = opts.fetch(:page, 1)
        self.per_page = opts.fetch(:per_page, self.class.per_page_default)

        @id = id
        @index = Elastomer::Indexes::Showcases.new
      end

      def execute
        response = index.docs.search(query, type: "showcase_collection")

        results = Results.new(response, page: page, per_page: per_page)
        results.results = normalize(results.results)

        results
      end

      def query
        {
          query: {
            bool: {
              must: [
                {
                  more_like_this: {
                    fields: FIELDS,
                    like: [
                      {
                        _index: index.name,
                        _id: @id
                      }],
                    min_term_freq: 2,
                    min_doc_freq: 1,
                  },
                },
              ],
              filter: { term: { published: true } },
            },
          },
          _source: { excludes: %w[items] },
          from: offset,
          size: per_page,
        }
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

      # Internal: Returns the Integer offset into the search results
      # corresponding to the current page. This is needed to take the
      # **will_paginate** `page` and `per_page` values and convert them into
      # something ElasticSearch understands.
      def offset
        offset = (page - 1) * per_page

        if offset >= self.class.max_offset_default
          Failbot.push(app: "github-user")
          raise Search::Query::MaxOffsetError, "Only the first #{self.class.max_offset_default} search results are available"
        else
          offset
        end
      end

    end
  end
end
