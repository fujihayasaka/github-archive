# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::Mobile
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :mobile_updates_url, Scalars::URI, "A WebSocket URL for connecting to receive updates.",
    null: true, required_capabilities: [:mobile_only_schema_mask, :subscribe_alive_events]

    def mobile_updates_url
      GitHub::WebSocket.websocket_url(nil, @context[:viewer].id)
    end

    field :mobile_capabilities, resolver: Resolvers::MobileCapabilities, required_capabilities: [:mobile_only_schema_mask], description: "Returns all capabilities for the mobile clients"

    field :viewer_updates_channel, String, "Channel value for subscribing to live updates.", null: true, required_capabilities: [:mobile_only_schema_mask, :subscribe_alive_events] do
      argument :name, Enums::UserPubSubTopic, "The name of the channel to use.", required: true
    end

    def viewer_updates_channel(**arguments)
      return nil unless @context[:viewer]

      case arguments[:name]
      when "notifications_changed"
        GitHub::WebSocket::Channels.signed_notifications_changed(@context[:viewer])
      when "marked_read"
        GitHub::WebSocket::Channels.signed_marked_as_read(@context[:viewer])
      end
    end
  end
end
