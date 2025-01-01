# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PullRequest < FeedItem
    delegate :repository, :issue, to: :pull_request

    def pull_request
      subject
    end

    def api_type
      "PullRequestEvent"
    end

    def payload
      {
        action: action,
        number: pull_request.number,
        pull_request: Api::Serializer.serialize(:pull_request_hash, pull_request, full: true)
      }
    end
  end
end
