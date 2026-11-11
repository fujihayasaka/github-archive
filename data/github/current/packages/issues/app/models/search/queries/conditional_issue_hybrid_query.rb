# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class ConditionalIssueHybridQuery < ConditionalIssueQuery
      SEMANTIC_WEIGHT = 2.0
      LEXICAL_WEIGHT  = 1.0

      MIN_SCORE_THRESHOLD = 0

      def initialize(opts = {}, &block)
        semantic_repo_ids = opts.delete(:semantic_repo_ids)
        super(opts)
        @empty_scope = false
        # When semantic_repo_ids is provided, the semantic component searches only
        # those repos (top N most recently updated) while the lexical component
        # uses the full scoped repo set. This avoids restricting lexical results
        # to 100 repos for org:/user:/owner:-scoped queries.
        semantic_opts = if semantic_repo_ids
          # The IDs from TopRepositories are already authorized — skip
          # rebuilding a full RepositoryFilter in the semantic sub-query.
          opts.merge(pre_resolved_repo_ids: semantic_repo_ids)
        elsif scoped_by_org_user_or_owner?
          # Org/user/owner scoped: derive KNN repo IDs from the lexical
          # component's already-built RepositoryFilter, eliminating the need
          # for a separate probe query and avoiding a redundant filter build
          # in the semantic sub-query.
          derived_ids = IssueSemanticHelper.select_top_repo_ids_from_filter(self.repository_filter)
          if derived_ids.empty?
            # No accessible repos — the semantic sub-query will be inert.
            # Mark the scope as empty so query_document falls back to pure
            # lexical, mirroring the legacy probe-empty behavior.
            @empty_scope = true
          end
          # Always pass pre_resolved_repo_ids — even when empty — so the
          # semantic sub-query uses the lightweight from_authorized_ids path
          # instead of rebuilding a full RepositoryFilter from scratch.
          opts.merge(pre_resolved_repo_ids: derived_ids)
        else
          opts
        end
        @semantic_query = ConditionalIssueSemanticQuery.new(semantic_opts, &block)
      end

      # Returns true if the query has a positive org:, user:, or owner: qualifier.
      sig { returns(T::Boolean) }
      def scoped_by_org_user_or_owner?
        [:org, :user, :owner].any? { |q| qualifiers.fetch(q, nil)&.must? }
      end

      # Returns true if the semantic component of the hybrid search fell back to lexical behavior
      def semantic_component_fell_back?
        # No text terms (qualifier-only query) or scoped query found zero
        # accessible repos — semantic search cannot produce candidates.
        return true if !@has_text_terms || @empty_scope

        @semantic_query&.fallback_to_non_semantic_behavior || false
      end

      def query_document
        # Fast-path: skip semantic query document/filter construction when the
        # semantic component cannot produce candidates (no text terms, or the
        # scoped query resolved to zero accessible repos).
        if !@has_text_terms || @empty_scope
          @semantic_query&.collect_contextual_fallback_reasons
          return super
        end

        doc = super

        # Get semantic query document first to trigger fallback detection
        semantic_doc = @semantic_query.query_document

        # If semantic query fell back to lexical, just use lexical
        # e.g. fell back due to non-issue target or quote being present
        if @semantic_query.fallback_to_non_semantic_behavior
          return doc
        end

        doc.merge(hybrid_query_doc(doc.delete(:query), semantic_doc[:query]))
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
      # (conditional_issue_hybrid_query) rather than the parent class name
      sig { override.params(exception: T.nilable(Exception)).returns(T::Array[String]) }
      def datadog_tags(exception = nil)
        super.tap do |tags|
          tags << "search_type:#{semantic_component_fell_back? ? "lexical" : "hybrid"}"
          tags << "dedicated_prs_index:#{@used_dedicated_prs_index || false}"
        end
      end

      def execute_results_log_metadata(results)
        super.merge(
          "gh.search.hybrid.search_type" => semantic_component_fell_back? ? "lexical" : "hybrid",
          "gh.search.hybrid.fallback_reasons" => fallback_reasons_for_metadata,
          "gh.search.query_scope" => query_scope_tag,
          "gh.search.dedicated_prs_index" => (@used_dedicated_prs_index || false).to_s,
        )
      end

      private

      # Internal: provides access to the semantic sub-query for testing/inspection only.
      sig { returns(T.nilable(ConditionalIssueSemanticQuery)) }
      attr_reader :semantic_query

      def custom_min_score
        return nil unless FeatureFlag.vexi.enabled?(:issues_semantic_fine_tune_query_filters, @current_user, default: false)
        return nil if top_level_qualifiers.empty?

        min_score_qualifier = top_level_qualifiers.find { |q| q.field == :"min-score" }
        return nil unless min_score_qualifier

        value = min_score_qualifier.collection.must&.first
        return nil unless value

        value.to_f
      end

      def custom_semantic_boost
        return nil unless FeatureFlag.vexi.enabled?(:issues_semantic_fine_tune_query_filters, @current_user, default: false)
        return nil if top_level_qualifiers.empty?

        boost_qualifier = top_level_qualifiers.find { |q| q.field == :"semantic-boost" }
        return nil unless boost_qualifier

        value = boost_qualifier.collection.must&.first
        return nil unless value

        value.to_f
      end

      def custom_lexical_boost
        return nil unless FeatureFlag.vexi.enabled?(:issues_semantic_fine_tune_query_filters, @current_user, default: false)
        return nil if top_level_qualifiers.empty?

        boost_qualifier = top_level_qualifiers.find { |q| q.field == :"lexical-boost" }
        return nil unless boost_qualifier

        value = boost_qualifier.collection.must&.first
        return nil unless value

        value.to_f
      end

      def fallback_reasons_for_metadata
        reasons = @semantic_query&.fallback_reasons&.map(&:to_s) || []
        reasons << "no_text_terms" if !@has_text_terms
        reasons << "empty_scope" if @empty_scope
        reasons.uniq.join(",").presence
      end

      def hybrid_query_doc(lexical_component, semantic_component)
        min_score_threshold = custom_min_score || MIN_SCORE_THRESHOLD
        semantic_weight = custom_semantic_boost || SEMANTIC_WEIGHT
        lexical_weight = custom_lexical_boost || LEXICAL_WEIGHT

        {
          query: {
            bool: {
              should: [
                add_boost_to_component(semantic_component, semantic_weight),
                add_boost_to_component(lexical_component, lexical_weight)
              ],
              minimum_should_match: 1
            }
          },
          min_score: min_score_threshold
        }
      end

      def add_boost_to_component(component, boost_value)
        return component unless component.is_a?(Hash) && component[:bool]

        component_copy = component.deep_dup
        component_copy[:bool][:boost] = boost_value
        component_copy
      end

      # Override to indicate state should be in post_filter when no aggregations
      def state_in_post_filter?
        aggregations.blank?
      end

      # Override to add state as post_filter when running without aggregations
      #
      # For KNN search (used by the semantic component), we exclude state from the KNN filter
      # portion of the query to ensure stable results. When aggregations are present, state is
      # applied as post_filter so that aggregations are calculated over the full result set before filtering.
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
    end
  end
end
