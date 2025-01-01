# typed: true
# frozen_string_literal: true

module Search
  module Filters
    module Discussions
      # Custom filter for handling "answered" discussions while excluding "verified" discussions.
      # When searching for "answered" discussions, we need to ensure they are not "verified".
      class AnsweredFilter < ::Search::Filter

        # Returns a filter Hash that can be used in the `must` portion of an ES
        # boolean filter.
        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def must
          return unless bool_collection.must?

          answered_values = bool_collection.must
          return unless answered_values.include?(true)

          # When answered=true, we want answered discussions that are NOT verified
          answered_and_not_verified_filter
        end

        # Returns a filter Hash that can be used in the `must_not` portion of an ES
        # boolean filter.
        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def must_not
          return unless bool_collection.must_not?

          not_answered_values = bool_collection.must_not
          return unless not_answered_values.include?(true)

          # When we negate answered=true, we want to return a filter that when applied
          # as must_not, gives us discussions that are NOT (answered AND not verified)
          # So we need to return the positive condition: answered AND not verified
          answered_and_not_verified_filter
        end

        private

        # Returns the Elasticsearch filter for answered discussions that are not verified.
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def answered_and_not_verified_filter
          {
            bool: {
              must: [
                { term: { answered: true } }
              ],
              must_not: [
                { term: { verified: true } }
              ]
            }
          }
        end
      end
    end
  end
end
