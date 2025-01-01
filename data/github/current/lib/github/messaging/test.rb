# typed: true
# frozen_string_literal: true

module GitHub
  module Messaging
    class Test < Provider
      NON_MOBILE_NUMBER    = "+1 3072581234"
      NON_VALID_NUMBER     = "+1 3072582345"
      SERVER_ERROR_NUMBER  = "+1 3072583456"
      TIMEOUT_ERROR_NUMBER = "+1 3072584567"
      GEO_PERMISSION_ERROR_NUMBER = "+1 3072585678"

      # Normalize a number for comparing test numbers.
      def self.normalize(number)
        Phonelib.parse(number).e164
      end

      ERROR_MAPPING = {
        normalize(NON_MOBILE_NUMBER)    => :number_not_mobile,
        normalize(NON_VALID_NUMBER)     => :number_not_valid,
        normalize(SERVER_ERROR_NUMBER)  => :server,
        normalize(TIMEOUT_ERROR_NUMBER) => :timeout,
        normalize(GEO_PERMISSION_ERROR_NUMBER) => :region_not_geo_permissioned,
      }

      # Send an SMS.
      #
      # to                - The number to send to.
      # message           - The message to send.
      # reason            - The reason for sending the message.
      # completed_captcha - User was shown and completed a CAPTCHA before SMS was sent.
      #
      # Returns a GitHub::Messaging::Receipt. Raises GitHub::Messaging::Error.
      def send_message(to, message, user, reason = :unknown, completed_captcha = false)
        noop

        if code = ERROR_MAPPING[self.class.normalize(to)]
          raise_for_code(code)
        end

        Receipt.new(
          provider: self,
          message_id: SecureRandom.hex,
        )
      end

      private

      # A noop method called by send_message so Mocha expectations can count
      # the number of times send_message is called without stubbing send_message
      #
      # Returns nothings.
      def noop
      end
    end
  end
end
