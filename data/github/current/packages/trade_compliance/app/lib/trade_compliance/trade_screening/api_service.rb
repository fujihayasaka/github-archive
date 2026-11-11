# typed: true
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  class ApiService

    RETRYABLE_ERRORS = [
      Faraday::ConnectionFailed,
      Faraday::RetriableResponse,
    ].freeze

    REQUEST_FAILED_EXCEPTIONS = [
      Faraday::Error,
      Errno::ETIMEDOUT,
      Yajl::ParseError,
      SDNAuthenticationError,
      ApiServiceAuthenticationError,
      EisBusResponseParsingError,
      LiveResponseParsingError,
      LiveResponseEmptyError,
      ApiServiceBadResponseError,
      StandardError,
    ]

    DEFAULT_RETRY_CONFIG = {
      max: 3,
      interval: 0.05,
      backoff_factor: 2,
      exceptions: RETRYABLE_ERRORS,
      methods: %i[post get],
      retry_statuses: [401, 500]
    }

    sig { params(hydro_actor: Symbol, screening_details: ScreeningDetails).returns(LiveResponse) }
    def self.request_trade_screening(hydro_actor:, screening_details:)
      make_live_request(owner_type: hydro_actor, body: screening_details.to_hash)
    end

    # Makes a request to the SDN Live Screening API
    sig { params(owner_type: Symbol, body: T::Hash[T.any(String, Symbol), T.untyped]).returns(LiveResponse) }
    def self.make_live_request(owner_type:, body: {})
      # External_uuid is a unique identifier for the user
      external_uuid = body.dig(:ScrReqsEnv, :ExternalRefID)
      # EId (Envelope ID) is a unique identifier for the request that is returned in the response
      eid = body.dig(:ScrReqsEnv, :EId)
      # record the start time so we monitor how long it takes to complete a request
      start_time = GitHub::Dogstats.monotonic_time

      # Returns a successful no_hit response if in development
      if mock_response_for_development?
        dev_resp = development_live_response(request_body: body)
        return parse_live_response(dev_resp, start_time, owner_type, external_uuid: external_uuid, eid: eid)
      end

      resp = live_connection.post do |req|
        req.url GitHub.sdn_live_api_url_path
        req.body = body.to_json
      end

      parse_live_response(resp, start_time, owner_type, external_uuid: external_uuid, eid: eid)
    rescue *REQUEST_FAILED_EXCEPTIONS => e
      log_failure(type: "live", owner_type: owner_type, exception: e, eid: eid, external_uuid: external_uuid, start_time: start_time)
    end

    # Makes an EIS (Enterprise Information System) request to the SDN API
    sig { params(offset: String).returns(EisBusResponse) }
    def self.make_eis_request(offset: "0")
      # record the start time so we monitor how long it takes to complete a request
      start_time = GitHub::Dogstats.monotonic_time

      resp = eis_connection.get "#{GitHub.sdn_eis_api_sub_path}/alertreview/1.0/#{offset}?batchsize=900"
      parse_eis_response(resp, start_time)
    rescue *REQUEST_FAILED_EXCEPTIONS => e
      log_failure(type: "eis", owner_type: :UNKNOWN, exception: e, start_time: start_time)
    end

    # Initializes a new Faraday::Connection for live requests
    #
    # returns Faraday::Connection
    def self.live_connection
      @live_conn ||= begin
        GitHub::FaradayClient::External.new(url: GitHub.sdn_live_api_base_url) do |f|
          f.options.timeout = 8.seconds
          f.request :retry, retry_options
          f.adapter Faraday.default_adapter
          f.headers = {
            "Ocp-Apim-Subscription-Key" => GitHub.ocp_apim_subscription_key,
            "Content-Type" => "application/json",
            "Accept" => "application/json",
          }
        end
      end

      @live_conn.authorization(:Bearer, RequestAccessToken.for_live_api)
      @live_conn
    end

    # Initializes a new Faraday::Connection for EIS requests
    #
    # returns Faraday::Connection
    def self.eis_connection
      @eis_conn ||= begin
        GitHub::FaradayClient::External.new(url: GitHub.sdn_eis_api_base_url) do |f|
          f.options.timeout = 8.seconds
          f.request :retry, retry_options
          f.adapter Faraday.default_adapter
          f.headers = {
            "Content-Type" => "application/json",
            "Accept" => "application/json",
          }
        end
      end

      @eis_conn.authorization(:Bearer, RequestAccessToken.for_eis)
      @eis_conn
    end

    # Constructs Faraday retry options hash
    #
    # returns the retry hash
    def self.retry_options
      retry_proc = proc { |env, _options, _retries, exc|
        exc_cls = exc.class

        if exc.instance_of?(Faraday::RetriableResponse) && env.status == 401
          if env.url.path == GitHub.sdn_live_api_url_path
            RequestAccessToken.force_new_token_for_live_api
            env.request_headers["Authorization"] = "Bearer #{RequestAccessToken.for_live_api}"
          elsif env.url.path.include?(GitHub.sdn_eis_api_sub_path)
            RequestAccessToken.force_new_token_for_eis
            env.request_headers["Authorization"] = "Bearer #{RequestAccessToken.for_eis}"
          end

          GitHub.dogstats.increment(
            "sdn_api_service.connection_retry",
            tags: ["exception:#{ApiServiceAuthenticationError.new.class}"],
          )
        else
          GitHub.dogstats.increment(
            "sdn_api_service.connection_retry",
            tags: ["exception:#{exc_cls}"],
          )
        end
      }

      options = DEFAULT_RETRY_CONFIG
      options[:retry_block] = retry_proc

      options
    end

    class << self

      private

      # We occasionally want to update the development config with the real secret so that we can test against the CDE api
      # in those scenarios, it's not ideal to have to always edit the client code to bypass the mocked response.
      # This gets around it by assuming that while in the dev environment, anything other than blank or "redacted" is a real secret value.
      sig { returns(T::Boolean) }
      def mock_response_for_development?
        return false unless Rails.env.development?

        GitHub.sdn_authentication_client_secret.blank? || GitHub.sdn_authentication_client_secret == "redacted"
      end

      # Private: Called when in development environment to avoid making a Live API request.
      #
      # The Hash object parsed matches the response in the VCR request file
      # test/fixtures/vcr_cassettes/trade_controls/sdn/valid_user_live_api_call.yml
      #
      # returns a successful response with screening status of no_hit
      def development_live_response(request_body:)
        Faraday::Response.new(
          status: 200,
          body: {
            ScrRespEnv: {
              EId: request_body.dig(:ScrReqsEnv, :EId),
              DT: request_body.dig(:ScrReqsEnv, :DT),
              SummResult: "No Hit",
              ScrResps: {
                ScrResp: [
                  {
                    ReqID: "IndName_IndAddr",
                    ExternalRefID: request_body.dig(:ScrReqsEnv, :ExternalRefID),
                    Result: "No Hit",
                    ResultDesc: "",
                    Type: "Address",
                    Errs: {
                      Err: [
                        {
                          ErrCode: "",
                          ErrDesc: ""
                        }
                      ]
                    }
                  }
                ]
              }
            }
          }.to_json
        )
      end

      # Logs a successful API response
      #
      # type - Which API service the response came from (live or eis)
      # status - The SDN screening status
      # start_time - The time recorded before the request was made
      # eid - Envelope ID, a unique identifier for the request and response
      # external_uuid - A unique identifier for the user or organization
      def log_success(type:, owner_type:, status:, start_time:, eid:, external_uuid: nil)
        tags = ["status:#{status}", "eid:#{eid}", "owner_type:#{owner_type}"]

        # This will allow us to query for example the metric sdn_api_service.live.time
        # to monitor the time (value) it takes to complete a request
        # TODO Convert this to a distribution metric. Histrograms/Timings are deprecated.
        GitHub.dogstats.timing_since("sdn_api_service.#{type}.time", start_time, tags: tags)

        # This logs to Splunk success requests
        GitHub.logger.info("sdn_api_service.success",
          "gh.sdn_api_service.type": type,
          "gh.sdn_api_service.url": get_base_url(type: type),
          "gh.sdn_api_service.status": status,
          "gh.sdn_api_service.eid": eid,
          "gh.sdn_api_service.external_uuid": external_uuid
        )

        # This will allow us to monitor the number of success requests
        # and the sdn statuses we are receiving
        #
        # TODO Replace this with a tag on on the distribution metric above. Query using `count:sdn_api_service.duration{type:live, result:success}`
        GitHub.dogstats.increment("sdn_api_service.#{type}.success", tags: tags)
      end

      # Logs a failed API response
      #
      # type - Which API service the response came from (live or eis)
      # exception - The exception that has been raised
      # start_time - The time recorded before the request was made
      # eid - Envelope ID, a unique identifier for the request and response
      # external_uuid - A unique identifier for the user or organization
      def log_failure(type:, owner_type:, start_time:, exception:, eid: nil, external_uuid: nil)
        safe_message = "Request to the SDN API failed because of #{exception.class.name} error"
        error_message = exception.message.presence || safe_message

        # This logs the failure to datadog with a safe error message
        tags = ["reason:#{safe_message}", "eid:#{eid}", "owner_type:#{owner_type}"]
        GitHub.dogstats.timing_since("sdn_api_service.#{type}.time", start_time, tags: tags)

        # This will allow us to monitor the number of failed requests
        # and the reasons for the failures
        GitHub.dogstats.increment("sdn_api_service.#{type}.failed", tags: tags)

        GitHub.logger.error("sdn_api_service.failed",
          "gh.sdn_api_service.type": type,
          "gh.sdn_api_service.url": get_base_url(type: type),
          "gh.sdn_api_service.eid": eid,
          "gh.sdn_api_service.external_uuid": external_uuid,
          "error.message": error_message
        )

        # Report the original exception to Sentry
        Failbot.report(exception) unless exception.is_a?(LiveResponseEmptyError)

        # Raise the exception with a controlled error class
        raise ApiServiceError, error_message
      end

      # Parses the response received from the EIS Bus API
      #
      # raises ApiServiceAuthenticationError or ApiServiceBadResponseError if request fails
      sig { params(resp: T.untyped, start_time: Numeric).returns(EisBusResponse) }
      def parse_eis_response(resp, start_time)
        case resp.status
        when (200..299)
          resp_data = GitHub::JSON.parse(resp.body, symbolize_names: true)
          response = EisBusResponse.parse(response: resp_data)
          response.messages.each do |msg|
            profile = AccountScreeningProfile.find_by(external_uuid: msg.external_id)
            owner_type = if profile.nil? || profile.owner.nil?
              :UNKNOWN
            else
              profile.hydro_actor
            end
            log_success(type: "eis", owner_type: owner_type, status: msg.status, eid: msg.eid, external_uuid: msg.external_id, start_time: start_time)
          end
          response
        when 401
          # For 401 errors the request will be automatically retried for 3 times
          # which involves making another request to force issue a new access token.
          # If this block is called that means for some reason the newly issued
          # access tokens did not work so we force issue a new token once again,
          # then we report ApiServiceAuthenticationError so we can investigate.
          RequestAccessToken.force_new_token_for_eis
          raise ApiServiceAuthenticationError, "Authentication error"
        else
          # Since EisBusResponseParsingError is thrown in case of unexpected response body,
          # we will only get here due to an unexpected HTTP error.
          raise ApiServiceBadResponseError, "Request to the SDN API failed because of #{resp.status} HTTP status"
        end
      end

      # Parses the response received from the SDN Live API
      #
      # raises ApiServiceAuthenticationError or ApiServiceBadResponseError if request fails
      # returns LiveResponse if request succeeds
      def parse_live_response(resp, start_time, owner_type, external_uuid: nil, eid: nil)
        case resp.status
        when (200..299)
          resp_data = GitHub::JSON.parse(resp.body, symbolize_names: true)
          live_response = LiveResponse.parse(response: resp_data)
          errors = live_response.errors

          # SdnDataValidationError (ingestion_error) is a valid status so no need to raise an error.
          if !errors.empty? && !errors.pluck(:code).include?("SdnDataValidationError")
            err_desc_arr = errors.collect { |u| "#{u[:code]}: #{u[:message]}" }
            raise ApiServiceBadResponseError, err_desc_arr.join(", ")
          else
            log_success(type: "live", owner_type: owner_type, status: live_response.status, eid: live_response.eid, start_time: start_time, external_uuid: live_response.external_uuid)
            live_response
          end
        when 401
          # For 401 errors the request will be automatically retried for 3 times
          # which involves making another request to force issue a new access token.
          # If this block is called that means for some reason the newly issued
          # access tokens did not work so we force issue a new token once again,
          # then we report ApiServiceAuthenticationError so we can investigate.
          RequestAccessToken.force_new_token_for_live_api
          raise ApiServiceAuthenticationError, "Authentication error"
        else
          # Since LiveResponseParsingError is thrown in case of unexpected response body,
          # we will only get here due to an unexpected HTTP error.
          raise ApiServiceBadResponseError, "Request to the SDN API failed because of #{resp.status} HTTP status"
        end
      end

      # Returns the base URL for the given API service type
      def get_base_url(type:)
        case type
        when "live"
          GitHub.sdn_live_api_base_url
        when "eis"
          GitHub.sdn_eis_api_base_url
        else
          "Unknown service type"
        end
      end
    end
  end
end
