# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PushEvent < FeedItem
    delegate :repository, :created_at, :total_commits_count, :branch_name, to: :push

    def push
      subject
    end

    def shas
      push.commits_summary
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

    private

    def ref_type
      push.ref_is_tag? ? :tag : :branch
    end
  end
end
