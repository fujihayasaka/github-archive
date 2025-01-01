# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SavedCollection < Platform::Objects::Base
      model_name "Dashboard::SavedCollection"
      description "A group of saved search views for a user"
      scopeless_tokens_as_minimum
      visibility :internal

      implements_node(templates: [[:dsc, :saved_collection_id]], as: "DSC", ready_date: "1970-01-01") do |saved_collection|
        {
          prefix: :dsc,
          saved_collection_id: saved_collection.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_dashboard.then do |dashboard|
          dashboard.async_user.then do |user|
            permission.access_allowed?(
              :read_user_dashboard,
              resource: user,
              current_repo: nil,
              current_org: nil,
              allow_integrations: false,
              allow_user_via_granular_actor: false
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_dashboard.then do |dashboard|
          dashboard.async_user.then do |user|
            permission.viewer == user
          end
        end
      end

      field :name, String, "The name of the saved collection.", null: false
      field :description, String, "The description of the saved collection.", null: false
      field :icon, Enums::SearchShortcutIcon, "The icon of the saved collection.", null: false
      field :color, Enums::SearchShortcutColor, "The color of the saved collection.", null: false

      field(
        :saved_views,
        Connections.define(Objects::SavedView),
        description: "The saved views belonging to this saved collection",
        null: false,
        visibility: :internal, connection: true
      ) do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :order_by, Inputs::SavedViewOrder, "Ordering options for saved views.", required: false,
          default_value: { field: "created_at", direction: "DESC" }
      end

      def saved_views(order_by:)
        object.async_saved_views(order_by: order_by).then do |saved_views|
          ArrayWrapper.new(saved_views)
        end
      end
    end
  end
end
