# typed: true
# frozen_string_literal: true

module Site
  module Header
    class NotificationsButtonComponent < ApplicationComponent
      include AnalyticsHelper
      include KeyboardShortcutsHelper
      include GitHub::ResilienceMixin

      # @param use_header_redesign [Symbol|Boolean] Whether to use the system's header redesign setting
      #   or a custom one. Defaults to :system
      def initialize(use_header_redesign: false, **system_arguments)
        @use_header_redesign = use_header_redesign
        @system_arguments = system_arguments
      end

      def use_header_redesign?
        @use_header_redesign
      end

      def analytics_icon_state
        "read"
      end

      def websocket_channel
        live_update_view_channel(GitHub::WebSocket::Channels.notifications_changed(current_user))
      end

      def render?
        logged_in?
      end

      def socket_data
        {
          channel: websocket_channel,
          "indicator-mode": :none,
          "tooltip-global": "You have unread notifications",
          "tooltip-unavailable": "Notifications are unavailable at the moment.",
          "tooltip-none": "You have no unread notifications",
          "header-redesign-enabled": use_header_redesign? ? true : nil,
          "fetch-indicator-src": notifications_indicator_path,
          "fetch-indicator-enabled": true,
        }.compact
      end
    end
  end
end
