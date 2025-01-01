# typed: true
# frozen_string_literal: true

module Notifications
  class TopShelfComponent < ApplicationComponent
    attr_reader :referrer, :extra_classes

    def initialize(referrer: nil, extra_classes: "")
      @referrer = referrer
      @extra_classes = extra_classes
    end

    memoize def render?
      logged_in? && (deferred? || allowed?)
    end

    def deferred?
      referrer.nil?
    end

    def allowed?
      referrer != :conditional_access_error
    end

    memoize def base_url
      url(notification_shelf_path)
    end

    memoize def include_url
      return nil unless params[:notification_referrer_id].present?

      url(notification_shelf_path(params.slice(*NotificationsV2Controller::REFERRER_PARAMS).permit!))
    end

    memoize def back_to_notifications_url
      path = notifications_path(
        before: params[:notifications_before].presence,
        after: params[:notifications_after].presence,
        query: params[:notifications_query].presence,
      )

      url(path)
    end

    memoize def websocket_channel
      live_update_view_channel(GitHub::WebSocket::Channels.notifications_changed(current_user))
    end

    private

    def url(path)
      [GitHub.url, path].join("")
    end
  end
end
