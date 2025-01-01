# typed: true
# frozen_string_literal: true

require "test_helper"

class HookDeliveriesClientTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    GitHub.flipper[:events_v2_publish_tier1_event].disable
    GitHub.flipper[:webhook_deliveries_traffic].disable
    @hook = create(:hook)
  end

  setup do
    @parent = "repository-#{@repo.id}"
    @delivery_id = 1
    @hook_id = 1
    @options = { include_payload: true }
    uuid = SimpleUUID::UUID.new(Time.now)
    @guid = uuid.to_guid
    @delivery_id = 3
  end

  context "initialize" do
    test "initialize both webhook deliveries and hookshot client for ui when both events_v2_publish_tier1_event and webhook_deliveries_traffic are enabled" do
      GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.new(@parent))
      GitHub.flipper[:webhook_deliveries_traffic].enable(Events::ParentAsActor.new(@parent))
      WebhookDeliveriesClient.expects(:new).once
      Hookshot::Client.expects(:ui_client_for_parent).once
      client = HookDeliveriesClient.new(@parent)
      assert_instance_of(HookDeliveriesClient, client)
    end

    test "initialize both webhook deliveries and hookshot client for ui when events_v2_publish_tier1_event is disabled and webhook_deliveries_traffic are enabled" do
      GitHub.flipper[:events_v2_publish_tier1_event].disable(Events::ParentAsActor.new(@parent))
      GitHub.flipper[:webhook_deliveries_traffic].enable(Events::ParentAsActor.new(@parent))
      WebhookDeliveriesClient.expects(:new).once
      Hookshot::Client.expects(:ui_client_for_parent).once
      client = HookDeliveriesClient.new(@parent)
      assert_instance_of(HookDeliveriesClient, client)
    end

    test "initialize both webhook deliveries and hookshot client for ui when both events_v2_publish_tier1_event is disabled and webhook_deliveries_traffic are disabled" do
      GitHub.flipper[:events_v2_publish_tier1_event].disable(Events::ParentAsActor.new(@parent))
      GitHub.flipper[:webhook_deliveries_traffic].disable(Events::ParentAsActor.new(@parent))
      WebhookDeliveriesClient.expects(:new).never
      Hookshot::Client.expects(:ui_client_for_parent).once
      client = HookDeliveriesClient.new(@parent)
      assert_instance_of(HookDeliveriesClient, client)
    end

    test "initialize both webhook deliveries and hookshot client for ui when events_v2_publish_tier1_event is enabled and webhook_deliveries_traffic is disabled" do
      GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.new(@parent))
      GitHub.flipper[:webhook_deliveries_traffic].disable(Events::ParentAsActor.new(@parent))
      WebhookDeliveriesClient.expects(:new).never
      Hookshot::Client.expects(:ui_client_for_parent).once
      client = HookDeliveriesClient.new(@parent)
      assert_instance_of(HookDeliveriesClient, client)
    end
  end

  context "#delivery_for_hook" do
    context "when events_v2_publish_tier1_event is disabled" do
      test "invoke only hookshot client delivery if  hookshot client fetch delivery successfully" do
        WebhookDeliveriesClient.any_instance.expects(:delivery_for_hook).never
        Hookshot::Client.any_instance.expects(:delivery_for_hook).with(@delivery_id, @hook_id, @options).returns([200, {}])
        ui_client = HookDeliveriesClient.new(@parent)
        ui_client.delivery_for_hook(@delivery_id, @hook_id, @options)
      end

      test "invoke only hookshot client if hookshot client fetch delivery with 500 error and BlobNotFound message when webhook_deliveries_traffic is disabled" do
        Hookshot::Client.any_instance.expects(:delivery_for_hook).with(@delivery_id, @hook_id, @options).returns([500, { "message" => "BlobNotFound" }])
        WebhookDeliveriesClient.any_instance.expects(:delivery_for_hook).never
        ui_client = HookDeliveriesClient.new(@parent)
        ui_client.delivery_for_hook(@delivery_id, @hook_id, @options)
      end

      test "invoke both hookshot and webhook deliveries client if hookshot client fetch delivery with 500 error and BlobNotFound message when webhook_deliveries_traffic is enabled" do
        GitHub.flipper[:webhook_deliveries_traffic].enable(Events::ParentAsActor.new(@parent))
        Hookshot::Client.any_instance.expects(:delivery_for_hook).with(@delivery_id, @hook_id, @options).returns([500, { "message" => "BlobNotFound" }])
        WebhookDeliveriesClient.any_instance.expects(:delivery_for_hook).once
        ui_client = HookDeliveriesClient.new(@parent)
        ui_client.delivery_for_hook(@delivery_id, @hook_id, @options)
      end
    end

    context "when events_v2_publish_tier1_event is enabled" do
      test "invoke only webhook-deliveries delivery if webhook-deliveries client fetch delivery successfully when webhook_deliveries_traffic is enabled" do
        GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.new(@parent))
        GitHub.flipper[:webhook_deliveries_traffic].enable(Events::ParentAsActor.new(@parent))
        WebhookDeliveriesClient.any_instance.expects(:delivery_for_hook).with(@delivery_id, @hook_id, @options).returns([200, {}])
        Hookshot::Client.any_instance.expects(:delivery_for_hook).never
        ui_client = HookDeliveriesClient.new(@parent)
        ui_client.delivery_for_hook(@delivery_id, @hook_id, @options)
      end

      test "invoke only webhook-deliveries client if webhook deliveries client fetch delivery with 500 error and BlobNotFound message when webhook_deliveries_traffic is disabled" do
        GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.new(@parent))
        Hookshot::Client.any_instance.expects(:delivery_for_hook).with(@delivery_id, @hook_id, @options).returns([500, { "message" => "BlobNotFound" }])
        WebhookDeliveriesClient.any_instance.expects(:delivery_for_hook).never
        ui_client = HookDeliveriesClient.new(@parent)
        ui_client.delivery_for_hook(@delivery_id, @hook_id, @options)
      end

      test "invoke both hookshot and webhook deliveries client if webhook deliveries client fetch delivery with 500 error and BlobNotFound message when webhook_deliveries_traffic is enbled" do
        GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.new(@parent))
        GitHub.flipper[:webhook_deliveries_traffic].enable(Events::ParentAsActor.new(@parent))
        WebhookDeliveriesClient.any_instance.expects(:delivery_for_hook).with(@delivery_id, @hook_id, @options).returns([500, { "message" => "BlobNotFound" }])
        Hookshot::Client.any_instance.expects(:delivery_for_hook).once
        ui_client = HookDeliveriesClient.new(@parent)
        ui_client.delivery_for_hook(@delivery_id, @hook_id, @options)
      end
    end
  end

  context "#deliveries_for_hook" do
    test "invoke hookshot client when events_v2_publish_tier1_event is disabled" do
      Hookshot::Client.any_instance.expects(:deliveries_for_hook).once
      WebhookDeliveriesClient.any_instance.expects(:deliveries_for_hook).never
      ui_client = HookDeliveriesClient.new(@parent)
      ui_client.deliveries_for_hook(1, nil)
    end

    test "invoke webhook deliveries client when webhook_deliveries_traffic and events_v2_publish_tier1_event are enbled" do
      GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.new(@parent))
      GitHub.flipper[:webhook_deliveries_traffic].enable(Events::ParentAsActor.new(@parent))
      Hookshot::Client.any_instance.expects(:deliveries_for_hook).never
      WebhookDeliveriesClient.any_instance.expects(:deliveries_for_hook).once
      ui_client = HookDeliveriesClient.new(@parent)
      ui_client.deliveries_for_hook(1, nil)
    end
  end

  context "#redeliver" do
    test "raise an error if invalid arguments are passed for v2 delivery" do
      client = HookDeliveriesClient.new(@parent)
      assert_raises_with_message(ArgumentError, "V2 redeliveries require a delivery_id") do
        client.redeliver(delivery_guid: @guid, hook: @hook, v2: true)
      end
    end

    test "raise an error if invalid arguments are passed for v1 delivery" do
      client = HookDeliveriesClient.new(@parent)
      assert_raises_with_message(ArgumentError, "V1 redeliveries require a delivery_guid") do
        client.redeliver(delivery_id: @delivery_id, hook: @hook)
      end
    end

    test "v2 redelivery calls WebhookDeliveriesClient" do
      GitHub.flipper[:webhook_deliveries_traffic].enable
      webhook_subscription = {
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
      WebhookDeliveriesClient.any_instance.
          expects(:redeliver).
          with(delivery_id: @delivery_id, webhook_subscription: webhook_subscription).
          once.
          returns([200, { message: "OK" }])

      client = HookDeliveriesClient.new(@parent)
      assert_equal true, client.redeliver(delivery_id: @delivery_id, hook: @hook, v2: true)
    end

    test "v2 redelivery returns error for non-200 responses" do
      GitHub.flipper[:webhook_deliveries_traffic].enable
      WebhookDeliveriesClient.any_instance.expects(:redeliver).once.returns([500, { message: "error" }])
      client = HookDeliveriesClient.new(@parent)
      assert_raises Hookshot::BadResponseError do
        client.redeliver(delivery_id: @delivery_id, hook: @hook, v2: true)
      end
    end

    test "v2 redelivery fails if webhook-deliveries traffic is disabled" do
      GitHub.flipper[:webhook_deliveries_traffic].disable
      client = HookDeliveriesClient.new(@parent)
      assert_raises_with_message(StandardError, "Cannot redeliver V2 delivery. webhook-deliveries traffic is disabled.") do
        client.redeliver(delivery_id: @delivery_id, hook: @hook, v2: true)
      end
    end

    test "v1 redelivery calls DeliverySystem" do
      Hook::DeliverySystem.expects(:redeliver).with(@guid, @hook).once.returns(true)
      client = HookDeliveriesClient.new(@parent)
      assert_equal true, client.redeliver(delivery_guid: @guid, hook: @hook)
    end
  end
end
