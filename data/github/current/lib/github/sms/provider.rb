# typed: true
# frozen_string_literal: true

module GitHub
  module SMS
    class Provider
      # Timeout to use for each SMS delivery attempt.
      TIMEOUT = GitHub.default_request_timeout - 2

      # Send an SMS.
      #
      # to                - The number to send to.
      # message           - The message to send.
      # reason            - The reason for sending the message.
      # completed_captcha - User was shown and completed a CAPTCHA before SMS was sent.
      #
      # Returns a GitHub::SMS::Receipt. Raises GitHub::SMS::Error.
      def send_message(to, message, user, reason = :unknown, completed_captcha = false)
        raise NotImplementedError
      end

      # Picks a number to send the SMS from (based on the provider).
      #
      # Returns a String.
      def from
        GitHub.sms_numbers[provider_name].sample
      end

      # Returns an alphanumeric sender ID that can be used for the 'from' value.
      #
      # Returns a String.
      def alphanumeric_from
        GitHub.sms_alphanumeric_sender_id
      end

      # Public: The name of this provider.
      #
      # Returns a String.
      def self.provider_name
        @provider_name ||= pretty_class_name(self)
      end

      # Public: The name of this provider.
      #
      # Returns a String.
      def provider_name
        self.class.provider_name
      end

      # Get the last section of a class name, underscore, and symbolize
      # it.
      #
      # klass - The class to pretify the name of.
      #
      # Returns a String.
      def self.pretty_class_name(klass)
        klass.name.split("::").last.underscore.to_sym
      end

      private

      # Private: Raises an appropriate error from a provider error code.
      #
      # code       - The error code sent by the provider.
      # message_id - The message_id returned by the provider.
      # country_code - The country code of the number.
      #
      # Raises a GitHub::SMS::Error instance.
      def raise_for_code(code, message_id: nil, country_code: nil)
        klass = error_code_mapping.fetch(code, UnknownError)
        error = klass.new
        error.set_backtrace(caller)

        # Instrument and report to Failbot since the exception will be rescued.
        GitHub.dogstats.increment("sms", tags: ["type:error", "providers:#{provider_name}", "country_code:#{country_code}", "error:#{code}", "subject:#{self.class.pretty_class_name(klass)}"])

        Failbot.push(
          app: "github-user",
          "gh.sms.provider": provider_name,
          "gh.sms.message.error_code": code,
          "gh.sms.message.id": message_id,
        )
        Failbot.report(error) rescue nil

        raise error
      end

      # Private: A Hash mapping provider error codes to GitHub::SMS::Error
      # subclasses.
      #
      # Returns a Hash.
      def error_code_mapping
        {
          number_not_mobile: NumberNotMobileError,
          number_not_valid: NumberNotValidError,
          area_not_supported: AreaNotSupportedError,
          region_not_geo_permissioned: RegionNotGeoPermissionedError,
          server: ServerError,
          timeout: TimeoutError,
        }
      end
    end
  end
end
