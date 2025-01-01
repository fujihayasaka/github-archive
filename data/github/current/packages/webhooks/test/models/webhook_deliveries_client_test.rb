# typed: true
# frozen_string_literal: true

require "test_helper"

class WebhookDeliveriesClientTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @hook = create :hook, installation_target: @repo
  end

  setup do
    @parent = "repository-#{@repo.id}"
    @client = WebhookDeliveriesClient.new(@parent)
    @delivery_guid = "30a336da-804f-11e5-9813-b4e9de149e9f"
    @delivery_id = 1
    @webhook_subscription = {
      webhook: {
        id: @hook.id,
        service: @hook.name,
        configuration: {
          url: @hook.url,
          content_type: @hook.content_type,
          insecure_ssl: @hook.insecure_ssl
        }
      },
      parent: @hook.hookshot_parent_id
    }
  end

  context "set up webhook deliveries env" do
    test "it sets the webhook deliveries envs for staging" do
      GitHub.stubs(:dynamic_lab?).returns(true)
      new_client = WebhookDeliveriesClient.new(@parent)
      assert_equal GitHub.staging_webhook_deliveries_url, new_client.instance_variable_get(:@webhook_deliveries_url)
      assert_equal GitHub.staging_webhook_deliveries_token, new_client.instance_variable_get(:@webhook_deliveries_token)
    end

    test "it sets the webhook deliveries envs for production" do
      assert_equal GitHub.webhook_deliveries_url, @client.instance_variable_get(:@webhook_deliveries_url)
      assert_equal GitHub.webhook_deliveries_token, @client.instance_variable_get(:@webhook_deliveries_token)
    end
  end

  context "#deliveries_for_hook" do
    test "it returns the response code" do
      with_stubbed_faraday_response("/deliveries", [200, {}, {}]) do
        status, body = @client.deliveries_for_hook(@hook.id)
        assert_equal 200, status
      end
    end

    test "it returns an array of deliveries belonging to the hook" do
      body = T.let({ deliveries: [{ guid: @delivery_guid, delivered_at: "2020-11-16T22:19:45Z" }] }, T.untyped)
      with_stubbed_faraday_response("/deliveries", [200, {}, body]) do
        _, response_body = @client.deliveries_for_hook(@hook.id)
        deliveries = JSON.parse(response_body)["deliveries"]
        assert_equal 1, deliveries.length
        assert_equal @delivery_guid, deliveries[0]["guid"]
      end
    end


    test "it raises Faraday::ConnectionFailed error" do
      failed_client = WebhookDeliveriesClient.new(@parent)
      failed_client.expects(:get).raises(Faraday::ConnectionFailed, "error")
      assert_raises(Faraday::ConnectionFailed) do
        failed_client.deliveries_for_hook 1
      end
    end

    test "it raise Faraday::TimeoutError" do
      failed_client = WebhookDeliveriesClient.new(@parent)
      failed_client.expects(:get).raises(Faraday::TimeoutError, "error")
      assert_raises(Faraday::TimeoutError) do
        failed_client.deliveries_for_hook 1
      end
    end
  end

  context "#delivery_for_hook" do
    test "it returns blob not found and 500 status code" do
      body = T.let({ "message": "test BlobNotFound" }, T.untyped)
      with_stubbed_faraday_response("/deliveries/123", [500, {}, body]) do
        status, response_body = @client.delivery_for_hook(123, 1)
        assert_equal 500, status
        assert_equal "BlobNotFound", response_body[:message]
      end
    end
  end

  context "#redeliver" do
    test "it returns successful response" do
      body = { "message": "ok" }
      with_stubbed_faraday_response("/redeliver", [200, {}, body], method: :post) do
        status, response_body = @client.redeliver(delivery_id: @delivery_id, webhook_subscription: @webhook_subscription)
        assert_equal 200, status
        assert_equal body.to_json, response_body
      end
    end

    test "it returns unsuccessful response" do
      body = { "message": "error" }
      with_stubbed_faraday_response("/redeliver", [500, {}, body], method: :post) do
        status, response_body = @client.redeliver(delivery_id: @delivery_id, webhook_subscription: @webhook_subscription)
        assert_equal 500, status
        assert_equal body.to_json, response_body
      end
    end
  end

  def with_stubbed_faraday_response(path, response, method: :get)
    status, headers, body = response
    VCR.eject_cassette
    VCR.turned_off do
      faraday = GitHub::FaradayClient::Internal.new(url: GitHub.webhook_deliveries_url) do |f|
        f.adapter :test do |stub|
          stub.send(method, path) do |_env|
            [status, headers, body.to_json]
          end
        end
      end

      @client.stubs(:faraday).returns(faraday)

      yield
    end
  end
end
