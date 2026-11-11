# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class ConditionalIssueSemanticQuery < ConditionalIssueQuery
      include IssueSemanticHelper

      attr_reader :fallback_to_non_semantic_behavior
      attr_reader :fallback_reasons
      attr_reader :with_validation

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :pre_resolved_repo_ids

      # Initialize the semantic query.
      # The @fallback_to_non_semantic_behavior flag tracks whether the query has fallen back
      # to lexical search behavior due to unsupported query patterns or errors.
      #
      # with_validation parameter defaults to true and controls query validation behavior.
      # Set to false to bypass validation for scenarios where query text may contain
      # characters that would normally be considered invalid syntax (e.g., markdown
      # formatting, code snippets, or user-generated content in issue bodies).
      #
      #   **When to use with_validation: false:**
      #   - Duplicate detection systems processing raw issue content with markdown syntax
      #   - Semantic search over user-generated text that may contain special characters
      #   - When you want to force semantic search without usual query restrictions
      #
      # **Security note:** Validation bypass only affects query parsing, not access controls.
      # Repository permissions, user authentication, and other security layers remain active.
      def initialize(opts = {})
        @with_validation = opts.fetch(:with_validation, true)
        @semantic_eligibility_pre_checked = opts.delete(:semantic_eligibility_pre_checked) || false
        @pre_resolved_repo_ids = T.let(opts.delete(:pre_resolved_repo_ids), T.nilable(T::Array[Integer]))
        @allow_prs = T.let(opts.delete(:allow_prs) || false, T::Boolean)
        super(opts)
        @fallback_to_non_semantic_behavior = false
        @fallback_reasons = T.let([], T::Array[Symbol])
      end

      # Override phrase assignment to support validation bypass for user-generated content.
      #
      # This override allows the semantic query to process raw text content that may contain
      # characters or patterns that would normally fail query validation (e.g., unbalanced
      # parentheses in markdown, code snippets, or other user-generated content).
      #
      # **Primary use case:** Duplicate detection systems that need to perform semantic
      # search on issue titles and bodies containing markdown formatting, code blocks,
      # or other syntax that would be rejected by standard query validation.
      #
      # **Example scenarios where validation bypass is needed:**
      # - Issue body: "Fix bug in `if (condition { ... }` block"   # Unbalanced braces
      # - Issue title: "Error with [markdown](link) syntax"        # Special characters
      # - Code snippets: "SELECT * FROM table WHERE (col = 'val'"   # SQL with unmatched parens
      #
      # When @with_validation is false, @is_valid is set to true regardless of content,
      # allowing semantic search to proceed without query syntax restrictions.
      sig { override.params(value: String).void }
      def phrase=(value)
        super
        unless @with_validation
          # If validation is disabled, we assume the query is valid and skip all checks that could set it to false.
          # This allows us to bypass the fallback logic in build_query_filter and always attempt semantic search,
          # even for queries that would normally be considered invalid (e.g., due to unsupported qualifiers or syntax).
          # Use with_validation: false when you want to force semantic search behavior without any of the usual restrictions.
          GitHub.dogstats.increment("search.advanced_search.validation_bypassed")
          @is_valid = true
          # Ensure invalid state is cleared when we bypass validation so the object state remains consistent.
          @invalid_reason = nil if defined?(@invalid_reason)
        end

      end

      # Returns true if the query is targeting issues only (not PRs or both).
      # This is determined by the index_type computed by ParsletQuery based on query filters
      # like is:issue, type:issue, linked:pr (which searches issues), etc.
      #
      # Semantic search should only run when explicitly filtering for issues.
      sig { returns(T::Boolean) }
      def targets_issues_only?
        @index_type == Search::ParsletQuery::IndexType::Issue
      end

      sig { params(qualifier: ParsletQuery::QueryQualifier, search_in_fields: T::Array[String]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def qualifier_to_query(qualifier, search_in_fields)
        if @fallback_to_non_semantic_behavior
          return super
        end

        # When the user specifies an in: qualifier, check if any requested fields
        # have semantic dense vectors. Title and body have vectors; comments does not.
        # If at least one semantic field is present, proceed with semantic search on
        # just those fields. Only fall back when none of the fields are semantic.
        # When the feature flag is off, fall back for any in: qualifier (legacy behavior).
        if search_in_fields.any?
          if FeatureFlag.vexi.enabled?(:semantic_search_in_qualifier, @current_user, default: false)
            semantic_fields = search_in_fields & IssueSemanticHelper::SEMANTIC_SEARCHABLE_FIELDS
            if semantic_fields.empty?
              set_fallback(:search_in_field_used)
              return super
            end
            # Narrow to only the fields that have dense vectors
            search_in_fields = semantic_fields
          else
            set_fallback(:search_in_field_used)
            return super
          end
        end

        escaped_query = escape_query(qualifier.query)

        # If there's any quoted text in the query, fall back to lexical search
        # This is because we assume the user wants exact matches for quoted text
        # and not semantic similarity
        if escaped_query.include?('"')
          set_fallback(:quoted_text)
          return super
        end

        # For KNN search, filters will be injected later in build_query_filter
        # For semantic search, no additional filters needed
        function_query = build_semantic_function_query(escaped_query, search_in_fields: search_in_fields)

        # If embedding generation failed, fall back to lexical search
        if function_query.nil?
          set_fallback(:embedding_generation_failed)
          return super
        end

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
      # For simple queries (query_depth <= 1), we inject filters into KNN clauses for optimal performance.
      # For complex nested queries (query_depth > 1), we fall back to the parent's non-semantic behavior
      # because the complex filter extraction logic is not needed for deeper nesting.
      #
      # KNN queries require filters within each knn clause for proper pre-filtering, not at the outer level.
      # This walks the query structure from the parent, extracts filters (repo, state, labels, etc.),
      # and injects them into each KNN clause's filter parameter.
      #
      # All these filters must be embedded in KNN clauses so Elasticsearch can efficiently
      # pre-filter documents before performing the expensive vector similarity calculation.
      def build_query_filter
        collect_contextual_fallback_reasons

        query_result = super

        return query_result if @fallback_to_non_semantic_behavior || !query_result

        # Get all filters that should be embedded in KNN clauses
        # These come from both the structured query (conditional_qualifiers) and the repo filter
        # State filters are excluded when no aggregations (will be applied as post_filter)
        qualifier_filters = extract_filters_from_query_result(query_result)
        return query_result if qualifier_filters.empty?

        # Inject these into all KNN clauses
        inject_qualifier_filters_into_knn(query_result, qualifier_filters)
      end

      # Override to add state as post_filter when running without aggregations
      #
      # For KNN search, we exclude state from the KNN filter portion of the query to ensure
      # stable results. When aggregations are present, state is applied as post_filter so that
      # aggregations are calculated over the full result set before filtering.
      #
      # To maintain consistency, we apply the same behavior (state as post_filter) even when
      # aggregations are not present. This means our KNN candidates may include documents
      # that will be filtered out by the post_filter, which could affect accuracy, but we
      # accept this trade-off for consistent behavior across queries with and without aggregations.
      def build_filter
        # When aggregations are present, use parent's implementation
        return super if aggregations.present?

        # When no aggregations, add state filter as post_filter if it exists in qualifiers
        return unless self.qualifiers[:state].present?

        builder = ::Search::FilterBuilder.new(self.qualifiers)
        filters = {}
        filters[:state] = builder.term_filter(:state)
        filter = Search::Filters::BoolFilter.new(filters)

        filter.build
      end

      # Override to route PR queries to the dedicated experiment index
      # when all scoped owners have the semantic_search_prs FF enabled.
      def index_for_type_param
        searcher = dedicated_prs_index_searcher
        if searcher
          @used_dedicated_prs_index = true
          return searcher
        end

        @used_dedicated_prs_index = false
        super
      end

      # Override to ensure this class logs with its own classname tag
      # (conditional_issue_semantic_query) rather than the parent class name
      sig { override.params(exception: T.nilable(Exception)).returns(T::Array[String]) }
      def datadog_tags(exception = nil)
        super.tap do |tags|
          tags << "search_type:#{fallback_to_non_semantic_behavior ? "lexical" : "semantic"}"
          tags << "dedicated_prs_index:#{@used_dedicated_prs_index || false}"
        end
      end

      def execute_results_log_metadata(results)
        super.merge(
          "gh.search.semantic.search_type" => fallback_to_non_semantic_behavior ? "lexical" : "semantic",
          "gh.search.semantic.fallback_reasons" => @fallback_reasons.map(&:to_s).join(",").presence,
          "gh.search.query_scope" => query_scope_tag,
          "gh.search.semantic.validation_bypassed" => (!@with_validation).to_s,
          "gh.search.dedicated_prs_index" => (@used_dedicated_prs_index || false).to_s,
        )
      end

      sig { params(reason: Symbol).void }
      def set_fallback(reason)
        # When the caller has already run the pre-check, skip redundant
        # fallback for non-embedding reasons (the pre-check already handled them).
        return if reason != :embedding_generation_failed && @semantic_eligibility_pre_checked

        primary = !@fallback_to_non_semantic_behavior
        @fallback_reasons << reason
        @fallback_to_non_semantic_behavior ||= true
        GitHub.dogstats.increment(
          "search.advanced_search.semantic_fallback",
          tags: custom_tags([
            "fallback_reason:#{reason}",
            "fallback_reason_primary:#{primary}"
          ])
        )
      end

      sig { void }
      def collect_contextual_fallback_reasons
        set_fallback(:no_text_terms) unless @has_text_terms

        # Check if query has nested bool qualifiers before building any queries
        set_fallback(:nested_bool_qualifier) if has_nested_bool_qualifiers?(self.conditional_qualifiers)

        # Fall back to lexical behavior if the query is not targeting a semantic-eligible type.
        # When the caller explicitly allows PR targets (e.g., REST API with PR rollout),
        # allow non-issue targets (e.g., is:pr, untyped) through without falling back.
        unless targets_issues_only? || @allow_prs
          set_fallback(:non_issue_target)
        end
      end

      private

      # Override to indicate state should be in post_filter when no aggregations
      def state_in_post_filter?
        aggregations.blank?
      end

      # Check if query has nested bool qualifiers (depth > 1)
      # Returns true if there are nested bool qualifiers, indicating we should fall back to non-semantic behavior
      sig { params(qualifier: T.nilable(ParsletQuery::BoolQualifier)).returns(T::Boolean) }
      def has_nested_bool_qualifiers?(qualifier)
        return false unless qualifier

        # Check if any of the qualifiers at this level are bool qualifiers (indicating nesting)
        qualifier.qualifiers.any? { |q| q.is_a?(ParsletQuery::BoolQualifier) }
      end

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
          # Skip state filters - state should only be filtered outside KNN clauses
          next if clause.dig(:term, :state)
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
