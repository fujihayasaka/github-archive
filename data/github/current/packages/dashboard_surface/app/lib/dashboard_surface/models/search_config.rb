# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Models
    class SearchConfig
      include DateMacroHelper
      include UrlHelpers

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
        "needs-action" => NamedQuery.new(
          queries: [
            Queries::NEEDS_ACTION_CHANGES_REQUESTED_QUERY,
            Queries::NEEDS_ACTION_FAILING_CHECKS_QUERY,
            Queries::NEEDS_ACTION_AGENT_BLOCKED,
          ],
        ),
        "ready-to-merge" => NamedQuery.new(
          queries: [Queries::READY_TO_MERGE_QUERY_WITH_REVIEW],
          post_filter: :post_filter_ready_to_merge,
        ),
        "review-requested" => NamedQuery.new(
          queries: [Queries::REVIEW_REQUESTED_QUERY],
        ),
        "team-review-requested" => NamedQuery.new(
          queries: [Queries::TEAM_REVIEW_REQUESTED_QUERY],
        ),
        "your-drafts" => NamedQuery.new(
          queries: [Queries::YOUR_DRAFTS_QUERY],
        ),
        "waiting-for-review" => NamedQuery.new(
          queries: [Queries::WAITING_FOR_REVIEW_QUERY],
        ),
        "merge-queue" => NamedQuery.new(
          queries: [Queries::MERGE_QUEUE_QUERY],
        ),
      }.freeze, T::Hash[String, NamedQuery])

      # Non-inbox queries
      PULLS_QUERIES = T.let({
        "authored" => Queries::AUTHORED_QUERY,
        "assigned" => Queries::ASSIGNED_QUERY,
        "involves" => Queries::INVOLVES_QUERY,
        "reviews" => Queries::REVIEW_QUERY,
      }.freeze, T::Hash[String, String])

      sig { returns(T.untyped) }
      attr_reader :params, :path

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { params(params: T.untyped, path: String, current_user: T.nilable(User)).returns(SearchConfig) }
      def self.from_params(params, path, current_user: nil)
        new(params, path, current_user: current_user)
      end

      sig { params(params: T.untyped, path: String, current_user: T.nilable(User)).void }
      def initialize(params, path, current_user: nil)
        @params = params
        @path = path
        @current_user = current_user
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
          key = path_query_key
          return saved_view_query || default_query unless key

          pulls_query_for(key.to_s)
        end
      end

      sig { returns(T.nilable(String)) }
      private def saved_view_query
        saved_view_id = params[:saved_view_id]
        user = current_user
        return unless saved_view_id.present? && user

        shortcut = user.dashboard&.shortcuts&.find_by(id: saved_view_id)
        shortcut&.compressed_query.presence
      end

      sig { returns(T.nilable(Symbol)) }
      private def path_query_key
        case path
        when all_pulls_authored_path                                 then :authored
        when all_pulls_assigned_path                                 then :assigned
        when all_pulls_involves_path, all_pulls_mentioned_path       then :involves
        when all_pulls_reviews_path, all_pulls_review_requested_path then :reviews
        end
      end

      sig { returns(T.nilable(NamedQuery)) }
      def named_query_def
        key = composite_key
        return nil if key.nil?

        if key == "merge-queue"
          NamedQuery.new(queries: [Queries.merge_queue_query_for(current_user)])
        else
          NAMED_QUERIES[key]
        end
      end


      sig { returns(T.nilable(String)) }
      private def composite_key
        params[:q].to_s.strip.presence
      end

      sig { returns(String) }
      private def default_query
        Queries.default_query_for(current_user)
      end

      sig { params(key: String).returns(String) }
      private def pulls_query_for(key)
        if key == "authored"
          Queries.authored_query_for(current_user)
        else
          PULLS_QUERIES.fetch(key)
        end
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
