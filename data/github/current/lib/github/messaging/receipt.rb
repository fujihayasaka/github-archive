# typed: true
# frozen_string_literal: true

# GitHub::Messaging::Receipt encapsulates data about an SMS delivery attempt.

module GitHub
  module Messaging
    class Receipt
      attr_reader :provider, :message_id, :channel

      # Instantiate a new Receipt object.
      #
      # data - A hash of data about a delivery attempt.
      #        :provider   - The SMS provider that was used.
      #        :message_id - Any message ID given by the provider.
      #        :channel    - The channel that the message was sent via (e.g. SMS, RCS).
      #
      # Returns nothing.
      def initialize(data = {})
        @provider   = data[:provider]
        @message_id = data[:message_id]
        @channel    = data[:channel]
      end
    end
  end
end
