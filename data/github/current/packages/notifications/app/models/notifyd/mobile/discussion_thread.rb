# typed: true
# frozen_string_literal: true

module Notifyd
  module Mobile
    class DiscussionThread
      include Thread

      sig { params(discussion: ::Discussion).void }
      def initialize(discussion:)
        @discussion = discussion
      end

      sig { override.returns(T.nilable(String)) }
      def id
        @discussion.permalink(include_host: false)
      end

      sig { override.returns(String) }
      def type
        "discussion"
      end
    end
  end
end
