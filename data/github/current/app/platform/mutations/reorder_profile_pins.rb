# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReorderProfilePins < Platform::Mutations::Base
      description "Reorder the items pinned to the specified profile."

      minimum_accepted_scopes ["public_repo"]

      visibility :under_development

      argument :profile_owner_id, ID, "ID of the owner of the profile to modify.",
        required: true, loads: Interfaces::ProfileOwner
      argument :pinned_item_ids, [ID], "IDs of the pinned items in the order you want them to appear on your profile.",
        required: true, loads: Unions::PinnableItem

      field :profile_owner, Interfaces::ProfileOwner,
        "The owner of the profile that was updated.", null: true

      def resolve(profile_owner:, pinned_items:)
        unless profile_owner.can_pin_profile_items?(context[:viewer])
          error_message = "#{context[:viewer].display_login} cannot reorder pins on #{profile_owner}'s profile"
          raise Errors::Forbidden.new(error_message)
        end

        profile = profile_owner.profile
        profile&.reorder_pinned_items(pinned_items)

        { profile_owner: profile_owner }
      end
    end
  end
end
