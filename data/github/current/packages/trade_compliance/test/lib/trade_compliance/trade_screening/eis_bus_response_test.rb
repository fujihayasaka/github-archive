# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class EisBusResponseTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      skip unless GitHub.billing_enabled?

      @response = JSON.parse(
        Rails.root.join("test", "fixtures", "trade_controls", "sdn", "ind_name_addr_eis_res.json").read,
        symbolize_names: true
      )
    end

    test "successfully parses the response with required keys and ignores non SELFSERV messages" do
      parsed_response = EisBusResponse.parse(response: @response)

      # size should be 2 since one of the messages has a cohort code  of GITHUB-NOTSELFSERV
      assert_equal 2, parsed_response.messages.size

      # last offset is correctly extracted
      assert_equal @response[:lastOffset], parsed_response.last_offset

      # EId (Envelope id) is correctly extracted
      payload = JSON.parse(@response[:messages][0][:messageBody][:messagePayload]).deep_symbolize_keys
      assert_equal payload[:ScrRespEnv][:EId], T.must(parsed_response.messages[0]).eid

      # status is correctly extracted
      message = T.must(parsed_response.messages[0])
      assert_equal 2, message.requests.size
      assert_equal "true_match", message.status
      assert_equal "true_match", T.must(message.requests[0]).status
      assert_equal "IndName_IndAddr", T.must(message.requests[0]).request_id
      assert_equal "no_hit", T.must(message.requests[1]).status
      assert_equal "Foo", T.must(message.requests[1]).request_id
    end

    test "raises exception if the response has changed and doesn't contain keys messages and lastOffset" do
      assert_raises EisBusResponseParsingError do
        EisBusResponse.parse(response: {})
      end
    end

    test "raises exception if messagePayload is missing" do
      error = assert_raises EisBusResponseParsingError do
        response = EisBusResponse.extract_info_from_message({ properties: { Cohort: "GITHUB-SELFSERV" }, messageBody: {} }, "1234")
      end
      assert_match /:messagePayload/, error.message
    end

    test "pushes messages received to hydro data warehouse" do
      EisBusResponse.parse(response: @response)
      expected_messages = @response[:messages].select { |msg| msg[:messageId] != "000d3a6d-00cf-1eeb-83c1-c4c4d18f885b" }
      assert_hydro_messages(count: 3, schema: "github.trade_screening.v0.EisResponse") # we have 2 messages, with 1 message containing 2 requests

      expected_messages.each do |msg|
        msg_payload = JSON.parse(msg[:messageBody][:messagePayload]).deep_symbolize_keys
        result = msg_payload[:ScrRespEnv][:ScrResps][:ScrResp][0]
        assert_hydro_published({
          last_offset: @response[:lastOffset],
          message: {
            request_id: result[:ReqID],
            external_user_id: result[:ExternalRefID],
            result: result[:Result],
            result_description: result[:ResultDesc],
            type: result[:Type],
            alert_id: result[:AlertID],
            eid: msg_payload[:ScrRespEnv][:EId],
            date: Google::Protobuf::Timestamp.new(seconds: Time.iso8601(msg_payload[:ScrRespEnv][:DT]).to_i)
          },
        }, schema: "github.trade_screening.v0.EisResponse")
      end
    end
  end
end
