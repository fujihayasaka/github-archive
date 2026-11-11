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

      # Case insensitivity can only be applied to filters with <= 1024 terms,
      # as a hard limit on the number of clauses in a bool query.  If the filter
      # exceeds this limit, the query will fail.
      def case_insensitive?
        options.fetch(:case_insensitive, false)
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

        if values.include?(::Search::Filter::MISSING)
          { bool: { must_not: { exists: { field: field } } } }

        elsif values.include?(::Search::Filter::EXISTS)
          { exists: { field: field } }

        else
          values = values.first if singular?
          build_term_filter(field, values, execution: execution)
        end
      end

      def map_bool_collection(&block)
        super(&block)

        if bool_collection.must_not
          bool_collection.must(::Search::Filter::EXISTS) if bool_collection.must_not.delete(::Search::Filter::MISSING)
          bool_collection.must(::Search::Filter::MISSING) if bool_collection.must_not.delete(::Search::Filter::EXISTS)
        end

        bool_collection
      end

      # Internal: Construct a term filter for the given field and value, modifying
      # Filter#build_term_filter to support case-insensitive term filters when
      # the `case_insensitive` option is enabled.
      #
      # The parent implementation can return one of three shapes:
      #   1. { term: { name => value } }
      #   2. { terms: { name => [values] } }
      #   3. { bool: { must: [{ term: ... }, ...] } } (execution: :and)
      #
      # Each is rewritten to use case-insensitive `term` clauses. The
      # `terms` shape is expanded into a `bool.should` of individual
      # `term` clauses since ES `terms` does not support `case_insensitive`.
      #
      # Case insensitivity can only be applied to filters with <= 1024 terms,
      # as a hard limit on the number of clauses in a bool query.  If the filter
      # exceeds this limit, the query will fail.
      #
      # Returns the filter Hash or nil if a filter could not be created.
      def build_term_filter(name, value, opts = {})
        filter = super
        return filter unless filter.present? && case_insensitive?

        if filter.key?(:term)
          ci_term_clause(name, filter[:term][name])
        elsif filter.key?(:terms)
          clauses = Array(filter[:terms][name]).map { |v| ci_term_clause(name, v) }
          { bool: { should: clauses, minimum_should_match: 1 } }
        elsif filter.dig(:bool, :must).is_a?(Array)
          clauses = filter[:bool][:must].map { |clause| ci_term_clause(name, clause[:term][name]) }
          { bool: { must: clauses } }
        else
          filter
        end
      end

      private

      def ci_term_clause(name, value)
        { term: { name => { value: value, case_insensitive: true } } }
      end
    end  # TermFilter
  end  # Filters
end  # Search
