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

    test "logs request" do
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

  context "#filter_by_stamp" do
    test "webhook is created and processed when there is no stamp key in the webhook in the dotcom stamp" do
      data = { event_category: "payment_processed", subscription_id: "test_id", other: "test_other" }
      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
      )

      post "/billing/zuora", params: data, headers: {
        "HTTP_AUTHORIZATION": authorization,
      }

      zuora_webhook = Billing::ZuoraWebhook.last!

      assert_response :ok
      assert_equal "payment_processed", zuora_webhook.kind
      refute zuora_webhook.payload["stamp"]
      assert_enqueued_with job: ZuoraWebhookJob, args: [zuora_webhook]
    end

    test "webhook is created and processed when the webhook stamp is an empty string in the dotcom stamp" do
      data = { event_category: "payment_processed", subscription_id: "test_id", other: "test_other", stamp: "" }
      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
      )

      post "/billing/zuora", params: data, headers: {
        "HTTP_AUTHORIZATION": authorization,
      }
      zuora_webhook = Billing::ZuoraWebhook.last!

      assert_response :ok
      assert_equal "payment_processed", zuora_webhook.kind
      assert_equal "", zuora_webhook.payload["stamp"]
      assert_enqueued_with job: ZuoraWebhookJob, args: [zuora_webhook]
    end

    test "wehbook is created and processed when the webhook stamp is nil in the dotcom stamp" do
      data = { event_category: "payment_processed", subscription_id: "test_id", other: "test_other", stamp: nil }
      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
      )

      post "/billing/zuora", params: data, headers: {
        "HTTP_AUTHORIZATION": authorization,
      }

      zuora_webhook = Billing::ZuoraWebhook.last!

      assert_response :ok
      assert_equal "payment_processed", zuora_webhook.kind
      assert_nil zuora_webhook.payload["stamp"]
      assert_enqueued_with job: ZuoraWebhookJob, args: [zuora_webhook]
    end

    test "webhook is created and processed when the webhook stamp matches the current stamp" do
      data = { event_category: "payment_processed", subscription_id: "test_id", other: "test_other", stamp: "dotcom" }
      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
      )

      post "/billing/zuora", params: data, headers: {
        "HTTP_AUTHORIZATION": authorization,
      }

      zuora_webhook = Billing::ZuoraWebhook.last!

      assert_response :ok
      assert_equal "payment_processed", zuora_webhook.kind
      assert_equal "dotcom", zuora_webhook.payload["stamp"]
      assert_enqueued_with job: ZuoraWebhookJob, args: [zuora_webhook]
    end

    test "returns 403 and increments the metric when the stamp in the webhook stamp does not match the current stamp" do
      data = { event_category: "payment_processed", subscription_id: "test_id", other: "test_other", stamp: "not_dotcom" }
      authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
        GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
      )
      post "/billing/zuora", params: data, headers: {
        "HTTP_AUTHORIZATION": authorization,
      }

      assert_response :forbidden
      assert_dogstats_increment 1, "zuora.webhook.stamp_mismatch.count", tags: ["webhook_stamp:not_dotcom"]
    end

    test "webhook is created and processed when the webhook stamp matches the current stamp in multi-tenant mode" do
      on_multi_tenant_enterprise do
        GitHub.stubs(:proxima_billing_enabled?).returns(true)
        GitHub::Config::Proxima.stubs(:current_stamp_or_dotcom).returns("staff-wus2-01")

        data = { event_category: "payment_processed", subscription_id: "test_id", other: "test_other", stamp: "staff-wus2-01" }
        authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
          GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
        )

        post "/billing/zuora", params: data, headers: {
          "HTTP_AUTHORIZATION": authorization,
        }

        zuora_webhook = Billing::ZuoraWebhook.last!

        assert_response :ok
        assert_equal "payment_processed", zuora_webhook.kind
        assert_equal "staff-wus2-01", zuora_webhook.payload["stamp"]
        assert_enqueued_with job: ZuoraWebhookJob, args: [zuora_webhook]
      end
    end

    test "returns 422 and increments the metric when the stamp in the webhook stamp does not match the current stamp in multi-tenant mode" do
      on_multi_tenant_enterprise do
        GitHub::Config::Proxima.stubs(:current_stamp_or_dotcom).returns("staff-wus2-01")
        GitHub.stubs(:proxima_billing_enabled?).returns(true)

        data = { event_category: "payment_processed", subscription_id: "test_id", other: "test_other", stamp: "not_proxima" }
        authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
          GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
        )
        post "/billing/zuora", params: data, headers: {
          "HTTP_AUTHORIZATION": authorization,
        }

        assert_response :forbidden
        assert_dogstats_increment 1, "zuora.webhook.stamp_mismatch.count", tags: ["webhook_stamp:not_proxima"]
      end
    end

    test "webhook is not created or processed when there's no value for the webhook stamp in multi-tenant mode" do
      on_multi_tenant_enterprise do
        GitHub.stubs(:proxima_billing_enabled?).returns(true)
        GitHub::Config::Proxima.stubs(:current_stamp_or_dotcom).returns("staff-wus2-01")

        data = { event_category: "payment_processed", subscription_id: "test_id", other: "test_other" }
        authorization = ActionController::HttpAuthentication::Basic.encode_credentials(
          GitHub.zuora_webhook_username, GitHub.zuora_webhook_password
        )
        post "/billing/zuora", params: data, headers: {
          "HTTP_AUTHORIZATION": authorization,
        }

        assert_response :forbidden
        assert_dogstats_increment 1, "zuora.webhook.stamp_mismatch.count", tags: ["webhook_stamp:"]
      end
    end
  end
end if GitHub.billing_enabled?
