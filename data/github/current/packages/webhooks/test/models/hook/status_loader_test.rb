# typed: true
# frozen_string_literal: true

require "test_helper"

class HookStatusLoaderTest < GitHub::TestCase

  fixtures do
    @hook = create(:hook, :web)
    disable_feature_flag(:events_v2_publish_tier1_event)
    disable_feature_flag(:events_v2_use_staffship_ui_flags)
    disable_feature_flag(:events_v2_owner_enabled)
    disable_feature_flag(:webhook_deliveries_traffic)
  end

  setup do
    @parent = @hook.installation_target
    @parent_actor_id = "#{@parent.class.name.underscore}-#{@parent.id}"
  end

  test "an empty list of hooks will return an empty array" do
    assert_equal [], Hook::StatusLoader.load_statuses(hook_records: [])
  end

  context "hookshot_statuses" do
    test "initializes ui client" do
      hookshot_client = mock("Hook::UIClient")
      hookshot_client.expects(:statuses_for_hooks).returns([nil, nil])
      Hookshot::Client.expects(:ui_client_for_parent).returns(hookshot_client)
      Hook::StatusLoader.new(hook_records: [@hook]).hookshot_statuses
    end

    # TODO: remove this test when removing events_v2_use_staffship_ui_flags, see https://github.com/github/ecosystem-events/issues/4876
    test "initializes webhook_deliveries client" do
      enable_feature_flag(:events_v2_publish_tier1_event, Events::ParentAsActor.new(@parent_actor_id))
      enable_feature_flag(:webhook_deliveries_traffic, Events::ParentAsActor.new(@parent_actor_id))
      webhook_deliveries_client = mock("WebhookDeliveriesClient")
      webhook_deliveries_client.expects(:statuses_for_hooks).returns([200, "success"])
      WebhookDeliveriesClient.expects(:new).returns(webhook_deliveries_client)
      Hook::StatusLoader.new(hook_records: [@hook]).hookshot_statuses
    end

    test "initializes webhook_deliveries client when events_v2_use_staffship_ui_flags is enabled" do
      enable_feature_flag(:events_v2_owner_enabled, Events::ParentAsActor.new(@parent_actor_id))
      enable_feature_flag(:events_v2_use_staffship_ui_flags)
      enable_feature_flag(:webhook_deliveries_traffic, Events::ParentAsActor.new(@parent_actor_id))
      webhook_deliveries_client = mock("WebhookDeliveriesClient")
      webhook_deliveries_client.expects(:statuses_for_hooks).returns([200, "success"])
      WebhookDeliveriesClient.expects(:new).returns(webhook_deliveries_client)
      Hook::StatusLoader.new(hook_records: [@hook]).hookshot_statuses
    end
  end

  context "hookshot" do
    test "returns the given hooks without statuses populated when Hookshot returns an error" do
      Hookshot::Client.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([500, {}])
      assert_equal [@hook], Hook::StatusLoader.load_statuses(hook_records: [@hook], parent: @parent)
    end

    test "populates the status from Hookshot for given hook records" do
      assert_nil @hook.last_status
      assert_nil @hook.last_status_message

      Hookshot::Client.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([200, { @hook.id.to_s => { "status" => 200, "response" => "OK" } }])
      hooks = Hook::StatusLoader.load_statuses(hook_records: [@hook], parent: @parent)
      assert_equal(1, hooks.length)
      hook = hooks.first
      assert_equal 200, hook.last_status
      assert_equal "OK", hook.last_status_message
    end

    test "returns a single record when given a single record" do
      assert_nil @hook.last_status
      assert_nil @hook.last_status_message

      Hookshot::Client.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([200, { @hook.id.to_s => { "status" => 200, "response" => "OK" } }])
      hook = Hook::StatusLoader.load_status(@hook)
      assert_equal @hook, hook
      assert_equal 200, hook.last_status
      assert_equal "OK", hook.last_status_message
    end
  end

  context "webhook_deliveries" do
    # TODO: remove this test when removing events_v2_use_staffship_ui_flags, see https://github.com/github/ecosystem-events/issues/4876
    test "returns the given hooks without statuses populated when WebhookDeliveries returns an error" do
      enable_feature_flag(:events_v2_publish_tier1_event, Events::ParentAsActor.new(@parent_actor_id))
      enable_feature_flag(:webhook_deliveries_traffic, Events::ParentAsActor.new(@parent_actor_id))
      WebhookDeliveriesClient.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([500, {}])
      assert_equal [@hook], Hook::StatusLoader.load_statuses(hook_records: [@hook], parent: @parent)
    end

    test "returns the given hooks without statuses populated when WebhookDeliveries returns an error and events_v2_use_staffship_ui_flags is enabled" do
      enable_feature_flag(:events_v2_use_staffship_ui_flags)
      enable_feature_flag(:events_v2_owner_enabled, Events::ParentAsActor.new(@parent_actor_id))
      enable_feature_flag(:webhook_deliveries_traffic, Events::ParentAsActor.new(@parent_actor_id))
      WebhookDeliveriesClient.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([500, {}])
      assert_equal [@hook], Hook::StatusLoader.load_statuses(hook_records: [@hook], parent: @parent)
    end

    # TODO: remove this test when removing events_v2_publish_tier1_event, see https://github.com/github/ecosystem-events/issues/4876
    test "populates the status from Hookshot for given hook records" do
      enable_feature_flag(:events_v2_publish_tier1_event, Events::ParentAsActor.new(@parent_actor_id))
      enable_feature_flag(:webhook_deliveries_traffic, Events::ParentAsActor.new(@parent_actor_id))

      assert_nil @hook.last_status
      assert_nil @hook.last_status_message

      WebhookDeliveriesClient.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([200, { @hook.id.to_s => { "status" => 200, "response" => "OK" } }])

      hooks = Hook::StatusLoader.load_statuses(hook_records: [@hook], parent: @parent)
      assert_equal(1, hooks.length)
      hook = hooks.first
      assert_equal 200, hook.last_status
      assert_equal "OK", hook.last_status_message
    end

    test "populates the status from Hookshot for given hook records when events_v2_use_staffship_ui_flags is enabled" do
      enable_feature_flag(:events_v2_use_staffship_ui_flags)
      enable_feature_flag(:events_v2_owner_enabled, Events::ParentAsActor.new(@parent_actor_id))
      enable_feature_flag(:webhook_deliveries_traffic, Events::ParentAsActor.new(@parent_actor_id))

      assert_nil @hook.last_status
      assert_nil @hook.last_status_message

      WebhookDeliveriesClient.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([200, { @hook.id.to_s => { "status" => 200, "response" => "OK" } }])

      hooks = Hook::StatusLoader.load_statuses(hook_records: [@hook], parent: @parent)
      assert_equal(1, hooks.length)
      hook = hooks.first
      assert_equal 200, hook.last_status
      assert_equal "OK", hook.last_status_message
    end

    # TODO: remove this test when removing events_v2_use_staffship_ui_flags, see https://github.com/github/ecosystem-events/issues/4876
    test "returns a single record when given a single record" do
      enable_feature_flag(:events_v2_publish_tier1_event, Events::ParentAsActor.new(@parent_actor_id))
      enable_feature_flag(:webhook_deliveries_traffic, Events::ParentAsActor.new(@parent_actor_id))

      assert_nil @hook.last_status
      assert_nil @hook.last_status_message

      WebhookDeliveriesClient.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([200, { @hook.id.to_s => { "status" => 200, "response" => "OK" } }])

      hook = Hook::StatusLoader.load_status(@hook)
      assert_equal @hook, hook
      assert_equal 200, hook.last_status
      assert_equal "OK", hook.last_status_message
    end

    test "returns a single record when given a single record  events_v2_use_staffship_ui_flags is enabled" do
      enable_feature_flag(:events_v2_use_staffship_ui_flags)
      enable_feature_flag(:events_v2_owner_enabled, Events::ParentAsActor.new(@parent_actor_id))
      enable_feature_flag(:webhook_deliveries_traffic, Events::ParentAsActor.new(@parent_actor_id))

      assert_nil @hook.last_status
      assert_nil @hook.last_status_message

      WebhookDeliveriesClient.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([200, { @hook.id.to_s => { "status" => 200, "response" => "OK" } }])

      hook = Hook::StatusLoader.load_status(@hook)
      assert_equal @hook, hook
      assert_equal 200, hook.last_status
      assert_equal "OK", hook.last_status_message
    end
  end
end
