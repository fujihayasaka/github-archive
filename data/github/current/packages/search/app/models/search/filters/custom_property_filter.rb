# typed: true
# frozen_string_literal: true

module Search
  module Filters
    class CustomPropertyFilter < ::Search::Filters::EnumeratedTermFilter
      def initialize(opts = {})
        super(opts)

        @key_regex = opts[:key_regex]
      end

      # Internal: Build the filter from the values.
      # We replace the Filter#build because it generates a { :bool => { :must => [] } }
      # which fails when negated. Instead, here we return all filters as an array
      #
      # Returns a filter array for ElasticSearch.
      def build(values)
        values = Array(values)
        values.map { |term| { term: { field => term } } }
      end

      # It will group together every filter matching the provided regex,
      # and then generate a common query for them on the provided field.
      # E.g.
      #   props.env:prod,test props.security:low
      # will yield
      #   field: [[env:prod, env:test], [security:low]]
      # which means
      #   all repos with (env:prod OR env:test) AND security:low
      #
      # Cannot use map_bool_collection because:
      #   - this doesn't address a single qualifier but all matching a key_regex
      #   - to map the values, we need also info from the qualifier (the property name)
      def bool_collection
        return @bool_collection if defined? @bool_collection
        @bool_collection = ::Search::ParsedQuery::BoolCollection.new field

        return @bool_collection if qualifiers.nil?

        qualifiers.each do |key, qualifier|
          if match = @key_regex.match(key)
            property_name = key.to_s.split(".").last
            qualifier.must&.each do |value|
              @bool_collection.must "#{property_name}:#{value.downcase}"
            end

            qualifier.and_should&.each do |values|
              @bool_collection.and_should values.map { |value| "#{property_name}:#{value.downcase}" }
            end

            qualifier.must_not&.each do |value|
              @bool_collection.must_not "#{property_name}:#{value.downcase}"
            end
          end
        end

        @bool_collection
      end
    end
  end
end
