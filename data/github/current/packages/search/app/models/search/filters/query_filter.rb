# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # A query filter is used to restrict search results to the set of
    # documents where a field value matches the given string query. The
    # :default_operator is used to control how the string query matches the
    # field. The :AND operator is used by default, and it requires all the
    # query tokens to be present in the field. You can also specify the :OR
    # operator such that only one field must be present.
    #
    # Please read the ElasticSearch documentation for more information:
    # http://www.elasticsearch.org/guide/reference/query-dsl/query-filter.html
    class QueryFilter < ::Search::Filter

      def default_operator
        options.fetch(:default_operator, :AND)
      end

      # Internal: Generate a filter document hash from the given value. The
      # value can be either an Array of Strings or a single String. In the
      # case of an Array of values, this method will call itself recursively
      # for each String in the Array. Please do avoid nested arrays lest the
      # stack-depth gods smite thee in their anger.
      #
      # value - The query filter value as a String or an Array of Strings.
      #
      # Returns a filter document Hash or nil.
      def build(values)
        return if values.blank?
        return query_filter_for(values.first) if values.length == 1

        ary = values.map { |v| query_filter_for(v) }
        ary.compact!
        return if ary.empty?
        return ary.first if ary.length == 1

        { bool: { should: ary } }
      end

      # Internal: Generate a query filter hash from the given value.
      #
      # value - The query filter value as a String.
      #
      # Returns a filter document Hash or nil.
      def query_filter_for(value)
        query = ::Search.escape_characters(value)
        return if query.empty?
        { query_string: { query: query, default_field: field, default_operator: default_operator } }
      end

    end
  end
end
