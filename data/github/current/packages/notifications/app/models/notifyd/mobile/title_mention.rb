# typed: true
# frozen_string_literal: true

module Notifyd
  module Mobile
    # TitleMention implements rendering the title that all push notifications
    # for mentions use.
    class TitleMention
      extend T::Sig

      sig { params(author: Author).void }
      def initialize(author:)
        @author = author
      end

      def to_s
        "@#{author.username} mentioned you"
      end

      private

      sig { returns(Author) }
      attr_reader :author
    end
  end
end
