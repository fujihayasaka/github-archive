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

  setup do
    GitHub.stubs(:braavos_support_entitlement_url).returns("http://braavos.test")
    GitHub.stubs(:braavos_support_entitlement_hmac).returns("nevermind")
    stub_domain("braavos.test")
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

  test "check_entitlement" do
    stub_request(:get, AGREEMENT_URL).to_return(SUCCESS_RESPONSE)
    response = SupportEntitlement::Braavos::Client.check_entitlement("123")

    assert_equal({ condition: "Active Contract", type: "Premier" }, response)
  end

  test "check_entitlement raises ApiError when response is not successful" do
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
