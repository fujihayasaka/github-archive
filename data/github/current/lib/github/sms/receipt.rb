# typed: true
# frozen_string_literal: true

# GitHub::SMS::Receipt encapsulates data about an SMS delivery attempt.

module GitHub
  module SMS
    class Receipt
      attr_reader :provider, :message_id

      # Instantiate a new Receipt object.
      #
      # data - A hash of data about a delivery attempt.
      #        :provider   - The SMS provider that was used.
      #        :message_id - Any message ID given by the provider.
      #
      # Returns nothing.
      def initialize(data = {})
        @provider   = data[:provider]
        @message_id = data[:message_id]
      end
    end
  end
end
