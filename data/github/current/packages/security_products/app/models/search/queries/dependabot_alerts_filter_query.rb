# typed: true
# frozen_string_literal: true

module Search
  module Queries
    # DependabotAlertsFilterQuery is specialized to fetch aggregation counts for fields.
    # It uses custom logic in the `terms_aggregation` method to perform:
    # 1. Case insensitive aggregation counts matching on a filter search value, if one is provided
    # 2. Querying for aggregation counts on field values selected in the search query, if any are present.
    #    This ensures that selected filter options are always returned in the aggregation results
    #    if they match the filter search value.
    class DependabotAlertsFilterQuery < DependabotAlertsEsQuery
      QUERY_TIMEOUT = "1000ms".freeze

      attr_reader :field, :value, :selected_field

      MORE_FILTER_OPTIONS_KEY = "__more__".freeze

      sig { params(field: Symbol, value: T.nilable(String), opts: T::Hash[T.untyped, T.untyped], block: T.nilable(T.proc.params(query: Search::Query).void)).void }
      def initialize(field, value, opts = {}, &block)
        @field = field
        @value = value
        @selected_field = "selected_#{field}".to_sym

        super(
          **opts,
          per_page: 0,
          aggregations: [field],
          &block
        )
      end

      # When loading filter values, don't limit the query to specific nodes based on
      # any repo-scoping filters in the search query.
      sig { returns(T::Array[Integer]) }
      memoize def routing_repo_ids
        # We can still use any values from the ACL filter to limit routing
        Array(access_filter[Search::Filters::DependabotAlertsAclFilter::REPOSITORY_ID_KEY])
      end

      # Fetch filter option aggregation counts from ES, applying additional logic to ensure selected
      # filter options are always included in the results if they match the filter search value.
      sig { returns(T::Array[[T.untyped, Integer]]) }
      def filter_option_counts
        result = execute

        bucket_counts = []

        # Always push selected filter options first to the beginning of the list
        selected_terms_aggregation = result.aggregations.dig(selected_field.to_s, "terms") || result.aggregations[selected_field.to_s]
        if selected_terms_aggregation && selected_terms_aggregation["buckets"].present?
          bucket_counts.concat(selected_terms_aggregation["buckets"].map { |b| [b["key"], b["doc_count"]] })
        end

        # Then followed by the rest of the buckets from the filter option query
        aggregation = result.aggregations.dig(field.to_s, "terms") || result.aggregations[field.to_s]
        if aggregation && aggregation["buckets"].present?
          bucket_counts.concat(aggregation["buckets"].map { |b| [b["key"], b["doc_count"]] })
        end

        # Add a bucket for other filter options if there are any, to signify there are
        # additional options beyond the top buckets that are being returned.
        if aggregation && aggregation["sum_other_doc_count"] > 0
          bucket_counts << [MORE_FILTER_OPTIONS_KEY, aggregation["sum_other_doc_count"]]
        end

        bucket_counts
      end

      # Internal: Construct a query document for fetching aggregation counts for filter options.
      # This method overrides the base implementation to ensure that the query does not perform
      # any additional lookups.
      #
      # Returns the query document as a Hash.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def query_document
        {
          query: {
            bool: {
              filter: build_query_filter
            }
          },
          size: 0,
          aggregations: build_aggregations,
          runtime_mappings: build_runtime_mappings
        }
      end

      # Provide a longer timeout for aggregation queries
      sig { override.returns(T::Hash[T.untyped, T.untyped]) }
      def query_params
        super.merge(timeout: QUERY_TIMEOUT)
      end

      # Internal: Helper method that will construct a `terms` aggregation for the
      # given field. The field must be present in the `aggregation_fields` list and
      # it must be declared as one of the `aggregations` for the query.
      #
      # field - The field to aggregation on as a Symbol
      #
      # Returns a terms aggregation Hash.
      def terms_aggregation(field)
        return {} unless aggregations? && aggregations.include?(field)

        # Do not apply any filtering at the aggregation level, all filtering will performed
        # at the query level to ensure that filtering applies to all aggregations
        result = {}
        result[field] = {
          terms: { field: field, size: aggregations_size }
        }

        # Filter aggregation terms to only include results matching an aggregation filter, if present.
        if value.present?
          case_insensitive_search_term = value.chars.map do |c|
            next Regexp.escape(c) if c !~ /[[:alpha:]]/
            "[#{c.upcase}#{c.downcase}]"
          end
          result.dig(field, :terms)[:include] = ".*#{case_insensitive_search_term.join}.*"
        end

        # If there are selected terms for this field, ensure they are included
        # in the aggregation results if they match the filter search value.
        selected_terms = selected_terms_for_field(field)
        if selected_terms.any?
          # Set the selected terms aggregation to include the selected terms
          # and limit the results to the number of selected terms.
          result[selected_field] = {
            terms: { field: field, size: selected_terms.size, include: selected_terms }
          }

          # Set the original aggregation to exclude the selected terms to avoid duplication in the results
          result.dig(field, :terms)[:exclude] = selected_terms
        end

        result
      end

      # Internal: Helper method to fetch selected terms for a given field from the query's filter hash.
      # This is used to ensure that selected filter options are always included in the aggregation results if they match the filter search value.
      sig { params(field: Symbol).returns(T::Array[String]) }
      def selected_terms_for_field(field)
        terms = filter_hash.values.find { |f| f.is_a?(Search::Filter) && f.field&.to_sym == field }
        return [] unless terms && terms.must.present?

        required_terms = parse_values_from_filter_clause(terms.must, field)
        return required_terms if value.nil?

        search_value = value.to_s.downcase
        required_terms.select { |term| term.to_s.downcase.include?(search_value) }
      end

      # Internal: Helper method to recursively parse selected terms from a filter clause,
      # which can be in the form of a `term`, `terms`, or a nested `bool` clause.
      sig { params(filter: T::Hash[T.untyped, T.untyped], field: Symbol).returns(T::Array[String]) }
      def parse_values_from_filter_clause(filter, field)
        values = []

        if (term_value = filter.dig(:term, field)).present?
          case term_value
          when String
            # { term: { field: value } }
            values << term_value
          when Hash
            # { term: { field: { value: value } } }
            values << term_value[:value]
          end
        end

        if (terms_value = filter.dig(:terms, field)).present?
          # { terms: { field: [value1, value2, ...] } }
          values.concat terms_value
        end

        if (bool_terms_value = filter.dig(:bool)).present?
          # { bool: { should: [...terms...] } }
          values.concat Array(bool_terms_value[:should]).flat_map { |should| parse_values_from_filter_clause(should, field) }

          # Note: This does not handle the following bool filter shapes because we don't yet have a way
          # to construct these types of filters, and so there's no practical reason to implement them.
          # { bool: { must: [...terms...] } }
          # { bool: { must_not: [...terms...] } }
        end

        values
      end
    end
  end
end
