# typed: true
# frozen_string_literal: true

require "test_helper"

class HookStatusLoaderTest < GitHub::TestCase

  fixtures do
    @hook = create(:hook, :web)
    @parent = @hook.installation_target
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
  end

  context "hookshot" do
    test "returns the given hooks without statuses populated when Hookshot returns an error" do
      Hookshot::Client.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([500, {}])
      assert_equal [@hook], Hook::StatusLoader.load_statuses(hook_records: [@hook], parent: @parent)
    end

    test "populates the status from Hookshot for given hook records" do
      Hookshot::Client.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([200, { @hook.id.to_s => { "status" => 200, "response" => "OK" } }])
      hooks = Hook::StatusLoader.load_statuses(hook_records: [@hook], parent: @parent)
      assert hook = hooks.pop
      refute hooks.pop
      assert_equal 200,  hook.last_status
      assert_equal "OK", hook.last_status_message
    end

    test "returns a single record when given a single record" do
      Hookshot::Client.any_instance.stubs(:statuses_for_hooks).
        with([@hook.id]).
        returns([200, { @hook.id.to_s => { "status" => 200, "response" => "OK" } }])
      assert_equal @hook, Hook::StatusLoader.load_status(@hook)
      assert_equal 200,  @hook.last_status
      assert_equal "OK", @hook.last_status_message
    end
  end
end
