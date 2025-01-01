# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::DeletePush < FeedItem::PushEvent
    # Display
    def action_string
      rollup? ? "pushed" : "deleted"
    end

    def description
      "#{actor} #{action_string} "
    end

    def api_type
      "DeleteEvent"
    end

    def payload
      {
        ref: ref,
        ref_type: ref_type,
        pusher_type: push.pusher.type
      }
    end
  end
end
