# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # A term filter is used to restrict search results to the set of documents
    # based on the value of the document fields. The value has to be an exact
    # match. Term filters should only be applied to fields that are not analyzed.
    #
    # If the value to match is actually an Array of values, then we will
    # create a terms filter. Only one of the values in the array needs to
    # match the document field. This behavior can be controlled via the
    # :execution flag.
    #
    # See the documentation below for more information on **term** and
    # **terms** filters.
    #
    # https://www.elastic.co/guide/en/elasticsearch/reference/master/query-dsl-term-query.html
    # https://www.elastic.co/guide/en/elasticsearch/reference/master/query-dsl-terms-query.html
    #
    class TermFilter < ::Search::Filter

      def execution
        options.fetch(:execution, :plain)
      end

      def singular?
        options.fetch(:singular, false)
      end

      def must_not
        values = bool_collection.must_not

        if values.blank?
          nil
        elsif values.length == 1 || singular?
          build_term_filter(field, values.first)
        else
          values.map { |value| build_term_filter(field, value) }
        end
      end

      #
      # values - The Array of values to convert into a term filter
      #
      # Returns the term filter Hash or nil.
      def build(values)
        return if values.blank?

        if values.include? :missing
          { bool: { must_not: { exists: { field: field } } } }

        elsif values.include? :exists
          { exists: { field: field } }

        else
          values = values.first if singular?
          build_term_filter(field, values, execution: execution)
        end
      end

      def map_bool_collection(&block)
        super(&block)

        if bool_collection.must_not
          if bool_collection.must_not.include? :missing
            bool_collection.must_not.delete(:missing)
            bool_collection.must(:exists)
          end
        end

        bool_collection
      end

    end  # TermFilter
  end  # Filters
end  # Search
