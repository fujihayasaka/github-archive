# typed: true
# frozen_string_literal: true

class PullRequest
  module PresenceDependency
    include GitHub::Memoizer
    extend T::Helpers

    requires_ancestor { PullRequest }

    def async_signed_presence_channel
      async_issue.then do |issue|
        T.must(issue).async_repository.then do |repo|
          T.must(repo).async_owner.then do |_owner|
            authzd_attrs = GitHub::WebSocket.generate_authzd_attributes(self)
            channel = GitHub::WebSocket::Channels.pull_request(self)
            GitHub::WebSocket.signed_presence_channel(channel, authzd_attrs)
          end
        end
      end
    end

    memoize def signed_presence_channel
      async_signed_presence_channel.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end
end
