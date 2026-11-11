# typed: true
# frozen_string_literal: true

module MemexProject::WebsocketDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { MemexProject }

  sig { returns(T.nilable(String)) }
  def live_updates_channel
    GitHub::WebSocket.signed_channel(memex_channel)
  end

  sig { returns(T.nilable(String)) }
  def presence_channel
    return if public?
    return unless owner.is_a?(Organization)

    GitHub::WebSocket.signed_presence_channel(
      memex_channel,
      GitHub::WebSocket.generate_authzd_attributes(self, view_live_update_authzd_attributes)
    )
  end

  # Public: Notify the project's websocket channel with the given data.
  #
  # data - a Hash of the notification data you want to send to the channel
  #
  # Returns nothing.
  def notify_memex_channel(data = {})
    GitHub::WebSocket.notify_memex_channel(self, memex_channel, data)
  end

  sig { returns(String) }
  private def memex_channel
    GitHub::WebSocket::Channels.memex(self)
  end
end
