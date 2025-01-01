# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Azure::SubscriptionClientTest < GitHub::TestCase

  setup do
    @http_client = GitHub::Azure::HttpClient.new
    @subscription_client = Billing::Azure::SubscriptionClient.new(http_client: @http_client)
  end

  context "#subscription_exists?" do
    test "401 means the subscription id exists" do
      subscription_id = "B2ACD84C-1862-423E-87B4-77AC8070B068"
      Billing::Kv.store.del("azure.subscription_status[#{subscription_id}]")
      expected_uri  = "https://management.azure.com/subscriptions/#{subscription_id}?api-version=2022-12-01"
      GitHub::Azure::HttpClient.any_instance.expects(:send_request).with(method: :get, uri: expected_uri).raises(Faraday::ClientError.new({ status: 401 }))

      status = @subscription_client.subscription_exists?(subscription_id: subscription_id)
      assert status[:exists]
    end

    test "404 means the subscription id does not exist" do
      subscription_id = "B2ACD84C-1862-423E-87B4-77AC8070B068"
      Billing::Kv.store.del("azure.subscription_status[#{subscription_id}]")
      expected_uri  = "https://management.azure.com/subscriptions/#{subscription_id}?api-version=2022-12-01"
      GitHub::Azure::HttpClient.any_instance.expects(:send_request).with(method: :get, uri: expected_uri).raises(Faraday::ClientError.new({ status: 404 }))

      status = @subscription_client.subscription_exists?(subscription_id: subscription_id)
      refute status[:exists]
      assert_equal Billing::Azure::SubscriptionClient::SUBSCRIPTION_DOES_NOT_EXIST, status[:reason]
    end

    test "can cache valid status" do
      subscription_id = "B2ACD84C-1862-423E-87B4-77AC8070B068"
      expected_uri = "https://management.azure.com/subscriptions/#{subscription_id}?api-version=2022-12-01"

      Billing::Kv.store.del("azure.subscription_status[#{subscription_id}]")
      Timecop.freeze(Time.now) do
        GitHub::Azure::HttpClient.any_instance.expects(:send_request).with(method: :get, uri: expected_uri).raises(Faraday::ClientError.new({ status: 401 }))
        Billing::Kv.store.expects(:set).with(
          "azure.subscription_status[#{subscription_id}]",
          { exists: true, subscription_id: subscription_id }.to_json,
          expires: 4.hours.from_now
        )
        status = @subscription_client.subscription_exists?(subscription_id: subscription_id)
        assert status[:exists]
      end
    end

    test "can cache invalid status" do
      subscription_id = "B2ACD84C-1862-423E-87B4-77AC8070B068"
      expected_uri = "https://management.azure.com/subscriptions/#{subscription_id}?api-version=2022-12-01"
      cache_object = {
        exists: false,
        subscription_id: subscription_id,
        reason: "subscription does not exist.",
      }

      Billing::Kv.store.del("azure.subscription_status[#{subscription_id}]")
      Timecop.freeze(Time.now) do
        GitHub::Azure::HttpClient.any_instance.expects(:send_request).with(method: :get, uri: expected_uri).raises(Faraday::ClientError.new({ status: 404 }))
        Billing::Kv.store.expects(:set).with("azure.subscription_status[#{subscription_id}]", cache_object.to_json, expires: 4.hours.from_now)
        status = @subscription_client.subscription_exists?(subscription_id: subscription_id)
        refute status[:exists]
      end
    end

    test "can get cached status" do
      subscription_id = "B2ACD84C-1862-423E-87B4-77AC8070B068"

      Billing::Kv.store.set("azure.subscription_status[#{subscription_id}]", { exists: true }.to_json)
      GitHub::Azure::HttpClient.any_instance.expects(:send_request).times(0)

      status = @subscription_client.subscription_exists?(subscription_id: subscription_id)
      assert status[:exists]
    end

  end


  context "#subscription_permissions" do
    test "logs error when failing to fetch subscription permissions" do
      subscription_id = "SUBSCRIPTION_ID_TEST"
      expected_uri = "https://management.azure.com/subscriptions/#{subscription_id}/providers/Microsoft.Authorization/permissions?api-version=2022-04-01"
      error = Faraday::ClientError.new("network error")

      GitHub.logger.expects(:error).with("Failed to fetch Azure subscription permissions", {
        exception: error,
        uri: expected_uri,
        subscription_id: subscription_id,
        context: "Billing::Azure::SubscriptionClient#subscription_permissions"
      })

      GitHub::Azure::HttpClient.any_instance.expects(:send_request).with(method: :get, uri: expected_uri).raises(error)

      assert_raises(Billing::Azure::SubscriptionClient::UnableToFetchAzureSubscriptionPermissionsError) do
        @subscription_client.subscription_permissions(subscription_id: subscription_id)
      end
    end
  end

  context "#tenants" do
    test "logs structured error when failing to fetch tenants" do
      expected_uri = "https://management.azure.com/tenants?api-version=2022-12-01"
      error = Faraday::ClientError.new("network error")

      GitHub.logger.expects(:error).with("Failed to fetch Azure tenants", {
        exception: error,
        uri: expected_uri,
        context: "Billing::Azure::SubscriptionClient#tenants"
      })

      GitHub::Azure::HttpClient.any_instance.expects(:send_request).with(method: :get, uri: expected_uri).raises(error)

      assert_raises(Billing::Azure::SubscriptionClient::UnableToFetchAzureTenantsError) do
        @subscription_client.tenants
      end
    end
  end

end
