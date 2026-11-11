# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::DeletePush < FeedItem::PushEvent
    # Display
    def action_string
      rollup? ? "pushed" : "deleted"
    end

    def description
      "#{actor} #{action_string}"
    end

    def api_type
      "DeleteEvent"
    end

    def payload
      {
        ref: parse_ref(ref),
        ref_type: ref_type,
        full_ref: ref,
        pusher_type: pusher_type,
      }
    end
  end
end
