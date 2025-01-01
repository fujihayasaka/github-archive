# typed: true
# frozen_string_literal: true

module GitHub
  module SMS
    class Local < Provider
      # Send an SMS.
      #
      # to                - The number to send to.
      # message           - The message to send.
      # reason            - The reason for sending the message.
      # completed_captcha - User was shown and completed a CAPTCHA before SMS was sent.
      #
      # Returns a GitHub::SMS::Receipt. Raises GitHub::SMS::Error.
      def send_message(to, message, user, reason = :unknown, completed_captcha = false)
        text = "Message from #{from} to #{to}: #{message}"

        Rails.logger.info(text)

        Receipt.new(
          provider: self,
          message_id: SecureRandom.hex,
        )
      end
    end
  end
end
