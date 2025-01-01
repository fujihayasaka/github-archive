# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateSavedView < Platform::Mutations::Base
      description "Create a saved view for the current user."
      minimum_accepted_scopes ["user"]
      visibility :internal

      argument :collection_id, ID, "The Node ID of the saved collection to create the saved view in.", required: true, loads: Objects::SavedCollection
      argument :name, String, "The name of the new saved view", required: true
      argument :query, String, "The query of the new saved view", required: true
      argument :description, String, "The description of the new saved view", required: false
      argument :icon, Enums::SearchShortcutIcon, "The icon of the new saved view", required: false
      argument :color, Enums::SearchShortcutColor, "The color of the new saved view", required: false

      field :saved_view, Objects::SavedView, "The newly created saved view.", null: true

      def self.async_api_can_modify?(permission, collection:, **_)
        collection.async_dashboard.then do |dashboard|
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

      def resolve(collection:, name:, query:, **inputs)
        saved_view = Dashboard::SavedView.new(
          saved_collection: collection,
          name: name,
          query: query,
        )

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
