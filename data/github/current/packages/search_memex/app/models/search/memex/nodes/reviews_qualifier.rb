# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      # Handles the `reviews:` qualifier (e.g. `reviews:approved`), filtering items by the review
      # state mirrored on each entry of the project's Reviewers field.
      class ReviewsQualifier < Qualifier
        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          return {} unless values.present?

          field = context.field_by_query_slug[:reviewers]
          return {} unless field.is_a?(MemexProjectColumn::Field::Reviewers)

          field.review_state_query_fragment(values:, is_negated: negated?, context:)
        end
      end
    end
  end
end
