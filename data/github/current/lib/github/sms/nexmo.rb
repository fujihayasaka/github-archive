# typed: true
# frozen_string_literal: true

#
# Nexmo API client and SMS::Provider subclass. Used by GitHub::SMS
# API Docs: https://docs.nexmo.com/index.php/sms-api/send-message
#
module GitHub
  module SMS
    class Nexmo < Provider
      TIME_ZONE = ActiveSupport::TimeZone["UTC"]

      # Public: Send an SMS
      #
      # to                - The number to send the SMS to.
      # message           - The body of the message.
      # reason            - The reason for sending the message.
      # completed_captcha - User was shown and completed a CAPTCHA before SMS was sent.
      #
      # Returns a GitHub::SMS::Receipt. Raises GitHub::SMS:Error on error responses.
      def send_message(to, message, user, reason = :unknown, completed_captcha = false)
        from_details = get_from_details(to)

        # Do not include the callback url in proxima requests. We do not want actions taken by a user on a proxima stamp
        # to be logged by a service running outside of that stamp.
        callback_url = GitHub.multi_tenant_enterprise? ? "" : GitHub.nexmo_callback_url&.gsub("{user_id}", user.id.to_s)

        params = {
          from: from_details[:from_value],
          to: to,
          text: message,
          callback: callback_url
        }

        http_res = connection.post("https://rest.nexmo.com/sms/json", params)

        # Handle unexpected status code.
        raise_for_code(:server) unless http_res.success?

        res_messages = parse_response(http_res)["messages"]

        # We only send one SMS at a time, so we should only receive one receipt.
        raise_for_code(:server) unless res_messages.length == 1
        res_message = res_messages.first
        receipt = build_receipt(res_message)

        # Instrument success status code.
        if http_res.success?
          GitHub.dogstats.increment("sms", tags: ["type:success", "providers:#{provider_name}", "from:#{from_details[:from_value]}", "country_code:#{from_details[:country_code]}", "reason:#{reason}", "completed_captcha:#{completed_captcha}"])
        end

        # Check for an error response.
        unless res_message["status"] == "0"
          raise_for_code(res_message["status"], message_id: receipt.message_id, country_code: from_details[:country_code])
        end

        receipt
      rescue Faraday::TimeoutError
        raise_for_code(:timeout, message_id: receipt&.message_id, country_code: from_details[:country_code])
      rescue Faraday::Error
        raise_for_code(:server, message_id: receipt&.message_id, country_code: from_details[:country_code])
      end

      # Checks the value of our account balance.
      #
      # Returns a Float.
      def account_balance
        http_res = connection.get("https://rest.nexmo.com/account/get-balance")
        case http_res.status
        when 200
          res = parse_response(http_res)
          res["value"]
        else
          raise_for_code(:server)
        end
      end

      if Rails.env.test?
        def req_stubs
          @req_stubs ||= Faraday::Adapter::Test::Stubs.new
        end
      end

      private

      # Private: Faraday connection for HTTP requests.
      #
      # Returns a Faraday::Connection instance.
      def connection
        @connection ||= Faraday.new(faraday_options) do |conn|
          conn.request :url_encoded
          if Rails.env.test?
            conn.adapter :test, req_stubs
          else
            conn.adapter :net_http
          end
        end
      end

      # Private: Options to instantiate the Faraday::Connection with.
      #
      # Returns a Hash.
      def faraday_options
        {
          request: {
            timeout: TIMEOUT,
          },
          params: {
            api_key: GitHub.nexmo_api_key,
            api_secret: GitHub.nexmo_api_secret,
          },
        }
      end

      # Private: Parse the response from Nexmo.
      #
      # res - A Faraday::Response object.
      #
      # Returns a Hash.
      def parse_response(res)
        begin
          JSON.parse(res.body)
        rescue ::JSON::ParserError
          {}
        end
      end

      # Private: Build a Receipt from an API response.
      #
      # res - A Hash parsed from an API response.
      #
      # Returns a GitHub::SMS::Receipt.
      def build_receipt(res)
        Receipt.new(
          provider: self,
          message_id: res["message-id"],
        )
      end

      # Private: A Hash mapping provider error codes to GitHub::SMS::Error
      # subclasses.
      #
      # Returns a Hash.
      def error_code_mapping
        super.merge(
          "3"  => NumberNotValidError,
          "5"  => ServerError,
          "6"  => NumberNotMobileError,
          "9"  => BillingError,
          "13" => ServerError,
        )
      end

      # Private: Gets the details from the SMS number.
      #
      # to - The number to send the SMS to.
      #
      # Returns a Hash of the country code and the from number.
      # The from number is either an alphanumeric value or a
      # number determined by Vonage (or Nexmo).
      # https://github.com/github/authentication/issues/2045
      def get_from_details(to)
        parsed_number = Phonelib.parse(to)
        country_code = parsed_number&.country_code

        from_value = if country_code == "1"
          GitHub.vonage_sms_us_canada_sender_id
        elsif country_code == "971"
          GitHub.vonage_sms_uae_sender_id
        else
          alphanumeric_from
        end

        { country_code: country_code,
          from_value: from_value
        }
      end
    end
  end
end
