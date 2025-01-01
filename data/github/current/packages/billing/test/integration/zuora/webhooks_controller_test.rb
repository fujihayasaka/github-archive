# typed: true
# frozen_string_literal: true

require "test_helper"

class Zuora::WebhooksControllerTest < GitHub::IntegrationTestCase
  include DogstatsTestHelpers

  context "POST /billing/zuora" do
    test "unauthorized when no credentials are not supplied" do
      post "/billing/zuora"

      assert_response :unauthorized
    end

    test "unauthorized when invalid username" do
      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        "invalid_username", GitHub.zuora_webhook_password
      )

      post "/billing/zuora", headers: { "HTTP_AUTHORIZATION" => authorization }

      assert_response :unauthorized
    end

    test "unauthorized when invalid password" do
      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, "invalid_password"
      )

      post "/billing/zuora", headers: { "HTTP_AUTHORIZATION" => authorization }

      assert_response :unauthorized
    end

    test "success when authenticated successfully" do
      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
      )
      post "/billing/zuora", params: {
        event_category: "payment_processed", subscription_id: "test_id"
      }, headers: { "HTTP_AUTHORIZATION" => authorization }

      assert_response :ok
      assert_dogstats_increment 0, "zuora.webhook.old_password_used"
    end

    test "success when authenticated with the new password when we're in the process of rolling the password in Zuora" do
      GitHub.stubs(:zuora_webhook_password).returns("old password")
      GitHub.stubs(:zuora_webhook_new_password).returns("new password")

      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, "new password"
      )
      post "/billing/zuora", params: {
        event_category: "payment_processed", subscription_id: "test_id"
      }, headers: { "HTTP_AUTHORIZATION" => authorization }

      assert_response :ok
      assert_dogstats_increment 0, "zuora.webhook.old_password_used"
    end

    test "success and increments a counter when authenticated with the old password when we're in the process of rolling the password in Zuora" do
      GitHub.stubs(:zuora_webhook_password).returns("old password")
      GitHub.stubs(:zuora_webhook_new_password).returns("new password")

      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, "old password"
      )
      post "/billing/zuora", params: {
        event_category: "payment_processed", subscription_id: "test_id"
      }, headers: { "HTTP_AUTHORIZATION" => authorization }

      assert_response :ok
      assert_dogstats_increment 1, "zuora.webhook.old_password_used"
    end

    test "unauthorized when the password doesn't match either the new password or the old password" do
      GitHub.stubs(:zuora_webhook_password).returns("old password")
      GitHub.stubs(:zuora_webhook_new_password).returns("new password")

      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, "not any password"
      )
      post "/billing/zuora", params: {
        event_category: "payment_processed", subscription_id: "test_id"
      }, headers: { "HTTP_AUTHORIZATION" => authorization }

      assert_response :unauthorized
    end

    test "unauthorized when the password is blank in the configuration and blank in the request" do
      GitHub.stubs(:zuora_webhook_password).returns("")
      GitHub.stubs(:zuora_webhook_new_password).returns("")

      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, ""
      )
      post "/billing/zuora", params: {
        event_category: "payment_processed", subscription_id: "test_id"
      }, headers: { "HTTP_AUTHORIZATION" => authorization }

      assert_response :unauthorized
    end

    test "unauthorized when the new password is blank in the configuration and blank in the request" do
      GitHub.stubs(:zuora_webhook_password).returns("old password")
      GitHub.stubs(:zuora_webhook_new_password).returns("")

      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, ""
      )
      post "/billing/zuora", params: {
        event_category: "payment_processed", subscription_id: "test_id"
      }, headers: { "HTTP_AUTHORIZATION" => authorization }

      assert_response :unauthorized
    end

    test "returns 401 when the new password is nil in the configuration and nil in the request" do
      GitHub.stubs(:zuora_webhook_password).returns("old password")
      GitHub.stubs(:zuora_webhook_new_password).returns(nil)

      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, nil
      )
      post "/billing/zuora", params: {
        event_category: "payment_processed", subscription_id: "test_id"
      }, headers: { "HTTP_AUTHORIZATION" => authorization }

      assert_response :unauthorized
    end

    test "sends valid requests to be processed by a background job" do
      data = { event_category: "PaymentProcessed", subscription_id: "test_id", other: "test_other" }

      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
      )
      post "/billing/zuora", params: data, headers: {
        "HTTP_AUTHORIZATION": authorization,
      }

      zuora_webhook = Billing::ZuoraWebhook.last

      assert_response :ok
      assert_enqueued_with job: ZuoraWebhookJob, args: [zuora_webhook]
    end

    test "logs requst" do
      data = { event_category: "payment_processed", subscription_id: "test_id", other: "test_other" }

      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
      )
      post "/billing/zuora", params: data, headers: {
        "HTTP_AUTHORIZATION": authorization,
      }

      assert_response :ok
    end
  end
end if GitHub.billing_enabled?
