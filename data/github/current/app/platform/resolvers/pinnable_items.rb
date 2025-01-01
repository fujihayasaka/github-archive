# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PinnableItems < Resolvers::Base
      type Connections.define(Unions::PinnableItem), null: false

      argument :types, [Enums::PinnableItemType],
        "Filter the types of pinnable items that are returned.", required: false

      def resolve(types: nil)
        # Integrations cannot access gists via the API, so only include them when it's a user making
        # the request:
        gists_allowed = context[:viewer].is_a?(User) && context[:viewer].user?

        unless types
          default_types = ["Repository"]
          default_types << "Gist" if gists_allowed
          types = default_types
        end

        if types.include?("Gist") && !gists_allowed
          raise Platform::Errors::Internal, "Gists cannot be accessed by an integration"
        end

        pinner = ProfilePinner.new(user: object, viewer: context[:viewer])
        pinner.async_sorted_pinnable_items(types: types).then do |items|
          ArrayWrapper.new(items)
        end
      end
    end
  end
end
