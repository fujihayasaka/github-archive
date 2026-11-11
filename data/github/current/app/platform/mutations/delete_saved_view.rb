# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteSavedView < Platform::Mutations::Base
      description "Delete a saved view for the current user."
      minimum_accepted_scopes ["user"]
      visibility :internal

      argument :saved_view_id, ID, "The Node ID of the saved view to delete.", required: true, loads: Objects::SavedView

      field :saved_view, Objects::SavedView, "The saved view that was deleted.", null: true

      def self.async_api_can_modify?(permission, saved_view:, **_)
        saved_view.async_dashboard.then do |dashboard|
          dashboard.async_user.then do |user|
            permission.access_allowed?(
              :update_user,
              resource: user,
              current_repo: nil,
              current_org: nil,
              allow_integrations: false,
              allow_user_via_granular_actor: false
            )
          end
        end
      end

      def resolve(saved_view:)
        if saved_view.destroy
          { saved_view: saved_view }
        else
          raise Errors::Unprocessable.new("Could not destroy saved view.")
        end
      end
    end
  end
end
