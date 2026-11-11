# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ProjectCardsBackwardsCompatibilityPending < Resolvers::ProjectCards
      def resolve(**arguments)
        if object.is_a?(Project)
          # TODO - indec - watch this until it's consistently zero then remove the
          # pendingCards connection and @backwards_compatibility_pending nonsense
          GitHub.dogstats.increment("projects.deprecated_graphql_pendingcards_used")
        end
        context[:backwards_compatibility_pending] = true
        super
      end
    end
  end
end
