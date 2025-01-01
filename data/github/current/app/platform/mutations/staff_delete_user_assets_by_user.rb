# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class StaffDeleteUserAssetsByUser < Platform::Mutations::Base
      description "Allows staff to hard-delete(CDN, MySQL records and blob object) user assets by user id and assets ids."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :user_id, ID, "The Global Relay ID of the user to delete user assets.", loads: Objects::User, required: true
      argument :assets_ids, [ID], "The IDs of the user assets to delete.", required: false

      field :message, String, description: "A message confirming the result of the deletion.", null: true
      field :job_id, ID, description: "The ID of the job that was enqueued to delete the user assets.", null: true

      def self.async_api_can_modify?(permission, user:, **inputs)
        viewer_is_site_admin?(permission.viewer, name)
      end

      def resolve(user:, **inputs)
        job = DeleteUserAssetsByUserIdJob.perform_later(user_id: user.id, assets_ids: inputs[:assets_ids])

        {
          message: "User assets are being deleted in background.",
          job_id: job.job_id,
        }
      end
    end
  end
end
