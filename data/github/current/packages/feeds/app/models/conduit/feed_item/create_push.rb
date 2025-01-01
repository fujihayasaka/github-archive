# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatePush < FeedItem::PushEvent
    # Display
    def action_string
      rollup? ? "pushed" : "created"
    end

    def description
      "#{actor} #{action_string} a branch"
    end

    def api_type
      "CreateEvent"
    end

    def payload
      {
        ref: parse_ref(ref),
        ref_type: ref_type,
        full_ref: ref,
        master_branch: repository.default_branch,
        description: repository.description,
        pusher_type: pusher_type,
      }
    end
  end
end
