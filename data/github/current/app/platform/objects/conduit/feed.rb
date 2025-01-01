# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Conduit::Feed < Platform::Objects::Base
      description "A user's dashboard feed."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      def self.async_api_can_access?(permission, object)
        object.async_user.then do |user|
          if object.for_you_context?
            permission.access_allowed?(
              :read_user_dashboard,
              resource: user,
              current_repo: nil,
              current_org: nil,
              allow_integrations: false,
              allow_user_via_granular_actor: false
            )
          elsif object.profile_activity_context?
            !user.private_profile_for?(permission.viewer)
          end
        end
      end

      def self.async_viewer_can_see?(permission, object)
        object.async_user.then do |user|
          if object.for_you_context?
            permission.viewer == user
          elsif object.profile_activity_context?
            !user.private_profile_for?(permission.viewer)
          else
            false
          end
        end
      end

      def self.define_item_type_enum(union_type)
        conn_name = self.graphql_name

        Class.new(Platform::Enums::Base) do
          graphql_name "#{conn_name}ItemType"
          description "A list of item types to include in the response"

          union_type.possible_types.each do |type|
            value type.graphql_name.underscore.upcase, type.description, value: type,
              visibility: type.visibility.include?(:public) ? :public : :internal
          end
        end
      end

      def self.define_item_types_argument(union_type, field)
        arg = field.argument_class.new(
          :item_types,
          [define_item_type_enum(union_type)],
          "Filter timeline items by type.",
          required: false,
          owner: field,
          default_value: [],
        )
        field.add_argument(arg)
      end

      field :items, Connections.define(Unions::FeedItem), "A list of feed items", null: false do
        self.owner.define_item_types_argument(Unions::FeedItem, self)
      end

      # Authorization checks for feed items happen in Conduit. Running additional auth checks
      # is redundant and should be avoided. It can be assumed that any item that made it this
      # far should be visible to the viewer.
      #
      # https://github.com/github/conduit/blob/master/internal/feedauthz/authz.go#L98-L109
      def items(**arguments)
        map = arguments[:item_types].
          each_with_object(Hash.new(false)) { |item, hash| hash[item] = true }

        item_types = Array(arguments[:item_types])
        prevent_mobile_multi_announcements = GitHub.flipper["prevent_mobile_multi_announcements"].enabled?
        items = object.items.select do |item|
          next false unless item.class.supports_graphql?

          # TODO: Remove this once the UI is built out for multiple announcements in mobile
          if prevent_mobile_multi_announcements && item.is_a?(::Conduit::FeedItem::CreatedDiscussion)
            next false unless item.universe_announcement?
          end

          next true if item_types.empty?

          gql_class = item.class.const_get(:GRAPHQL_TYPE)
          map[gql_class]
        end

        ArrayWrapper.new(items)
      end

      field :filters, [Objects::Conduit::FeedFilter], "The filter settings for this feed", null: true

      def filters
        return if object.profile_activity_context?

        object.async_user.then do |user|
          user.async_for_you_feed_filter_settings.then do |settings|
            filter = ::Conduit::FeedFilter.new(settings&.values, viewer: user)

            groups = ::Conduit::FeedFilter.available_groups(viewer: user)
            groups.map do |(name, _)|
              Models::Conduit::FeedFilter.new(
                name: name,
                is_enabled: filter.includes_group?(name),
                user: user
              )
            end
          end
        end
      end
    end
  end
end
