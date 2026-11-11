# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # A prefix filter is used to restrict search results to the set of
    # documents where the field matches the specified prefix. The field should
    # have `not_analyzed` semantics in the search index. If the prefix value
    # to match is an Array then a prefix filter will be constructed for each
    # item in the Array.
    #
    # Please read the ElasticSearch documentation for more information:
    # https://www.elastic.co/guide/en/elasticsearch/reference/master/query-dsl-prefix-query.html
    class PrefixFilter < ::Search::Filter

      # Internal: Generate a filter hash from the given values.
      #
      # values - The prefix filter values as an Array of Strings.
      #
      # Returns a filter Hash or nil.
      def build(values)
        return if values.blank?
        return prefix_filter_for(values.first) if values.length == 1

        ary = values.map { |v| prefix_filter_for(v) }
        ary.compact!
        return if ary.empty?
        return ary.first if ary.length == 1

        { bool: { should: ary } }
      end

      # Internal: Generate a prefix filter hash from the given value.
      #
      # value - The prefix filter value as a String.
      #
      # Returns a filter document Hash or nil.
      def prefix_filter_for(value)
        return if value.blank?
        { prefix: { field => value.to_s } }
      end

    end  # PrefixFilter
  end  # Filters
end  # Search
