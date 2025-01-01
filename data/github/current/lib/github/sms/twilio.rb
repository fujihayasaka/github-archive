# typed: true
# frozen_string_literal: true

module GitHub
  module SMS
    class Twilio < Provider
      # Send an SMS.
      #
      # to                - The number to send to.
      # message           - The message to send.
      # reason            - The reason for sending the message.
      # completed_captcha - User was shown and completed a CAPTCHA before SMS was sent.
      #
      # Returns a GitHub::SMS::Receipt. Raises GitHub::SMS::Error.
      def send_message(to, message, user, reason = :unknown, completed_captcha = false)
        from_details = from_number_details(to)

        from_value = from_details[:use_alphanumeric_from] ? alphanumeric_from : from

        twilio_message = client.messages.create(
          from: from_value,
          to: to,
          body: message,
          status_callback: GitHub.twilio_callback_url.gsub("{user_id}", user.id.to_s),
        )

        receipt = build_receipt(twilio_message)

        # Instrument success status code.
        GitHub.dogstats.increment("sms", tags: ["type:success", "providers:#{provider_name}", "from:#{from_value}", "country_code:#{from_details[:country_code]}", "reason:#{reason}", "completed_captcha:#{completed_captcha}"])

        receipt
      rescue ::Twilio::REST::RestError => e
        raise_for_code(e.code, country_code: from_details[:country_code])
      rescue ::Twilio::REST::TwilioError
        raise_for_code(:server, country_code: from_details[:country_code])
      rescue Timeout::Error
        raise_for_code(:timeout, country_code: from_details[:country_code])
      end

      private

      # Private: Twilio client.
      #
      # Returns a Twilio::REST::Client instance.
      def client
        @client ||= ::Twilio::REST::Client.new(
          GitHub.twilio_sid,
          GitHub.twilio_token,
          nil, # account_sid
          nil, # region
          ::Twilio::HTTP::Client.new(
            timeout: TIMEOUT
          )
        )
      end

      # Private: Build a Receipt from an API response.
      #
      # message - A Twilio::REST::SMS::Message.
      #
      # Returns a GitHub::SMS::Receipt.
      def build_receipt(message)
        Receipt.new(
          provider: self,
          message_id: message.sid,
        )
      end

      # Private: A Hash mapping provider error codes to GitHub::SMS::Error
      # subclasses.
      #
      # Returns a Hash.
      def error_code_mapping
        super.merge(
          10001 => BillingError,
          21408 => RegionNotGeoPermissionedError,
          21614 => NumberNotMobileError,
          21211 => NumberNotValidError,
          21612 => AreaNotSupportedError,
        )
      end

      # Private: Gets the details of the 'from' number.
      #
      # Returns a Hash of the country code and whether the
      # from value should be alphanumeric of not.
      def from_number_details(to)
        parsed_number = Phonelib.parse(to)
        country_code = parsed_number&.country_code

        { country_code: country_code,
          use_alphanumeric_from: alphanumeric_from?(country_code)
        }
      end

      # Private: Determine if a given number belongs to a
      # country that requires an alphanumeric 'from' value.
      # https://github.com/github/authentication/issues/595
      #
      # Returns a boolean.
      def alphanumeric_from?(country_code)
        return true if country_code == "242" # Congo
        return true if country_code == "243" # Congo, Dem Rep
        return true if country_code == "260" # Zambia
        return true if country_code == "256" # Uganda
        return true if country_code == "241" # Gabon
        return true if country_code == "261" # Madagascar
        return true if country_code == "265" # Malawi
        return true if country_code == "234" # Nigeria
        return true if country_code == "250" # Rwanda
        return true if country_code == "44" # UK
        return true if country_code == "81" # Japan

        # awaiting pre-registration
        # true if country_code == "255" # Tanzania

        false
      end
    end
  end
end
