# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PinnedItems < Resolvers::Base
      type Connections.define(Unions::PinnableItem), null: false

      argument :types, [Enums::PinnableItemType],
        "Filter the types of pinned items that are returned.", required: false

      def resolve(types: nil)
        if context[:viewer].is_a?(User) && object.private_profile_for?(context[:viewer])
          return ArrayWrapper.new
        end

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

        # Object can be a User or Organization
        object.async_pinned_items(viewer: context[:viewer], types: types).then do |items|
          ArrayWrapper.new(items)
        end
      end
    end
  end
end
