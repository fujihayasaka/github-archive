# typed: true
# frozen_string_literal: true
module Platform
  module Mutations
    class AddStaffNote < Platform::Mutations::Base
      description "Adds a staff note for a user."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :user_id, ID, "Global relay id of the user to add a staff note for.", required: true, loads: Objects::User
      argument :body, String, "Body of the staff note.", required: true
      argument :is_pinned, Boolean, "Whether the staff note is pinned.", required: false, default_value: false

      field :id, String, "Global relay id of staff note that was added.", null: true

      def self.async_api_can_modify?(permission, **inputs)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(user:, **inputs)
        if inputs[:is_pinned]
          already_has_pinned_note = StaffNote.where(notable: user, is_pinned: true).any?

          if already_has_pinned_note
            raise Errors::Unprocessable.new "User already has a pinned note."
          end
        end

        staff_note = StaffNote.create(user: context[:viewer], notable: user, note: inputs[:body], is_pinned: inputs[:is_pinned])
        { id: staff_note.global_relay_id }
      end
    end
  end
end
