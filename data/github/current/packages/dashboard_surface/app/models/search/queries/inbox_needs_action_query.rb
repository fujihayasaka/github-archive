# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class InboxNeedsActionQuery < Search::Queries::ConditionalIssueQuery
      DEFAULT_UPDATED_GTE = "now-30d/d"

      sig { params(opts: T::Hash[Symbol, T.untyped]).void }
      def initialize(opts = {})
        @scope_phrase = T.let(opts.fetch(:scope_phrase, "").to_s, String)
        super(opts.merge(phrase: "", query: ""))
      end

      sig { override.returns(T::Hash[T.untyped, T.untyped]) }
      def query_document
        {
          query: {
            bool: {
              filter: base_filters,
              minimum_should_match: 1,
              should: should_clauses,
            },
          },
          sort: [{ updated_at: "desc" }],
          _source: source_fields,
          from: offset,
          size: per_page,
        }
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      private def base_filters
        filters = T.let([
          { term: { state: "open" } },
          { term: { archived: false } },
          { term: { draft: false } },
        ], T::Array[T::Hash[Symbol, T.untyped]])

        repo_filter = scoped_repo_filter
        filters << repo_filter if repo_filter

        # Only add updated_at filter if the scope phrase includes an updated qualifier
        if parsed_scope_terms.any? { |term| term.is_a?(Array) && term[0].to_sym == :updated && !term[2] }
          filters << { range: { updated_at: { gte: updated_gte } } }
        end

        filters
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      private def should_clauses
        viewer_id = current_user&.id || 0
        copilot_id = copilot_bot_id

        [
          {
            bool: {
              _name: "changes_requested",
              filter: [
                { term: { author_id: viewer_id } },
                { term: { review_status: "changes_requested" } },
              ],
            },
          },
          {
            bool: {
              _name: "failing_checks",
              filter: [
                { term: { author_id: viewer_id } },
                { term: { status: "failure" } },
              ],
            },
          },
          {
            bool: {
              _name: "agent_blocked",
              filter: [
                { term: { author_id: copilot_id } },
                { terms: { assignee_id: [viewer_id] } },
                {
                  bool: {
                    minimum_should_match: 1,
                    should: [
                      { term: { status: "failure" } },
                      { term: { review_status: "changes_requested" } },
                    ],
                  },
                },
              ],
            },
          },
        ]
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      private def scoped_repo_filter
        repo_values = scope_repo_values
        return nil if repo_values.empty?

        qualifiers = Hash.new { |h, k| h[k] = ::Search::ParsedQuery::BoolCollection.new(k) }
        repo_values.each { |value| qualifiers[:repo].must(value) }

        builder = ::Search::FilterBuilder.new(qualifiers)
        repo_filter = builder.repository_filter(
          current_user,
          nil,
          "issues",
          user_session: user_session,
          ip: remote_ip,
        )

        ::Search::Filters::BoolFilter.new(repo_id: repo_filter).build
      end

      sig { returns(T::Array[String]) }
      private def scope_repo_values
        values = parsed_scope_terms.filter_map do |term|
          next unless term.is_a?(Array)

          key, value, negated = term
          next unless key.to_sym == :repo && !negated

          value.to_s.strip.presence
        end

        values.uniq
      end

      sig { returns(String) }
      private def updated_gte
        updated_clause = parsed_scope_terms.find do |term|
          term.is_a?(Array) && term[0].to_sym == :updated && !term[2]
        end
        return DEFAULT_UPDATED_GTE if updated_clause.nil?

        value = updated_clause[1].to_s
        return value.delete_prefix(">=") if value.start_with?(">=")

        value
      end

      sig { returns(Integer) }
      private def copilot_bot_id
        Apps::Privileged.integration(:copilot_swe_agent)&.bot&.id || 0
      end

      sig { returns(T::Array[T.any(String, T::Array[T.untyped])]) }
      memoize private def parsed_scope_terms
        Search::ParsedQuery.parse(
          @scope_phrase,
          terms: [:repo, :updated],
          normalize_quotes: false,
        )
      end
    end
  end
end
