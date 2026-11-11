# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class ConditionalIssueSemanticQuery < ConditionalIssueQuery
      include IssueSemanticHelper

      sig { params(qualifier: ParsletQuery::QueryQualifier, search_in_fields: T::Array[String]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def qualifier_to_query(qualifier, search_in_fields)
        escaped_query = escape_query(qualifier.query)

        has_quoted_text_term = escaped_query.include?('"')

        # phrase_slop of zero means that the tokens in a matching document have to appear in the exact order
        # of the terms in an ElasticSearch phrase (characters surrrounded by double quotes) in the query input
        phrase_slop = has_quoted_text_term ? 0 : DEFAULT_PHRASE_SLOP_VALUE

        # "texty" analyzer has to be used for exact queries because some characters can produce a different set of tokens
        # when processed by "texty_search"
        analyzer = has_quoted_text_term ? "texty" : "texty_search"

        # For KNN search, filters will be injected later in build_query_filter
        # For semantic search, no additional filters needed
        function_query = build_semantic_function_query(escaped_query)

        {
          function_score: {
            query: function_query,
            score_mode: "sum",
            functions: [
              {
                exp: {
                  created_at: {
                    scale: "42d",
                    decay: 0.5,
                  }
                }
              },
              {
                exp: {
                  updated_at: {
                    scale: "84d",
                    decay: 0.5,
                  }
                }
              },
              {
                filter: { term: { state: "open" } },
                weight: 2,
              },
            ],
          }
        }
      end

      # Override build_query_filter to inject filters into KNN clauses when feature flag is enabled.
      #
      # KNN queries require filters within each knn clause for proper pre-filtering, not at the outer level.
      # This walks the query structure from the parent, extracts filters (repo, state, labels, etc.),
      # and injects them into each KNN clause's filter parameter.
      #
      # All these filters must be embedded in KNN clauses so Elasticsearch can efficiently
      # pre-filter documents before performing the expensive vector similarity calculation.
      def build_query_filter
        query_result = super
        return query_result if !query_result || !use_knn_search?

        # Get all filters that should be embedded in KNN clauses
        # These come from both the structured query (conditional_qualifiers) and the repo filter
        qualifier_filters = extract_filters_from_query_result(query_result)
        return query_result if qualifier_filters.empty?

        # Inject these into all KNN clauses
        inject_qualifier_filters_into_knn(query_result, qualifier_filters)
      end

      private

      # Normalize filter format - converts array format [:term, {field: value}] to hash format {term: {field: value}}
      # This is used to convert query segments to filters
      def normalize_filter_format(filter)
        if filter.is_a?(Array) && filter.length == 2 && filter[0].is_a?(Symbol)
          # Convert [:term, {field: value}] to {term: {field: value}}
          { filter[0] => filter[1] }
        else
          filter
        end
      end

      # Extract filters from the already-built query result
      # This includes both filters from the query structure and filters built from self.qualifiers hash
      def extract_filters_from_query_result(query_result)
        all_filters = []

        # First, get filters from the query structure (repo filters, etc.)
        all_filters.concat(extract_filters_from_structure(query_result))

        # Second, build filters from self.qualifiers hash (state, labels, etc.)
        all_filters.concat(build_filters_from_qualifiers_hash)

        all_filters.compact.uniq
      end

      # Extract filters from the query structure
      # This recursively searches the entire query structure to find all filter clauses
      # Extracts filter clauses from an ElasticSearch query structure.
      # Handles :must, :should, and :must_not clauses recursively.
      #
      # Example input:
      # {
      #   bool: {
      #     must: [
      #       { term: { state: "open" } },
      #       { bool: { should: [ ... ] } }
      #     ],
      #     should: [
      #       { term: { priority: "high" } }
      #     ],
      #     must_not: [
      #       { term: { locked: true } }
      #     ]
      #   }
      # }
      #
      # Returns an array of normalized filter hashes.
      def extract_filters_from_structure(query_result)
        return [] unless query_result.is_a?(Hash)

        filters = []
        filters.concat(extract_from_must_clauses(query_result))
        filters.concat(extract_from_should_clauses(query_result))
        filters.concat(extract_from_must_not_clauses(query_result))
        filters
      end

      # Extracts filters from :must clauses.
      # Example: { bool: { must: [ { term: ... }, { bool: ... } ] } }
      def extract_from_must_clauses(query_result)
        filters = []
        must_clauses = query_result.dig(:bool, :must)
        return filters unless must_clauses
        clauses = must_clauses.is_a?(Array) ? must_clauses : [must_clauses]
        clauses.each do |clause|
          next unless clause.is_a?(Hash)
          # Skip function_score queries
          next if clause.key?(:function_score)
          if !clause.key?(:bool)
            filters << normalize_filter_format(clause)
          else
            # Recursively extract from nested bool structures
            filters.concat(extract_filters_from_structure(clause))
          end
        end
        filters
      end

      # Extracts filters from :should clauses (OR queries).
      # Example: { bool: { should: [ { term: ... }, { bool: ... } ] } }
      def extract_from_should_clauses(query_result)
        filters = []
        should_clauses = query_result.dig(:bool, :should)
        return filters unless should_clauses
        clauses = should_clauses.is_a?(Array) ? should_clauses : [should_clauses]
        clauses.each do |clause|
          next unless clause.is_a?(Hash)
          # Skip function_score queries
          next if clause.key?(:function_score)
          if clause.key?(:bool)
            filters.concat(extract_filters_from_structure(clause))
          elsif !clause.key?(:knn) # Skip KNN clauses but include other filter types
            filters << normalize_filter_format(clause)
          end
        end
        filters
      end

      # Extracts filters from :must_not clauses (negation).
      # Example: { bool: { must_not: [ { term: ... } ] } }
      def extract_from_must_not_clauses(query_result)
        filters = []
        must_not_clauses = query_result.dig(:bool, :must_not)
        return filters unless must_not_clauses
        clauses = must_not_clauses.is_a?(Array) ? must_not_clauses : [must_not_clauses]
        clauses.each do |clause|
          next unless clause.is_a?(Hash)
          # Wrap in must_not to preserve negation semantics
          filters << { bool: { must_not: normalize_filter_format(clause) } }
        end
        filters
      end

      # Build filters from the self.qualifiers hash using FilterBuilder
      # This handles all qualifiers that don't require additional context like current_user
      def build_filters_from_qualifiers_hash
        return [] unless self.qualifiers

        builder = ::Search::FilterBuilder.new(self.qualifiers)

        # Build all available filters from qualifiers
        # Note: Some filters like author/assignee require additional context (current_user, exclude_private_profiles)
        # that isn't available here. Those filters are handled through the normal query structure extraction.
        filters = {}
        filters[:state] = builder.term_filter(:state)
        filters[:status] = builder.term_filter(:status)
        filters[:public] = builder.term_filter(:public)
        filters[:locked] = builder.term_filter(:locked)
        filters[:draft] = builder.term_filter(:draft)
        filters[:merged] = builder.term_filter(:merged, :merged_state)
        filters[:queued] = builder.term_filter(:queued)
        filters[:labels] = builder.label_filter(:labels, :label, missing: :none)

        # Remove nil and blank filters
        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        # Use BoolFilter to build the query fragment from all filters
        bool_collection = ::Search::Filters::BoolFilter.new(filters)
        query_fragment = bool_collection.build

        # Extract individual filter clauses from the built fragment
        if query_fragment
          extract_filters_from_structure(query_fragment)
        else
          []
        end
      end

      # Inject qualifier filters into all KNN clauses
      def inject_qualifier_filters_into_knn(obj, filters)
        case obj
        when Hash
          if obj.key?(:knn)
            # Found KNN clause - add qualifier filters to existing filter
            current_filter = obj[:knn][:filter] || {}

            # Combine existing filter with new qualifier filters
            if current_filter.empty?
              # No existing filter, just use the new filters
              obj[:knn][:filter] = if filters.length == 1
                filters[0]
              elsif filters.length > 1
                { bool: { must: filters } }
              else
                {}
              end
            else
              # Merge with existing filter
              all_filters = [current_filter] + filters
              obj[:knn][:filter] = if all_filters.length == 1
                all_filters[0]
              else
                { bool: { must: all_filters } }
              end
            end
          else
            obj.each_value { |v| inject_qualifier_filters_into_knn(v, filters) }
          end
        when Array
          obj.each { |item| inject_qualifier_filters_into_knn(item, filters) }
        end
        obj
      end

    end
  end
end
