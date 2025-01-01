# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class BlockModels < Platform::Mutations::Base
      description "Disable Models access via blocking the user"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :user_id, ID, "Global relay id of the user to add a staff note for", required: true, loads: Objects::User
      argument :reason, String, "Reason for disabling the user", required: true
      argument :staff_note, String, "Adds a staff note to the repository owner", required: false

      field :id, String, "Global relay id of the account that was blocked", null: true

      def self.async_api_can_modify?(permission, **inputs)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(user:, **inputs)
        reason     = inputs[:reason]
        staff_note = inputs[:staff_note]

        GitHub.logger.with_named_tags("gh.user.id" => user.id) do
          GitHub.logger.info("Processing models block for user")

          if GitHubModels.domain.blocks.exists?(user)
            raise Errors::Unprocessable.new "User is already blocked from using Models."
          else
            if staff_note.present? && !GitHub.enterprise?
              StaffNote.create(
                user: context[:viewer],
                notable: user,
                note: staff_note,
              )
            end
            GitHubModels.domain.blocks.create(
              actor: context[:viewer],
              user: user,
              reason: "#{reason} #{staff_note}".strip,
            )
            { id: user.global_relay_id }
          end
        end
      end
    end
  end
end
