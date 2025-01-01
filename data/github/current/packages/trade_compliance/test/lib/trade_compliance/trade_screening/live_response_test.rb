# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class LiveResponseTest < GitHub::TestCase
    setup do
      skip unless GitHub.billing_enabled?

      @response = JSON.parse(
        Rails.root.join("test", "fixtures", "trade_controls", "sdn", "ind_name_addr_res.json").read,
        symbolize_names: true
      )
    end

    test "can extract the 2 screening results for 2 profiles from the SDN response received" do
      responses = LiveResponse.parse(response: @response).live_responses
      assert_equal 2, responses.size
      assert_equal 0, T.must(responses[0]).errors.size
      assert_equal 2, T.must(responses[1]).errors.size

      # status is correctly extracted
      assert_equal "no_hit", T.must(responses[0]).status
      assert_equal "true_match", T.must(responses[1]).status

      # status reason is correctly extracted
      assert_equal "sample description 1", T.must(responses[0]).status_reason
      assert_equal "sample description 2", T.must(responses[1]).status_reason

      # external uuid is correctly extracted
      assert_equal @response[:ScrRespEnv][:ScrResps][:ScrResp][0][:ExternalRefID], T.must(responses[0]).external_uuid
      assert_equal @response[:ScrRespEnv][:ScrResps][:ScrResp][1][:ExternalRefID], T.must(responses[1]).external_uuid

      # EId (Envelope ID) is correctly extracted
      assert_equal @response[:ScrRespEnv][:EId], T.must(responses[0]).eid
      assert_equal @response[:ScrRespEnv][:EId], T.must(responses[1]).eid

      # errors are correctly mapped
      error_values = LiveResponse::SDN_ERROR_CODE_MAP.values
      assert_includes error_values, T.must(T.must(responses[1]).errors[0])[:code]
      assert_includes error_values, T.must(T.must(responses[1]).errors[1])[:code]

      assert_nil Failbot.reports.last
    end

    test "reports an error if the EId key is present but the value is blank" do
      @response[:ScrRespEnv][:EId] = ""
      response = T.must(LiveResponse.parse(response: @response).live_responses.first)

      assert_equal 1, response.errors.size
      assert_equal({ code: "SdnErrorUnknown", message: "SDN LIVE response is invalid: EId" }, response.errors.first)
    end

    test "reports an error if the ExternalRefID key is present but the value is blank" do
      @response[:ScrRespEnv][:ScrResps][:ScrResp].first[:ExternalRefID] = ""
      response = T.must(LiveResponse.parse(response: @response).live_responses.first)

      assert_equal 1, response.errors.size
      assert_equal({ code: "SdnErrorUnknown", message: "SDN LIVE response is invalid: External ref" }, response.errors.first)
    end

    test "reports an error if the Result key is present but the value is blank or invalid" do
      @response[:ScrRespEnv][:ScrResps][:ScrResp].first[:Result] = ""
      response = T.must(LiveResponse.parse(response: @response).live_responses.first)

      assert_equal 1, response.errors.size
      assert_equal({ code: "SdnErrorUnknown", message: "SDN LIVE response is invalid: Screening status: " }, response.errors.first)

      @response[:ScrRespEnv][:ScrResps][:ScrResp].first[:Result] = "invalid"
      response = T.must(LiveResponse.parse(response: @response).live_responses.first)

      assert_equal 1, response.errors.size
      assert_equal({ code: "SdnErrorUnknown", message: "SDN LIVE response is invalid: Screening status: invalid" }, response.errors.first)
    end

    test "raises exception if the response has changed and doesn't contain keys ScrRespEnv" do
      err = assert_raises LiveResponseParsingError do
        LiveResponse.parse(response: {})
      end

      assert_equal "SDN LIVE response is missing required keys: ScrRespEnv", err.message
    end

    test "raises exception if the response has changed and doesn't contain keys EId and ScrResps" do
      err = assert_raises LiveResponseParsingError do
        LiveResponse.parse(response: { ScrRespEnv: {} })
      end

      assert_equal "SDN LIVE response is missing required keys: EId, ScrResps", err.message
    end

    test "raises exception if the response has changed and doesn't contain keys EId and ScrResp" do
      err = assert_raises LiveResponseParsingError do
        LiveResponse.parse(response: { ScrRespEnv: { ScrResps: {} } })
      end

      assert_equal "SDN LIVE response is missing required keys: EId, ScrResp", err.message
    end

    test "reports when an error has no match in LiveResponse::SDN_ERROR_CODE_MAP" do
      quick_response = { ScrRespEnv: { EId: "Eid", SummResult: "true_match", ScrResps: { ScrResp: [{ ExternalRefID: "refId", Result: "true_match", Errs: { Err: [{ ErrCode: "RandomErrorNotInMap", ErrDesc: "new error" }] } }] } } }

      responses = LiveResponse.parse(response: quick_response)
      needle = Failbot.reports.last

      assert_equal "TradeCompliance::TradeScreening::LiveResponseParsingError", Failbot.exception_classname_from_hash(needle)
      assert_match "SDN received error code wasn't found in the error code map. received code: RandomErrorNotInMap", Failbot.exception_message_from_hash(needle)
    end
  end
end
