# typed: strict
# frozen_string_literal: true

module Pulls
  module OpenStateClosedByPrefillExclusion
    extend ActiveSupport::Concern

    private

    sig { params(query: T::Array[T.untyped]).returns(T::Boolean) }
    def parsed_issues_query_include_open_state?(query)
      query.include?([:state, "open"]) || query.include?([:is, "open"])
    end

    sig { params(query: T.any(String, T::Array[T.untyped])).returns(T::Boolean) }
    def exclude_closed_by_prefill_for_open_state_query?(query)
      viewer = T.cast(T.unsafe(self).current_user, T.nilable(User))
      return false unless FeatureFlag.vexi.enabled?(:pulls_exclude_closed_by_on_state_open, viewer, default: false)

      parsed_query = T.let(
        query.is_a?(String) ? Search::Queries::IssueQuery.parse(query, viewer) : query,
        T::Array[T.untyped],
      )
      parsed_issues_query_include_open_state?(parsed_query)
    end
  end
end
