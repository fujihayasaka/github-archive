# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserDashboard < Platform::Objects::Base
      description "A user's dashboard."

      implements_node templates: [[:ud, :user_id, :id]], as: "UD", ready_date: Platform::Helpers::GlobalId::COHORT_3 do |dashboard|
        {
          prefix: :ud,
          user_id: dashboard.user_id,
          id: dashboard.id
        }
      end

      minimum_accepted_scopes ["user"]
      mobile_only true

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_user.then do |user|
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

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_user.then do |user|
          permission.viewer == user
        end
      end

      field :user, Objects::User, "The user this dashboard belongs to.", null: false
      field :selected_teams, Connections.define(Objects::Team), "The teams the user has selected to see on their dashboard.", null: false do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :order_by, Inputs::TeamOrder, "Ordering options for selected teams.", required: false, default_value: { field: "name", direction: "ASC" }
      end

      field :shortcuts, Connections.define(Objects::SearchShortcut), "The saved searched shortcuts for this dashboard", null: false do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :search_types, [Enums::SearchShortcutType], <<~DESC, required: false
          The types of search shortcuts to return. If not provided, all shortcuts are returned.
        DESC
      end

      def selected_teams(order_by:)
        object.selected_teams.order("teams.#{order_by.field} #{order_by.direction}")
      end

      def shortcuts(search_types: nil)
        if search_types.nil? # No value provided or explicit nil.
          object.shortcuts
        elsif search_types.empty? # Explicit empty array.
          object.shortcuts.none
        else # Some search types were passed in.
          object.shortcuts.where(search_type: search_types)
        end
      end

      field :nav_links, [Objects::UserDashboardNavLink], "The mobile navigation links for this dashboard", null: false

      def nav_links
        object.async_mobile_nav_links
      end

      field :feed, Objects::Conduit::Feed, "The home feed for this dashboard", null: false

      def feed
        object.async_user.then do |user|
          user.async_for_you_feed_filter_settings.then do |settings|
            filter = ::Conduit::FeedFilter.new(settings&.values, viewer: user)
            cap_filter = @context[:cap_filter]
            exp_context = ::Conduit::ExpContext.new(user)

            ::Conduit.for_you_feed(user: object.user, filter: filter, exp_context:, cap_filter:)
          end
        end
      end

      field(
        :saved_collections,
        Connections.define(Objects::SavedCollection),
        description: "The groups of saved views belonging to this dashboard",
        null: false,
        visibility: :internal,
        connection: true
      ) do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :order_by, Inputs::SavedCollectionOrder, "Ordering options for saved collections.", required: false,
          default_value: { field: "created_at", direction: "DESC" }
      end

      def saved_collections(order_by:)
        object.async_saved_collections(order_by: order_by).then do |saved_collections|
          ArrayWrapper.new(saved_collections)
        end
      end

      field :reviews_collection, Objects::SavedCollection, "The collection of reviews belonging to this dashboard", null: true

      def reviews_collection
        object.async_reviews_collection
      end
    end
  end
end
