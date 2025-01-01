# typed: false
# frozen_string_literal: true

module Platform
  module Interfaces
    module ProfileOwner
      include Platform::Interfaces::Base

      description "Represents any entity on GitHub that has a profile page."

      field :id, ID, description: "The Node ID of the ProfileOwner object", method: :global_relay_id, null: false

      field :login, String, "The username used to login.", null: false

      field :name, String, null: true, description: "The public profile name."

      field :email, String, null: true, description: "The public profile email."

      field :location, String, null: true, description: "The public profile location."

      field :website_url, Scalars::URI, null: true, description: "The public profile website URL."

      field :item_showcase, Objects::ProfileItemShowcase,
        description: "Showcases a selection of repositories and gists that the profile owner has either curated or that have been selected automatically based on popularity.",
        null: false

      def item_showcase
        ::ProfileItemShowcase.new(user: @object, viewer: @context[:viewer])
      end

      field :pinned_items, resolver: Resolvers::PinnedItems,
        description: "A list of repositories and gists this profile owner has pinned to their profile",
        connection: true

      field :pinned_items_remaining, Int, null: false,
        description: "Returns how many more items this profile owner can pin to their profile."

      field :any_pinnable_items, Boolean,
        description: "Determine if this repository owner has any items that can be pinned to their profile.",
        null: false do
        argument :type, Enums::PinnableItemType, "Filter to only a particular kind of pinnable item.", required: false
      end

      def any_pinnable_items(type: nil)
        types = if type
          [type]
        else
          ProfilePin.pinned_item_types.keys
        end
        @object.async_any_pinnable_items?(viewer: @context[:viewer], types: types)
      end

      field :pinnable_items, resolver: Resolvers::PinnableItems,
        description: "A list of repositories and gists this profile owner can pin to their profile.",
        connection: true, max_page_size: 250

      field :viewer_can_change_pinned_items, Boolean,
        description: "Can the viewer pin repositories and gists to the profile?",
        null: false

      def viewer_can_change_pinned_items
        @object.can_pin_profile_items?(@context[:viewer])
      end
    end
  end
end
