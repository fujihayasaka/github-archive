# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PushEvent < FeedItem
    include GitHub::Memoizer

    delegate :repository, :created_at, :branch_name, to: :push

    def push
      subject
    end

    # Pusher type - user or deploy key
    # If original actor id is 0, it means the pusher is a deploy key
    def pusher_type
      twirp_item.actor&.id.zero? ? :deploy_key : :user
    end

    # Pusher sub type - user or bot
    def pusher_sub_type
      push.pusher.type
    end

    memoize def shas
      push.commits_summary
    end

    memoize def total_commits_count
      push.total_commits_count
    end

    def ref
      push.ref
    end

    # Display
    def action_string
      "pushed"
    end

    def description
      "#{actor} #{action_string} #{repository.name}"
    end

    # Analytics
    def analytics_card_type
      CardType::PUSH
    end

    def resource_type
      ResourceType::PUSH_EVENT
    end

    def resource_id
      push.id
    end

    def source
      repository.name_with_display_owner
    end

    def api_type
      "PushEvent"
    end

    def payload
      {
        repository_id: repository.id,
        push_id: push.id,
        size: total_commits_count,
        distinct_size: distinct_size,
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

    private

    def ref_type
      push.ref_is_tag? ? :tag : :branch
    end

    def distinct_size
      push.commits_pushed_count
    end
  end
end
