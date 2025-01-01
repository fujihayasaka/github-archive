# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateSavedCollection < Platform::Mutations::Base
      description "Create a saved collection for the current user."
      minimum_accepted_scopes ["user"]
      visibility :internal

      argument :name, String, "The name of the new collection", required: true
      argument :saved_views, [Inputs::DraftSavedView], "The saved views to add to the new collection", required: false
      argument :description, String, "The description of the new collection", required: false
      argument :icon, Enums::SearchShortcutIcon, "The icon of the new collection", required: false
      argument :color, Enums::SearchShortcutColor, "The color of the new collection", required: false
      argument :protected_type, Enums::SavedCollectionProtectedType,
        "Optional protected type for a system-created collection.", visibility: :internal, required: false

      field :saved_collection, Objects::SavedCollection, "The newly created saved collection.", null: true
      field :dashboard, Objects::UserDashboard, "The user dashboard the collection was added to.", null: true

      def self.async_api_can_modify?(permission, **_)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false
        )
      end

      def resolve(name:, **inputs)
        viewer = context[:viewer]
        dashboard = viewer.find_or_create_dashboard
        saved_views = inputs[:saved_views] || []
        if saved_views.length > Dashboard::SavedView::MAX_PER_COLLECTION
          raise Errors::Unprocessable.new("Cannot create a collection with more than #{Dashboard::SavedView::MAX_PER_COLLECTION} saved views.")
        end

        result = Dashboard::SavedCollection::Creator.execute(
          dashboard: dashboard,
          name: name,
          description: inputs[:description],
          saved_views: saved_views,
          icon: inputs[:icon],
          color: inputs[:color],
          protected_type: inputs[:protected_type],
        )

        dashboard.reload
        collection = result.collection

        if result.success?
          {
            dashboard: dashboard,
            saved_collection: collection,
          }
        else
          raise Errors::Unprocessable.new(result.errors.to_sentence)
        end
      end
    end
  end
end
