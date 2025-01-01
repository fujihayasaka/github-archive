# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class ApiServiceTest < GitHub::TestCase
    include TradeScreeningTestHelpers
    include DogstatsTestHelpers
    include GitHub::LoggerHelper

    setup do
      # This ensures each test starts with a fresh connection instance as they can bleed across tests
      ApiService.instance_variable_set(:@eis_conn, nil)
      ApiService.instance_variable_set(:@live_conn, nil)
    end

    fixtures do
      @user_request_body = JSON.parse(
        Rails.root.join("test", "fixtures", "trade_controls", "sdn", "ind_name_addr_req.json").read,
      ).deep_symbolize_keys

      @business_request_body = JSON.parse(
        Rails.root.join("test", "fixtures", "trade_controls", "sdn", "business_name_addr_req.json").read,
      ).deep_symbolize_keys

      @bad_request_body = JSON.parse(
        Rails.root.join("test", "fixtures", "trade_controls", "sdn", "ind_name_addr_bad_checksum_req.json").read,
      ).deep_symbolize_keys
    end

    def live_conn_stub(exc)
      GitHub::FaradayClient::External.new(url: "http://example.invalid") do |builder|
        builder.request :retry, ApiService.retry_options

        builder.adapter :test do |stub|
          stub.post(GitHub.sdn_live_api_url_path) do
            raise exc, nil
          end
        end
      end
    end

    def eis_conn_stub(exc)
      GitHub::FaradayClient::External.new(url: "http://example.invalid") do |builder|
        builder.request :retry, ApiService.retry_options

        builder.adapter :test do |stub|
          stub.get("#{GitHub.sdn_eis_api_sub_path}/alertreview/1.0/0?batchsize=900") do
            raise exc, nil
          end
        end
      end
    end

    def make_request(cassette, **options, &block)
      VCR.use_cassette(cassette, **options) do
        yield
      end
    end

    context "live" do
      test "it raises and reports authentication error if access token is invalid and retries does not resolve it" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        assert_logged(
          "Body" => "sdn_api_service.failed",
          "gh.sdn_api_service.type" => "live",
          "gh.sdn_api_service.url" => GitHub.sdn_live_api_base_url,
          "error.message" => "Authentication error") do
          assert_raises ApiServiceError do
            # returns 401 which raises Faraday::RetriableResponse which is caught by the retry middleware
            response = make_request("trade_controls/sdn/unauthorized_live_error", allow_playback_repeats: true) do
              ApiService.make_live_request(body: @user_request_body, owner_type: :USER)
            end
          end
        end

        retry_expected_tags = [
          "exception:TradeCompliance::TradeScreening::ApiServiceAuthenticationError"
        ]
        assert_dogstats_increment 3, "sdn_api_service.connection_retry", tags: retry_expected_tags

        expected_tags_failure = [
          "reason:Request to the SDN API failed because of TradeCompliance::TradeScreening::ApiServiceAuthenticationError error",
          "eid:#{@user_request_body.dig(:ScrReqsEnv, :EId)}",
          "owner_type:USER",
        ]
        assert_dogstats_increment 1, "sdn_api_service.live.failed", tags: expected_tags_failure
        assert_dogstats_timing(1, "sdn_api_service.live.time", tags: expected_tags_failure)

        needle = Failbot.reports.last
        assert_equal "TradeCompliance::TradeScreening::ApiServiceAuthenticationError", Failbot.exception_classname_from_hash(needle)
        assert_equal "Authentication error", Failbot.exception_message_from_hash(needle)
      end

      test "it requests and updates the auth header after a failed screening request and resets the connection instance" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        # request_1 is the request made through faraday caught by VCR
        # request_2 is the request/response loaded from the VCR yaml file
        # At this point the requests have already been matched by :path
        auth_matcher = lambda do |request_1, request_2|
          # If the request is for a token we don't need to query it
          return true if request_1.uri.ends_with?("oauth2/token")
          # The auth header should not be empty as the first token request will populate it
          assert !request_1.headers["Authorization"].empty?
          # The screening request and the VCR request should have the same auth header
          #   this will check that the tokens from the auth requests have been accepted.
          #   This returns true if passed and so continues the VCR checks
          assert_equal request_1.headers["Authorization"], request_2.headers["Authorization"]
        end

        with_cache_enabled do
          response = make_request("trade_controls/sdn/single_live_retry_token_update", match_requests_on: [:path, auth_matcher]) do
            ApiService.make_live_request(body: @user_request_body, owner_type: :USER)
          end

          # When creating a new connection the auth header should be the cached one
          assert_equal "Bearer token_2", ApiService.live_connection.headers["Authorization"]
        end

        assert_dogstats_increment 2, "sdn_api.request_new_token.success"

        retry_expected_tags = [
          "exception:TradeCompliance::TradeScreening::ApiServiceAuthenticationError"
        ]
        assert_dogstats_increment 1, "sdn_api_service.connection_retry", tags: retry_expected_tags

        expected_tags_success = [
          "status:hit_in_review",
          "eid:#{@user_request_body.dig(:ScrReqsEnv, :EId)}",
          "owner_type:USER",
        ]
        assert_dogstats_increment 1, "sdn_api_service.live.success", tags: expected_tags_success
      end

      test "does not raise error if request fails because of ingestion error but returns ingestion_error status" do
        assert_nothing_raised do
          response = make_request("trade_controls/sdn/live_api_bad_request_error") do
            ApiService.make_live_request(body: @bad_request_body, owner_type: :USER)
          end

          assert_equal "SdnDataValidationError", response.errors[0][:code]
          assert_equal "ingestion_error", response.status
        end
      end

      test "raises bad response error if error code is invalid and logs error" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        conn = GitHub::FaradayClient::External.new(url: "http://example.invalid") do |builder|
          builder.adapter :test do |stub|
            stub.post(GitHub.sdn_live_api_url_path) do
              [
                200,
                { "Content-Type": "text/plain", },
                "{\"ScrRespEnv\":{\"EId\":\"d60756eb-bd19-4013-GTHB-1SSINDTST201\",\"DT\":\"2020-10-23T12:40:27.607921\",\"SummResult\":\"Unknown Error\",\"ScrResps\":{\"ScrResp\":[{\"ReqID\":\"\",\"ExternalRefID\":\"d60756eb-bd19-4013-GTHB-1SSINDTST201\",\"Result\":\"Unknown Error\",\"ResultDesc\":\"\",\"Type\":\"Address\",\"Errs\":{\"Err\":[{\"ErrCode\":\"UnknownError\",\"ErrDesc\":\"Unknown\"}]}}]}}}"
              ]
            end
          end
        end

        ApiService.stubs(:live_connection).returns(conn)

        assert_logged(
          "Body" => "sdn_api_service.failed",
          "gh.sdn_api_service.type" => "live",
          "gh.sdn_api_service.url" => GitHub.sdn_live_api_base_url) do
          assert_raises ApiServiceError do
            ApiService.make_live_request(owner_type: :USER, body: {})
          end
        end

        expected_tags_failure = [
          "reason:Request to the SDN API failed because of TradeCompliance::TradeScreening::ApiServiceBadResponseError error",
          "eid:",
          "owner_type:USER",
        ]
        assert_dogstats_increment 1, "sdn_api_service.live.failed", tags: expected_tags_failure
        assert_dogstats_timing(1, "sdn_api_service.live.time", tags: expected_tags_failure)

        needle = Failbot.reports.last
        assert_equal "TradeCompliance::TradeScreening::ApiServiceBadResponseError", Failbot.exception_classname_from_hash(needle)
        assert_equal "SdnErrorUnknown: Unknown, SdnErrorUnknown: SDN LIVE response is invalid: Screening status: unknown_error", Failbot.exception_message_from_hash(needle)
      end

      test "should report LiveResponseParsingError instead of NoMethodError to Sentry if ScrResp array is empty" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        eid = "d60756eb-bd19-4013-GTHB-1SSINDTST201"
        conn = GitHub::FaradayClient::External.new(url: "http://example.invalid") do |builder|
          builder.adapter :test do |stub|
            stub.post(GitHub.sdn_live_api_url_path) do
              [
                200,
                { "Content-Type": "text/plain", },
                "{\"ScrRespEnv\":{\"EId\":\"#{eid}\",\"DT\":\"2020-10-23T12:40:27.607921\",\"SummResult\":\"Unknown Error\",\"ScrResps\":{\"ScrResp\":[]}}}"
              ]
            end
          end
        end

        ApiService.stubs(:live_connection).returns(conn)

        assert_logged("Body" => "sdn_api_service.failed", "gh.sdn_api_service.type" => "live") do
          assert_raises ApiServiceError do
            ApiService.make_live_request(owner_type: :USER, body: {  ScrReqsEnv: { EId: eid } })
          end
        end

        needle = Failbot.reports.last
        assert_equal "TradeCompliance::TradeScreening::LiveResponseParsingError", Failbot.exception_classname_from_hash(needle)
        assert_equal "Expected ScrResp array to have at least one response. EID: #{eid}", Failbot.exception_message_from_hash(needle)
      end

      test "raises bad response error if response payload is invalid and logs error" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        conn = GitHub::FaradayClient::External.new(url: "http://example.invalid") do |builder|
          builder.adapter :test do |stub|
            stub.post(GitHub.sdn_live_api_url_path) do
              [
                200,
                { "Content-Type": "text/plain", },
                "{\"ScrRespEnv\":{\"EId\":\"d60756eb-bd19-4013-GTHB-1SSINDTST201\",\"DT\":\"2020-10-23T12:41:54.376233\",\"SummResult\":\"Hit in Review\",\"ScrResps\":{\"SomeRandomKey\":[{\"ReqID\":\"IndName_IndAddr\",\"ExternalRefID\":\"d60756eb-bd19-4013-GTHB-1SSINDTST201\",\"Result\":\"Hit in Review\",\"ResultDesc\":\"\",\"Type\":\"Address\",\"Errs\":{\"Err\":[{\"ErrCode\":\"\",\"ErrDesc\":\"\"}]}}]}}}"
              ]
            end
          end
        end

        ApiService.stubs(:live_connection).returns(conn)

        assert_logged("Body" => "sdn_api_service.failed", "gh.sdn_api_service.type" => "live") do
          assert_raises ApiServiceError do
            ApiService.make_live_request(owner_type: :USER, body: {})
          end
        end

        expected_tags = [
          "reason:Request to the SDN API failed because of TradeCompliance::TradeScreening::LiveResponseParsingError error",
          "eid:",
          "owner_type:USER",
        ]

        assert_dogstats_increment 1, "sdn_api_service.live.failed", tags: expected_tags
        assert_dogstats_timing(1, "sdn_api_service.live.time", tags: expected_tags)
        Faraday.default_connection = nil

        needle = Failbot.reports.last
        assert_equal "TradeCompliance::TradeScreening::LiveResponseParsingError", Failbot.exception_classname_from_hash(needle)
        assert_equal "SDN LIVE response is missing required keys: ScrResp", Failbot.exception_message_from_hash(needle)
      end

      test "successfully makes user live sdn request and logs success" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        expected_log = {
          "Body" => "sdn_api_service.success",
          "gh.sdn_api_service.type" => "live",
          "gh.sdn_api_service.url" => GitHub.sdn_live_api_base_url,
        }

        assert_logged(**expected_log) do
          response = make_request("trade_controls/sdn/valid_user_live_api_call") do
            ApiService.make_live_request(body: @user_request_body, owner_type: :USER)
          end

          expected_tags = [
            "status:hit_in_review",
            "eid:#{response.eid}",
            "owner_type:USER",
          ]

          assert_dogstats_increment 1, "sdn_api_service.live.success", tags: expected_tags
          assert_dogstats_timing(1, "sdn_api_service.live.time", tags: expected_tags)
          assert_equal "hit_in_review", response.status
        end
      end

      test "successfully makes business live sdn request and logs success" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        expected_log = {
          "Body" => "sdn_api_service.success",
          "gh.sdn_api_service.type" => "live",
          "gh.sdn_api_service.url" => GitHub.sdn_live_api_base_url,
        }

        assert_logged(**expected_log) do
          response = make_request("trade_controls/sdn/valid_business_live_api_call") do
            ApiService.make_live_request(body: @business_request_body, owner_type: :ORGANIZATION)
          end

          expected_tags = [
            "status:hit_in_review",
            "eid:#{response.eid}",
            "owner_type:ORGANIZATION",
          ]

          assert_dogstats_increment 1, "sdn_api_service.live.success", tags: expected_tags
          assert_dogstats_timing(1, "sdn_api_service.live.time", tags: expected_tags)
          assert_equal "hit_in_review", response.status
        end
      end

      test "#request_trade_screening gets request body for individual and calls #make_live_request" do
        profile = T.let(create(:account_screening_profile), AccountScreeningProfile)
        customer_details = CustomerDetails.new(
          id: "1",
          first_name: profile.first_name,
          last_name: profile.last_name,
          address1: profile.address1,
          city: profile.city,
          region: profile.region,
          country_code: profile.country_code,
          postal_code: profile.postal_code)
        screening_details = T.let(ScreeningDetails.new(account_type: AccountType::Individual, external_id: SecureRandom.uuid), ScreeningDetails)
        screening_details.add_customer_details(details: customer_details)

        business_details = T.let(CustomerDetails.new(id: "2", entity_name: "OctoFactory", address1: "1 Infinity Loop", city: "San Francisco", region: "California", country_code: "US", postal_code: "94105"), CustomerDetails)
        business_screening_details = T.let(ScreeningDetails.new(account_type: AccountType::Business, external_id: SecureRandom.uuid), ScreeningDetails)
        business_screening_details.add_customer_details(details: business_details)

        ScreeningDetails.any_instance.expects(:to_hash).once.returns({})
        ApiService.expects(:make_live_request).once.returns(TradeCompliance::TradeScreening::LiveResponse.new(external_uuid: "1", eid: "1", status: "hit_in_review", status_reason: "hit_in_review"))

        ApiService.request_trade_screening(hydro_actor: profile.hydro_actor, screening_details: screening_details)
      end

      test "#request_trade_screening gets request body for business org and calls #make_live_request" do
        profile = T.let(create(:account_screening_profile, :with_org), AccountScreeningProfile)
        customer_details = CustomerDetails.new(
          id: "1",
          entity_name: profile.entity_name,
          address1: profile.address1,
          city: profile.city,
          region: profile.region,
          country_code: profile.country_code,
          postal_code: profile.postal_code)
        screening_details = T.let(ScreeningDetails.new(account_type: AccountType::Business, external_id: SecureRandom.uuid), ScreeningDetails)
        screening_details.add_customer_details(details: customer_details)

        ScreeningDetails.any_instance.expects(:to_hash).once.returns({})
        ApiService.expects(:make_live_request).once.returns(TradeCompliance::TradeScreening::LiveResponse.new(external_uuid: "1", eid: "1", status: "hit_in_review", status_reason: "hit_in_review"))

        ApiService.request_trade_screening(hydro_actor: profile.hydro_actor, screening_details: screening_details)
      end

      # Yes there is only one error, but this list could change in the future
      [Faraday::ConnectionFailed].each do |error|
        test "retries call on #{error} error" do
          stats = GitHub::MemoryDogstatsD.new
          GitHub.stubs(:dogstats).returns(stats)
          ApiService.stubs(:live_connection).returns(live_conn_stub(error))

          assert_raises ApiServiceError do
            ApiService.make_live_request(owner_type: :USER)
          end

          expected_retry_tags = [
            "exception:#{error}"
          ]

          assert_dogstats_increment 3, "sdn_api_service.connection_retry", tags: expected_retry_tags

          expected_tags = [
            "reason:Request to the SDN API failed because of #{error} error",
            "eid:",
            "owner_type:USER",
          ]

          assert_dogstats_increment 1, "sdn_api_service.live.failed", tags: expected_tags
        end
      end

      [Faraday::TimeoutError, Errno::ETIMEDOUT].each do |error|
        test "it does not retry on timeout error #{error}" do
          ApiService.stubs(:live_connection).returns(live_conn_stub(error))

          assert_raises ApiServiceError do
            ApiService.make_live_request(owner_type: :USER)
          end

          assert_dogstats_increment 0, "sdn_api_service.connection_retry"

          expected_tags = [
            "reason:Request to the SDN API failed because of #{error} error",
            "eid:",
            "owner_type:USER",
          ]
          assert_dogstats_increment 1, "sdn_api_service.live.failed", tags: expected_tags
        end
      end

      test "it raises and reports authentication error if OAuth2 client credentials is invalid" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        client_secret_matcher = lambda do |request_1, request_2|
          invalid_client = "client_secret=INVALID"
          client_secret_1 = request_1.body.split("&")[1]
          client_secret_2 = request_2.body.split("&")[1]
          client_secret_2 == invalid_client && client_secret_2 == invalid_client
        end

        ApiService.remove_instance_variable(:@live_conn) if ApiService.instance_variable_defined?(:@live_conn)
        assert_logged("Body" => "sdn_api_service.failed", "gh.sdn_api_service.type" => "live", "error.message" => "Unauthorized due to Invalid client credentials") do
          assert_raises ApiServiceError do
            response = make_request("trade_controls/sdn/invalid_client_secret", match_requests_on: [client_secret_matcher], allow_playback_repeats: true) do
              ApiService.make_live_request(body: @user_request_body, owner_type: :USER)
            end
          end
        end

        expected_tags_failure = [
          "reason:Request to the SDN API failed because of TradeCompliance::TradeScreening::SDNAuthenticationError error",
          "eid:#{@user_request_body.dig(:ScrReqsEnv, :EId)}",
          "owner_type:USER",
        ]
        assert_dogstats_increment 1, "sdn_api_service.live.failed", tags: expected_tags_failure
        assert_dogstats_timing(1, "sdn_api_service.live.time", tags: expected_tags_failure)

        needle = Failbot.reports.last
        assert_equal "TradeCompliance::TradeScreening::SDNAuthenticationError", Failbot.exception_classname_from_hash(needle)
        assert_equal "Unauthorized due to Invalid client credentials", Failbot.exception_message_from_hash(needle)
      end

      test "it reports unexpected HTTP status" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        conn = GitHub::FaradayClient::External.new(url: "http://example.invalid") do |builder|
          builder.adapter :test do |stub|
            stub.post(GitHub.sdn_live_api_url_path) do
              [
                500,
                { "Content-Type": "text/plain", },
                "{}"
              ]
            end
          end
        end

        ApiService.stubs(:live_connection).returns(conn)

        assert_logged("Body" => "sdn_api_service.failed", "gh.sdn_api_service.type" => "live", "error.message" => "Request to the SDN API failed because of 500 HTTP status") do
          assert_raises ApiServiceError do
            ApiService.make_live_request(owner_type: :USER, body: {})
          end
        end
      end
    end

    context "eis" do
      test "it raises and reports authentication error if access token is invalid and retries does not resolve it" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        assert_logged(
          "Body" => "sdn_api_service.failed",
          "gh.sdn_api_service.type" => "eis",
          "gh.sdn_api_service.url" => GitHub.sdn_eis_api_base_url,
          "error.message" => "Authentication error") do
          assert_raises ApiServiceError do
            response = make_request("trade_controls/sdn/unauthorized_eis_error", allow_playback_repeats: true) do
              ApiService.make_eis_request
            end
          end
        end

        retry_expected_tags = [
          "exception:TradeCompliance::TradeScreening::ApiServiceAuthenticationError"
        ]
        assert_dogstats_increment 3, "sdn_api_service.connection_retry", tags: retry_expected_tags

        expected_tags_failure = [
          "reason:Request to the SDN API failed because of TradeCompliance::TradeScreening::ApiServiceAuthenticationError error",
          "owner_type:UNKNOWN",
        ]
        assert_dogstats_increment 1, "sdn_api_service.eis.failed", tags: expected_tags_failure
        assert_dogstats_timing(1, "sdn_api_service.eis.time", tags: expected_tags_failure)

        needle = Failbot.reports.last
        assert_equal "TradeCompliance::TradeScreening::ApiServiceAuthenticationError", Failbot.exception_classname_from_hash(needle)
        assert_equal "Authentication error", Failbot.exception_message_from_hash(needle)
      end

      test "it requests and updates the auth header after a failed eis request and resets the connection instance" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        # request_1 is the request made through faraday caught by VCR
        # request_2 is the request/response loaded from the VCR yaml file
        # At this point the requests have already been matched by :path
        auth_matcher = lambda do |request_1, request_2|
          # If the request is for a token we don't need to query it
          return true if request_1.uri.ends_with?("oauth2/token")
          # The auth header should not be empty as the first token request will populate it
          assert !request_1.headers["Authorization"].empty?
          # The EIS request and the VCR request should have the same auth header
          #   this will check that the tokens from the auth requests have been accepted.
          #   This returns true if passed and so continues the VCR checks
          assert_equal request_1.headers["Authorization"], request_2.headers["Authorization"]
        end

        with_cache_enabled do
          response = make_request("trade_controls/sdn/single_eis_retry_token_update", match_requests_on: [:path, auth_matcher]) do
            ApiService.make_eis_request
          end

          # When creating a new connection the auth header should be the cached one
          assert_equal "Bearer token_2", ApiService.eis_connection.headers["Authorization"]
        end

        assert_dogstats_increment 2, "sdn_api.request_new_token.success"

        retry_expected_tags = [
          "exception:TradeCompliance::TradeScreening::ApiServiceAuthenticationError"
        ]
        assert_dogstats_increment 1, "sdn_api_service.connection_retry", tags: retry_expected_tags

        expected_tags_success = [
          "status:true_match",
          "eid:",
          "owner_type:UNKNOWN",
        ]
        assert_dogstats_increment 1, "sdn_api_service.eis.success", tags: expected_tags_success
      end

      test "successfully makes eis sdn request" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        response = make_request("trade_controls/sdn/valid_eis_api_call") do
          ApiService.make_eis_request
        end

        expected_response = []
        expected_message = EisBusResponse::Message.new(eid: "", request_date_string: "2020-10-13T12:02:25.5056640-00:00", result_text: "True Match", response: EisBusResponse::Response.new)
        expected_message.requests << EisBusResponse::Request.new(
          request_id: "IndName_IndAddr",
          external_id: "d60756eb-bd19-4013-GTHB-1SSINDTST36",
          result_text: "True Match",
          status_reason: "Entity / Individual matched to list",
          alert_id: "00000000000000011950",
          type: "Address",
        )
        expected_message.requests << EisBusResponse::Request.new(
          request_id: "1",
          external_id: "d60756eb-bd19-4013-GTHB-1SSINDTST36",
          result_text: "No Hit",
          status_reason: "Entity / Individual cleared",
          alert_id: "00000000000000011950",
          type: "Address",
        )
        assert_equal true, response.last_offset.present?
        assert_equal [expected_message.serialize], response.messages.map(&:serialize)

        assert_dogstats_increment 1, "sdn_api_service.eis.success"
        assert_dogstats_timing(1, "sdn_api_service.eis.time")
      end

      test "should gracefully handle the case where the screening record owner is deleted before the EIS update is received for the record" do
        upp = create(:account_screening_profile, external_uuid: "d60756eb-bd19-4013-GTHB-1SSINDTST36")
        upp.owner.delete
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        response = make_request("trade_controls/sdn/valid_eis_api_call") do
          ApiService.make_eis_request
        end

        expected_message = EisBusResponse::Message.new(eid: "", request_date_string: "2020-10-13T12:02:25.5056640-00:00", result_text: "True Match", response: EisBusResponse::Response.new)
        expected_message.requests << EisBusResponse::Request.new(
          request_id: "IndName_IndAddr",
          external_id: "d60756eb-bd19-4013-GTHB-1SSINDTST36",
          result_text: "True Match",
          status_reason: "Entity / Individual matched to list",
          alert_id: "00000000000000011950",
          type: "Address",
        )
        expected_message.requests << EisBusResponse::Request.new(
          request_id: "1",
          external_id: "d60756eb-bd19-4013-GTHB-1SSINDTST36",
          result_text: "No Hit",
          status_reason: "Entity / Individual cleared",
          alert_id: "00000000000000011950",
          type: "Address",
        )
        assert_equal true, response.last_offset.present?
        assert_equal [expected_message.serialize], response.messages.map(&:serialize)

        assert_dogstats_increment 1, "sdn_api_service.eis.success"
        assert_dogstats_timing(1, "sdn_api_service.eis.time")
      end

      test "it raises and reports authentication error if OAuth2 client credentials is invalid" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        assert_logged("Body" => "sdn_api_service.failed", "gh.sdn_api_service.type" => "eis", "error.message" => "Unauthorized due to Invalid client credentials") do
          assert_raises ApiServiceError do
            response = make_request("trade_controls/sdn/invalid_client_secret", allow_playback_repeats: true) do
              ApiService.make_eis_request
            end
          end
        end

        expected_tags_failure = [
          "reason:Request to the SDN API failed because of TradeCompliance::TradeScreening::SDNAuthenticationError error",
          "eid:",
          "owner_type:UNKNOWN",
        ]
        assert_dogstats_increment 1, "sdn_api_service.eis.failed", tags: expected_tags_failure
        assert_dogstats_timing(1, "sdn_api_service.eis.time", tags: expected_tags_failure)

        needle = Failbot.reports.last
        assert_equal "TradeCompliance::TradeScreening::SDNAuthenticationError", Failbot.exception_classname_from_hash(needle)
        assert_equal "Unauthorized due to Invalid client credentials", Failbot.exception_message_from_hash(needle)
      end

      test "it reports unexpected HTTP status" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        conn = GitHub::FaradayClient::External.new(url: "http://example.invalid") do |builder|
          builder.adapter :test do |stub|
            stub.get("#{GitHub.sdn_eis_api_sub_path}/alertreview/1.0/0?batchsize=900") do
              [
                500,
                { "Content-Type": "text/plain", },
                "{}"
              ]
            end
          end
        end

        ApiService.stubs(:eis_connection).returns(conn)

        assert_logged("Body" => "sdn_api_service.failed", "gh.sdn_api_service.type" => "eis", "error.message" => "Request to the SDN API failed because of 500 HTTP status") do
          assert_raises ApiServiceError do
            ApiService.make_eis_request
          end
        end
      end
    end
  end
end
