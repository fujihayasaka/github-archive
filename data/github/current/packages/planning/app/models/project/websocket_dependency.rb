# typed: true
# frozen_string_literal: true

module Project::WebsocketDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Project }

  # Public: Sends a notification to any websocket channels that are listening
  # for new cards on a project.
  #
  # payload - A hash of information to pass to the channel.
  #   :is_project_activity - flag used to determine if new activity link should
  #                          be shown. (default: true)
  def notify_add_cards_channel(payload)
    add_cards_channel = GitHub::WebSocket::Channels.project_add_cards_link(id)

    # Allow caller to set is_project_activity if needed
    payload.reverse_merge!(is_project_activity: true)

    GitHub::WebSocket.notify_project_channel(self, add_cards_channel, payload)

    # Update triage/search results as well
    notify_subscribers(payload)
  end

  def notify_metadata_subscribers(locked_by: nil)
    payload = {
      name: name,
      locked: locked? ? locked_by : false,
      project_migration: project_migration_payload,
    }
    GitHub::WebSocket.notify_project_channel(
      self,
      metadata_channel,
      payload,
    )
  end

  def notify_subscribers(payload)
    payload.update(
      state: as_json,
      client_uid: GitHub.context[:client_uid],
    )

    # Allow caller to set is_project_activity if needed
    unless payload.has_key?(:is_project_activity)
      payload[:is_project_activity] = true
    end

    GitHub::WebSocket.notify_project_channel(self, channel, payload)
  end

  def channel
    GitHub::WebSocket::Channels.project(self)
  end

  def metadata_channel
    GitHub::WebSocket::Channels.project_metadata(self)
  end
end
