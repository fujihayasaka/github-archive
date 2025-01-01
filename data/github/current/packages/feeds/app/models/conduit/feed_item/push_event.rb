# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PushEvent < FeedItem
    delegate :repository, to: :push

    def push
      subject
    end

    def shas
      push.commits_summary
    end

    def api_type
      "PushEvent"
    end

    def payload
      {
        repository_id: repository.id,
        push_id: push.id,
        size: push.total_commits_count,
        distinct_size: push.distinct_commits_pushed.size,
        ref: push.ref,
        head: push.after,
        before: push.before,
        commits: shas.map do |(id, email, message, name, is_distinct)|
          {
            sha: id,
            author: { email: email, name: name },
            message: message,
            distinct: is_distinct,
            url: "#{GitHub.api_url}/repos/#{repository.name_with_display_owner}/commits/#{id}",
          }
        end
      }
    end

    def self.supports_graphql?
      false
    end

    # This FeedItem isn't being used for Feed Cards right now so doesn't need analytics
    def analytics_card_type
      nil
    end
  end
end
