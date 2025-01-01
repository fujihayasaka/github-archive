# typed: true
# frozen_string_literal: true
module Platform
  module Mutations
    class UpdateStaffNote < Platform::Mutations::Base
      description "Updates a staff note for a user."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :staff_note_id, ID, "Global relay id of the staff note to update.", required: true, loads: Objects::StaffNote
      argument :body, String, "The new body of the staff note.", required: false
      argument :is_pinned, Boolean, "Whether or not the staff note is pinned.", required: false

      field :staff_note, Objects::StaffNote, "The updated staff note.", null: true

      exempt_from_tenant_context_requirement

      def self.async_api_can_modify?(permission, **inputs)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(staff_note:, **inputs)
        staff_note.body = inputs[:body] if inputs.key?(:body)

        if inputs.key?(:is_pinned)
          already_has_pinned_note = StaffNote.where(notable_id: staff_note.notable_id, is_pinned: true).any?

          if inputs[:is_pinned] && already_has_pinned_note
            raise Errors::Unprocessable.new "User already has a pinned note."
          else
            staff_note.is_pinned = inputs[:is_pinned]
          end
        end

        if staff_note.save
          { staff_note: staff_note }
        else
          raise Errors::Unprocessable.new(staff_note.errors.full_messages.join(", "))
        end
      end
    end
  end
end
