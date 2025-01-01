# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetProfilePins < Platform::Mutations::Base
      description "Pin items to a profile."

      minimum_accepted_scopes ["public_repo"]

      visibility :under_development

      argument :profile_owner_id, ID, "ID of the owner of the profile to modify.",
        required: true, loads: Interfaces::ProfileOwner
      argument :pinned_item_ids, [ID], "IDs of the pinned items in the order you want them to appear on your profile.", required: true, loads: Unions::PinnableItem

      field :profile_owner, Interfaces::ProfileOwner,
        "The owner of the profile that was updated.", null: true

      def resolve(profile_owner:, pinned_items:)
        unless profile_owner.can_pin_profile_items?(context[:viewer])
          error_message = "#{context[:viewer].display_login} cannot pin items on #{profile_owner.display_login}'s profile"
          raise Errors::Forbidden.new(error_message)
        end

        pinner = ProfilePinner.new(user: profile_owner, items: pinned_items,
                                   viewer: context[:viewer])
        pinner.async_pin.then do
          { profile_owner: profile_owner }
        end
      end
    end
  end
end
