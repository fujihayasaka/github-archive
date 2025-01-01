# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateSavedView < Platform::Mutations::Base
      description "Update a saved view for the current user."
      minimum_accepted_scopes ["user"]
      visibility :internal

      argument :saved_view_id, ID, "The Node ID of the saved view to update.", required: true, loads: Objects::SavedView
      argument :name, String, "The name of the new saved view", required: false
      argument :query, String, "The saved views to add to the new saved view", required: false
      argument :description, String, "The description of the new saved view", required: false
      argument :icon, Enums::SearchShortcutIcon, "The icon of the new saved view", required: false
      argument :color, Enums::SearchShortcutColor, "The color of the new saved view", required: false

      field :saved_view, Objects::SavedView, "The updated saved view.", null: true

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

      def resolve(saved_view:, **inputs)
        saved_view.name = inputs[:name] if inputs.key?(:name)
        saved_view.query = inputs[:query] if inputs.key?(:query)
        saved_view.description = inputs[:description] if inputs.key?(:description)
        saved_view.icon = inputs[:icon] if inputs.key?(:icon)
        saved_view.color = inputs[:color] if inputs.key?(:color)

        if saved_view.save
          {
            saved_view: saved_view,
          }
        else
          raise Errors::Unprocessable.new(saved_view.errors.full_messages.join(", "))
        end
      end
    end
  end
end
