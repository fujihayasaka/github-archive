# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Signature::RsaTest < GitHub::BillingTestCase

  context ".generate" do
    test "returns nil if connection to Zuora times out" do
      stub_request(:post, "#{GitHub.zuora_rest_server}/v1/rsa-signatures").to_timeout

      # .to_timeout is interpreted as a Faraday::ConnectionFailed by the HTTP client
      GitHub.dogstats.expects(:increment).with("zuora.connection_failed")

      rsa_signature = Billing::Zuora::Signature::RSA.generate(
        uri: GitHub.zuora_payment_page_uri,
        page_id: GitHub.zuora_settings_regular_light_default_payment_page_id,
        account_id: "123",
      )

      assert_nil rsa_signature
    end

    test "returns signature" do
      rsa_signature = Billing::Zuora::Signature::RSA.generate(
        uri: GitHub.zuora_payment_page_uri,
        page_id: GitHub.zuora_settings_regular_light_default_payment_page_id,
        account_id: "123",
      )

      assert_equal "kzxphj0ABjaJtAsjmvsJ8vYzj9Yvn2W9", rsa_signature.token
    end
  end
end
