# typed: true
# frozen_string_literal: true

module Orgs
  module Invitations
    class ReinstateView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      # Internal: Wraps an ActiveRecord scope to ensure we don't return an
      # unbound number of models in the view.
      class RestorableTypeView
        LIMIT = 100

        attr_reader :model_id, :singular, :plural, :phrase, :octicon,
          :label_attribute

        def initialize(scope:, model_id:, singular:, plural:, phrase:, octicon:, label_attribute: :name, limit: LIMIT)
          @scope = scope
          @model_id = model_id
          @singular = singular
          @plural = plural
          @phrase = phrase
          @octicon = octicon
          @label_attribute = label_attribute
          @limit = limit
        end

        def name
          return singular if count == 1
          plural
        end

        def count
          @count ||= @scope.count # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end

        def models
          @scope.limit(@limit)
        end
      end
    end
  end
end
