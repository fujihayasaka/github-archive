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

      memoize def indicator_mode
        return :none unless logged_in?
        return :none if fetch_indicator_enabled?

        with_database_error_fallback(fallback: :none) do
          current_user.indicator_mode
        end
      end

      def has_unread_notifications?
        indicator_mode == :global
      end

      def analytics_icon_state
        has_unread_notifications? ? "unread" : "read"
      end

      def websocket_channel
        live_update_view_channel(GitHub::WebSocket::Channels.notifications_changed(current_user))
      end

      def render?
        logged_in? && indicator_mode != :disabled
      end

      memoize def fetch_indicator_enabled?
        GitHub.flipper[:notifications_indicator_async_fetch].enabled?(current_user)
      end

      def socket_data
        {
          channel: websocket_channel,
          "indicator-mode": indicator_mode,
          "tooltip-global": "You have unread notifications",
          "tooltip-unavailable": "Notifications are unavailable at the moment.",
          "tooltip-none": "You have no unread notifications",
          "header-redesign-enabled": use_header_redesign? ? true : nil,
          "fetch-indicator-src": notifications_indicator_path,
          "fetch-indicator-enabled": fetch_indicator_enabled? ? true : nil,
        }.compact
      end
    end
  end
end
