# typed: true
# frozen_string_literal: true

module Search
  module Filters
    # When the `agent_author_search_expansion` feature flag is enabled,
    # this filter expands an `author:X` query to also match PRs where X is
    # the assignee AND the author is a known agent bot (e.g. Copilot SWE agent).
    # This allows users to find PRs that agents created on their behalf via
    # `author:@me`.
    #
    # The generated ES query becomes (for single user/bot):
    #   { bool: { should: [
    #       <original author filter>,
    #       { bool: { must: [
    #           { term: { assignee_id: user_id } },
    #           { term: { author_id: agent_bot_id } }
    #       ] } }
    #   ], minimum_should_match: 1 } }
    #
    # This filter is temporary and will be removed when co-author reindexing ships.
    # Ref: https://github.com/github/core-ux/issues/1628
    class AgentAuthorExpansionFilter < ::Search::Filter
      def initialize(original_author_filter:, agent_bot_ids:)
        @original = original_author_filter
        @agent_bot_ids = agent_bot_ids
        @valid = @original.valid?
      end

      def blank?
        @original.blank?
      end

      def invalid_reason
        @original.invalid_reason
      end

      def must
        original_must = @original.must
        return original_must if original_must.nil? || @agent_bot_ids.empty?

        # Only expand for numeric user IDs (skip symbols like :exists/:missing)
        author_ids = Array(@original.bool_collection.must).grep(Integer)
        return original_must if author_ids.empty?

        # Skip expansion if the searched author IS an agent bot itself
        expanded_ids = author_ids - @agent_bot_ids
        return original_must if expanded_ids.empty?

        # Build expansion: assignee_id IN expanded_ids AND author_id IN agent_bot_ids.
        # `build_term_filter` (inherited from Search::Filter) auto-picks `term` vs `terms`
        # based on array length, matching the convention used by sibling filters.
        expansion = {
          bool: {
            must: [
              build_term_filter(:assignee_id, expanded_ids),
              build_term_filter(:author_id, @agent_bot_ids),
            ],
          },
        }

        # OR: original author match OR (assignee match AND bot author)
        { bool: { should: [original_must, expansion], minimum_should_match: 1 } }
      end

      def must_not
        @original.must_not
      end

      def should
        @original.should
      end
    end
  end
end
