# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::Issue < FeedItem
    delegate :repository, to: :issue

    def issue
      subject
    end

    def api_type
      "IssuesEvent"
    end

    def payload
      {
        action: action,
        issue: Api::Serializer.serialize(:issue_hash, issue),
      }
    end
  end
end
