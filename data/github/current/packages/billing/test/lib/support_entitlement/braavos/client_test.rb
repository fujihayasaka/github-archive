# typed: true
# frozen_string_literal: true

require "test_helper"

class SupportEntitlementBraavosClientTest < GitHub::TestCase
  SUCCESS_RESPONSE = {
    status: 200,
    body: { condition: "Active Contract", type: "Premier" }.to_json,
    headers: { "Content-Type" => "application/json" }
  }
  NOT_FOUND_RESPONSE = { status: 404 }
  ERROR_RESPONSE = { status: 401 }
  AGREEMENT_URL = "http://braavos.test/agreements_for_subscription/123"
  AGREEMENTS_BY_EA_URL = "http://braavos.test/agreements_for_enterprise_account/10"

  setup do
    GitHub.stubs(:braavos_support_entitlement_url).returns("http://braavos.test")
    GitHub.stubs(:braavos_support_entitlement_hmac).returns("nevermind")
    stub_domain("braavos.test")
    GitHub.flipper[:braavos_debug_logging].stubs(:enabled?).returns(true)
  end

  test "sets hmac header" do
    travel_to Time.zone.local(1991, 9, 24, 00, 00, 00) do
      res = SupportEntitlement::Braavos::Client.get("/")
      hmac = res.env.request_headers["Request-HMAC"]

      encrypted_hmac = "685670400.3288f93dfcc6d3e4da164c5d85ea8410f59f75c10e6b2be3510c8c39b4bf6992"
      assert_equal encrypted_hmac, hmac
    end
  end

  test "raises when not given a 2xx response status" do
    stub_request(:get, "http://braavos.test").to_return(ERROR_RESPONSE)

    assert_raises Faraday::UnauthorizedError do
      SupportEntitlement::Braavos::Client.get("/")
    end
  end

  context "check_entitlements_by_ea" do
    test "successful request returns correct response" do
      expected_response = {
        agreements: [{
          type: "Premier",
          condition: "Active Contract",
          isRevoked: false,
          packages: [
            { serviceOfferingId: 1266 },
            { serviceOfferingId: 1352 },
          ],
          tpid: "12345",
        }],
        eans: %w(555666 666555)
      }

      stub_request(:get, AGREEMENTS_BY_EA_URL).to_return(
        status: 200,
        body: expected_response.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      response = SupportEntitlement::Braavos::Client.check_entitlements_by_ea(id: 10)

      assert_equal(expected_response, response)
    end

    test "raises ApiError when response is not successful" do
      stub_request(:get, AGREEMENTS_BY_EA_URL).to_return(ERROR_RESPONSE)

      assert_raises SupportEntitlement::Braavos::Client::ApiError do
        SupportEntitlement::Braavos::Client.check_entitlements_by_ea(id: 10)
      end
    end

    test "handles Faraday errors" do
      stub_request(:get, AGREEMENTS_BY_EA_URL).to_raise(Faraday::ConnectionFailed)

      GitHub.dogstats.expects(:increment).with("braavos.agreements_for_enterprise_account.response_code", tags: ["response_code:unknown"])
      assert_raises SupportEntitlement::Braavos::Client::ApiError do
        SupportEntitlement::Braavos::Client.check_entitlements_by_ea(id: 10)
      end
    end

    test "retries 500 response code responses" do
      expected_response = {
        agreements: [{
          type: "Premier",
          condition: "Active Contract",
          isRevoked: false,
          packages: [
            { serviceOfferingId: 1266 },
            { serviceOfferingId: 1352 },
          ],
          tpid: "12345",
        }],
        eans: %w(555666 666555)
      }

      stub_request(:get, AGREEMENTS_BY_EA_URL).to_return([
        { status: 500 },
        { status: 500 },
        { status: 500 },
        {
          status: 200,
          body: expected_response.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      ])

      response = SupportEntitlement::Braavos::Client.check_entitlements_by_ea(id: 10)

      assert_equal(expected_response, response)
    end

    test "raises API error if the API returns a 500 error" do
      stub_request(:get, AGREEMENTS_BY_EA_URL).to_return({ status: 500 })

      assert_raises SupportEntitlement::Braavos::Client::ApiError do
        SupportEntitlement::Braavos::Client.check_entitlements_by_ea(id: 10)
      end
    end

    test "handles 404 response and does not raise an error" do
      stub_request(:get, AGREEMENTS_BY_EA_URL).to_return(NOT_FOUND_RESPONSE)

      assert_nothing_raised do
        response = SupportEntitlement::Braavos::Client.check_entitlements_by_ea(id: 10)
        assert_nil response
      end
    end

    test "increments braavos.agreements_for_enterprise_account.response_code " do
      stub_request(:get, AGREEMENTS_BY_EA_URL).to_return(SUCCESS_RESPONSE)

      GitHub.dogstats.expects(:increment).with("braavos.agreements_for_enterprise_account.response_code", tags: ["response_code:200"])
      SupportEntitlement::Braavos::Client.check_entitlements_by_ea(id: 10)
    end

    test "increments braavos.agreements_for_enterprise_account.response_code when response is not successful" do
      stub_request(:get, AGREEMENTS_BY_EA_URL).to_return(ERROR_RESPONSE)

      GitHub.dogstats.expects(:increment).with("braavos.agreements_for_enterprise_account.response_code", tags: ["response_code:401"])
      assert_raises SupportEntitlement::Braavos::Client::ApiError do
        SupportEntitlement::Braavos::Client.check_entitlements_by_ea(id: 10)
      end
    end
  end

  context "check_entitlement" do
    test "successful request returns correct response" do
      stub_request(:get, AGREEMENT_URL).to_return(SUCCESS_RESPONSE)
      response = SupportEntitlement::Braavos::Client.check_entitlement("123")

      assert_equal({ condition: "Active Contract", type: "Premier" }, response)
    end

    test "raises ApiError when response is not successful" do
      stub_request(:get, AGREEMENT_URL).to_return(ERROR_RESPONSE)

      assert_raises SupportEntitlement::Braavos::Client::ApiError do
        SupportEntitlement::Braavos::Client.check_entitlement("123")
      end
    end

    test "handles Faraday errors" do
      stub_request(:get, AGREEMENT_URL).to_raise(Faraday::ConnectionFailed)

      GitHub.dogstats.expects(:increment).with("braavos.agreements_for_subscription.response_code", tags: ["response_code:unknown"])
      assert_raises SupportEntitlement::Braavos::Client::ApiError do
        SupportEntitlement::Braavos::Client.check_entitlement("123")
      end
    end

    test "handles 404 response and does not raise an error" do
      stub_request(:get, AGREEMENT_URL).to_return(NOT_FOUND_RESPONSE)

      assert_nothing_raised do
        response = SupportEntitlement::Braavos::Client.check_entitlement("123")
        assert_equal({ not_found: true }, response)
      end
    end

    test "increments braavos.agreements_for_subscription.response_code " do
      stub_request(:get, AGREEMENT_URL).to_return(SUCCESS_RESPONSE)

      GitHub.dogstats.expects(:increment).with("braavos.agreements_for_subscription.response_code", tags: ["response_code:200"])
      SupportEntitlement::Braavos::Client.check_entitlement("123")
    end

    test "increments braavos.agreements_for_subscription.response_code when response is not successful" do
      stub_request(:get, AGREEMENT_URL).to_return(ERROR_RESPONSE)

      GitHub.dogstats.expects(:increment).with("braavos.agreements_for_subscription.response_code", tags: ["response_code:401"])
      assert_raises SupportEntitlement::Braavos::Client::ApiError do
        SupportEntitlement::Braavos::Client.check_entitlement("123")
      end
    end
  end
end
