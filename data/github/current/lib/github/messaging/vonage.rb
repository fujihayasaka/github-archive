# typed: true
# frozen_string_literal: true

#
# Nexmo API client and SMS::Provider subclass. Used by GitHub::Messaging
# API Docs: https://docs.nexmo.com/index.php/sms-api/send-message
#
module GitHub
  module Messaging
    class Vonage < Provider
      TIME_ZONE = ActiveSupport::TimeZone["UTC"]

      # Public: Send an message
      #
      # to                - The number to send the message to.
      # message           - The body of the message.
      # reason            - The reason for sending the message.
      # completed_captcha - User was shown and completed a CAPTCHA before message was sent.
      #
      # Returns a GitHub::Messaging::Receipt. Raises GitHub::Messaging::Error on error responses.
      def send_message(to, message, user, reason = :unknown, completed_captcha = false)
        from_details = get_from_details(to)

        if FeatureFlag.vexi.enabled?(:vonage_sdk, user, default: false)
          sdk_send(user, to, from_details, message, reason, completed_captcha)
        else
          http_sms(user, to, from_details, message, reason, completed_captcha)
        end

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

      if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        def req_stubs
          @req_stubs ||= Faraday::Adapter::Test::Stubs.new
        end
      end

      private

      # Private: Vonage client.
      #
      # Returns a Vonage::Client instance.
      def client
        @client ||= ::Vonage::Client.new(
          application_id: GitHub.vonage_application_id,
          private_key: GitHub.vonage_private_key
        )
      end

      # Private: Faraday connection for HTTP requests.
      #
      # Returns a Faraday::Connection instance.
      def connection
        @connection ||= Faraday.new(faraday_options) do |conn| # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
          conn.request :url_encoded
          if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
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
      # Returns a GitHub::Messaging::Receipt.
      def build_sms_receipt(res)
        Receipt.new(
          provider: self,
          message_id: res["message-id"],
        )
      end

      def build_sdk_receipt(res)
        Receipt.new(
          provider: self,
          message_id: res.message_uuid,
        )
      end

      # Private: A Hash mapping provider error codes to GitHub::Messaging::Error
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

      # Private: Extracts the message ID from an error.
      #
      # error - The error object raised by the Vonage SDK.
      #
      # Returns the message ID if available, otherwise nil.
      def extract_message_id(error)
        if error.respond_to?(:http_response) && error.http_response.respond_to?(:message_uuid)
          error.http_response.message_uuid
        else
          nil
        end
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

      def sdk_send(user, to, from_details, message, reason, completed_captcha)
        # Do not include the callback url in proxima requests. We do not want actions taken by a user on a proxima stamp
        # to be logged by a service running outside of that stamp.
        callback_url = GitHub.multi_tenant_enterprise? ? "" : GitHub.vonage_messages_callback_url&.gsub("{user_id}", user.id.to_s)

        begin
          vonage_rcs_message = ::Vonage::Messaging::Message.rcs(
            type: "text",
            message: message,
            opts: {
              webhook_url: callback_url,
              rcs: {
                category: "authentication"
              }
            }
          )
          vonage_sms_message = ::Vonage::Messaging::Message.sms(
            from: from_details[:from_value],
            to: to,
            message: message,
            opts: {
              webhook_url: callback_url
            }
          )

          # always send RCS to countries in rcs_country_set, some amount of RCS/SMS split for countries in rcs_experiment_country_set, and check the force-RCS override that can be enabled per-user
          if rcs_country_set.include?(from_details[:country_code]) || send_rcs_for_experiment?(from_details[:country_code]) || FeatureFlag.vexi.enabled?(:vonage_rcs_override, user, default: false)
            message_type = "rcs"
            response = client.messaging.send( # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
              from: "GitHub",
              to: to,
              **vonage_rcs_message,
              failover: [vonage_sms_message]
            )
          else
            message_type = "sms"
            response = client.messaging.send( # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
              **vonage_sms_message,
            )
          end

          if response.http_response.code.to_i == 202
            GitHub.dogstats.increment(message_type, tags: ["type:success", "providers:#{provider_name}", "from:#{from_details[:from_value]}", "country_code:#{from_details[:country_code]}", "reason:#{reason}", "completed_captcha:#{completed_captcha}"])
          end

          build_sdk_receipt(response)
        rescue ::Vonage::APIError => error
          error_code = :unexpected
          if error.is_a?(::Vonage::AuthenticationError)
            error_code = :authentication
            error_message = error.message.present? ? error.message : "verify application ID and private key are valid"
          elsif error.is_a?(::Vonage::ClientError)
            error_code = :client
            error_message = error.message.present? ? error.message : "an invalid vonage_message was created, verify params are all valid"
          elsif error.is_a?(::Vonage::ServerError)
            error_code = :server
            error_message = error.message.present? ? error.message : "server error occurred"
          end

          GitHub.logger.error("Vonage SDK error", {
            error_class: error.class.name,
            error_message: error_message || "Unknown Vonage error",
            country_code: from_details[:country_code],
            from_value: from_details[:from_value],
            http_response_body: error.http_response_body.inspect
          })

          message_id = extract_message_id(error)
          raise_for_code(error_code, message_type: message_type, message_id: message_id, country_code: from_details[:country_code])
        end
      end

      def http_sms(user, to, from_details, message, reason, completed_captcha)
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
        receipt = build_sms_receipt(res_message)

        # Instrument success status code.
        if http_res.success?
          GitHub.dogstats.increment("sms", tags: ["type:success", "providers:#{provider_name}", "from:#{from_details[:from_value]}", "country_code:#{from_details[:country_code]}", "reason:#{reason}", "completed_captcha:#{completed_captcha}"])
        end

        # Check for an error response.
        unless res_message["status"] == "0"
          raise_for_code(res_message["status"], message_type: "sms", message_id: receipt.message_id, country_code: from_details[:country_code])
        end

        receipt
      rescue Faraday::TimeoutError
        raise_for_code(:timeout, message_type: "sms", message_id: receipt&.message_id, country_code: from_details[:country_code])
      rescue Faraday::Error
        raise_for_code(:server, message_type: "sms", message_id: receipt&.message_id, country_code: from_details[:country_code])
      end

      # Private: Set of Countries that support RCS messaging AND are cheaper to send RCS messages to than SMS messages.
      #
      # Returns a Set of country codes.
      def rcs_country_set
        return @rcs_country_set if @rcs_country_set

        enabled_set = Set.new

        if FeatureFlag.vexi.enabled?(:vonage_rcs, default: false)
          enabled_set.merge([
            ["+43",   "Austria"],
            ["+55",   "Brazil"],
            ["+49",   "Germany"],
            ["+39",   "Italy"],
            ["+52",   "Mexico"],
            ["+31",   "Netherlands"],
            ["+234",  "Nigeria"],
            ["+47",   "Norway"],
            ["+351",  "Portugal"],
            ["+27",   "South Africa"],
            ["+34",   "Spain"],
            ["+46",   "Sweden"],
            ["+44",   "United Kingdom"]
          ])

          # supported but we don't want to enable by default, due to potential cost. Experimenting first, can turn on fully with targeted FF.
          if FeatureFlag.vexi.enabled?(:vonage_rcs_france, default: false)
            enabled_set.add(["+33", "France"])
          end
        else
          if FeatureFlag.vexi.enabled?(:vonage_rcs_austria, default: false)
            enabled_set.add(["+43", "Austria"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_brazil, default: false)
            enabled_set.add(["+55", "Brazil"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_france, default: false)
            enabled_set.add(["+33", "France"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_germany, default: false)
            enabled_set.add(["+49", "Germany"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_italy, default: false)
            enabled_set.add(["+39", "Italy"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_mexico, default: false)
            enabled_set.add(["+52", "Mexico"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_netherlands, default: false)
            enabled_set.add(["+31", "Netherlands"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_nigeria, default: false)
            enabled_set.add(["+234", "Nigeria"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_norway, default: false)
            enabled_set.add(["+47", "Norway"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_portugal, default: false)
            enabled_set.add(["+351", "Portugal"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_south_africa, default: false)
            enabled_set.add(["+27", "South Africa"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_spain, default: false)
            enabled_set.add(["+34", "Spain"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_sweden, default: false)
            enabled_set.add(["+46", "Sweden"])
          end
          if FeatureFlag.vexi.enabled?(:vonage_rcs_united_kingdom, default: false)
            enabled_set.add(["+44", "United Kingdom"])
          end
        end

        @rcs_country_set = enabled_set.map { |pair| pair.first.delete_prefix("+") }.compact
      end

      # want a 50-50 split of RCS/SMS messages for the experiment, for countries in the experiment set.
      # then intend to determine if RCS higher OTP conversion offsets higher per-message price
      def send_rcs_for_experiment?(country_code)
        return false unless rcs_experiment_country_set.include?(country_code)

        SecureRandom.random_number(1000) / 2 == 0
      end

      def rcs_experiment_country_set
        return @rcs_experiment_country_set if @rcs_experiment_country_set

        experiment_set = Set.new
        if FeatureFlag.vexi.enabled?(:vonage_rcs_experiment_france, default: false)
          experiment_set.add(["+33", "France"])
        end

        @rcs_experiment_country_set = experiment_set.map { |pair| pair.first.delete_prefix("+") }.compact
      end
    end
  end
end
