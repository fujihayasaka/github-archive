# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class EnterpriseQuery < ::Search::Query

      def self.field_list
        [:created, :updated, :sort].freeze
      end

      DEFAULT_SORT = %w(created desc).freeze

      SORT_MAPPINGS = {
        "created" => "created_at",
        "updated" => "updated_at",
      }.freeze

      def initialize(opts = {}, &block)
        super(opts, &block)
        @index = Elastomer::Indexes::Enterprises.new
      end

      def qualifier_fields
        self.class.field_list
      end

      def query_params
        { type: "enterprise" }
      end

      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "slug"
            @query_fields << "slug^10" << "slug.ngram^0.8"
          when "name"
            @query_fields << "name^1.2"
          end
        end

        @query_fields = %w[slug^10 slug.ngram^0.8 name^1.2] if @query_fields.empty?
        @query_fields
      end

      def query_doc
        return if escaped_query.empty?

        {
          query_string: {
            query: escaped_query,
            fields: query_fields,
            phrase_slop: 10,
            default_operator: "AND",
            analyzer: "texty_search",
          },
        }
      end

      def build_sort
        return if sort.blank?

        build_sort_section(sort, "_score", SORT_MAPPINGS)
      end

      def default_sort
        DEFAULT_SORT
      end

      def filter_hash
        return @filter_hash if defined? @filter_hash

        filters = {}

        filters[:created_at] = builder.date_range_filter(:created_at, :created)
        filters[:updated_at] = builder.date_range_filter(:updated_at, :updated)

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      def normalize(results)
        prune_results(results) unless @results_pruned
        super(results)
      end

      def prune_results(results)
        business_ids = results.map { |result| result["_id"].to_i }
        businesses = Business.where(id: business_ids).index_by(&:id)

        results.delete_if do |result|
          doc_id = result["_id"].to_i
          business = businesses[doc_id]

          if business.nil? && !Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("enterprise", doc_id)
            next true
          end

          false
        end
      end

      def parsed_query
        @parsed_query ||= self.class.parse(user_query)
      end
    end
  end
end
