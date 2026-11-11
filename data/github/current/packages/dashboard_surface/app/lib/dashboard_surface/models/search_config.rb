# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Models
    class SearchConfig
      include DateMacroHelper

      DEFAULT_QUERY = "is:pr author:@me archived:false sort:updated-desc state:open"

      # Named ES queries for each inbox section.
      # Single-query sections have one-element arrays; composite sections have multiple.
      READY_TO_MERGE_QUERY = "is:pr author:@me state:open -is:draft archived:false sort:updated-desc"
      REVIEW_REQUESTED_QUERY = "is:pr user-review-requested:@me state:open archived:false"
      TEAM_REVIEW_REQUESTED_QUERY = "is:pr team-review-requested-user:@me state:open archived:false"
      MERGE_QUEUE_QUERY = "is:pr is:queued state:open (author:@me OR (author:@copilot assignee:@me)) archived:false sort:updated-desc"

      # "Needs action" captures PRs that require attention, including those with
      # changes requested, failing checks, or agent-owned PRs that are blocking
      # you. Because ES qualifiers don't support OR across fields in a single
      # clause, we execute multiple sub-queries server-side (including the
      # agent-blocked case, which includes its own OR) and merge/deduplicate the
      # results.
      NEEDS_ACTION_CHANGES_REQUESTED_QUERY = "is:pr author:@me state:open review:changes_requested archived:false sort:updated-desc"
      NEEDS_ACTION_FAILING_CHECKS_QUERY = "is:pr author:@me state:open status:failure archived:false sort:updated-desc"
      NEEDS_ACTION_AGENT_BLOCKED = "is:pr -is:closed archived:false author:@copilot assignee:@me (status:failure OR review-requested:@me) sort:updated-desc"
      NEEDS_ACTION_ACTIVE_REVIEW_QUERY = "is:pr author:@me state:open review:required comments:>0 archived:false sort:updated-desc"

      # Definition for a named inbox query with its ES sub-queries and optional
      # post-filter. The post_filter symbol names a method on the controller that
      # receives the Issue array after ES and returns a filtered/augmented array.
      class NamedQuery < T::Struct
        const :queries, T::Array[String]
        const :post_filter, T.nilable(Symbol), default: nil
      end

      # Unified map of named queries → ES query strings + optional post-filter.
      # Each key is an inbox section ID.
      # Composite sections (e.g. "needs-action") have multiple sub-queries that are
      # executed and merged/deduplicated.
      # Sections with a post_filter will have results augmented in the controller
      # after ES returns — use this for checks that ES can't express (merge state,
      # live review decisions, etc.).
      NAMED_QUERIES = T.let({
        "ready-to-merge" => NamedQuery.new(
          queries: [READY_TO_MERGE_QUERY],
          post_filter: :post_filter_ready_to_merge,
        ),
        "needs-action" => NamedQuery.new(
          queries: [NEEDS_ACTION_CHANGES_REQUESTED_QUERY, NEEDS_ACTION_FAILING_CHECKS_QUERY, NEEDS_ACTION_AGENT_BLOCKED, NEEDS_ACTION_ACTIVE_REVIEW_QUERY],
        ),
        "review-requested" => NamedQuery.new(
          queries: [REVIEW_REQUESTED_QUERY],
        ),
        "team-review-requested" => NamedQuery.new(
          queries: [TEAM_REVIEW_REQUESTED_QUERY],
        ),
        "merge-queue" => NamedQuery.new(
          queries: [MERGE_QUEUE_QUERY],
        ),
      }.freeze, T::Hash[String, NamedQuery])

      sig { returns(T.untyped) }
      attr_reader :params

      sig { params(params: T.untyped).returns(SearchConfig) }
      def self.from_params(params)
        new(params)
      end

      sig { params(params: T.untyped).void }
      def initialize(params)
        @params = params
      end

      sig { returns(String) }
      def es_query
        replace_today_macro(query_value)
      end

      sig { returns(String) }
      private def query_value
        if params[:q].present?
          key = params[:q].to_s.strip
          named = named_query_def
          named ? named.queries.first.to_s : key
        else
          DEFAULT_QUERY
        end
      end

      sig { returns(T.nilable(NamedQuery)) }
      def named_query_def
        key = composite_key
        return nil if key.nil?

        NAMED_QUERIES[key]
      end

      sig { returns(T.nilable(String)) }
      private def composite_key
        params[:q].to_s.strip.presence
      end

      sig { returns(Integer) }
      def maximum_result_limit
        25
      end

      sig { returns(Integer) }
      def page
        (params[:page] || 1).to_i
      end
    end
  end
end
