# typed: true
# frozen_string_literal: true

class PullRequest
  module PresenceDependency
    include GitHub::Memoizer
    extend T::Helpers

    requires_ancestor { PullRequest }

    def async_signed_presence_channel
      async_issue.then do |issue|
        issue.async_repository.then do |repo|
          repo.async_owner.then do |_owner|
            authzd_attrs = GitHub::WebSocket.generate_authzd_attributes(self)
            channel = GitHub::WebSocket::Channels.pull_request(self)
            GitHub::WebSocket.signed_presence_channel(channel, authzd_attrs)
          end
        end
      end
    end

    memoize def signed_presence_channel
      async_signed_presence_channel.sync
    end
  end
end
