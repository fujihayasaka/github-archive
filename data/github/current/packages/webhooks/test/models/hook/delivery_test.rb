# typed: true
# frozen_string_literal: true

require "test_helper"

class HookDeliveryTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @org = create :organization, admin: @user, plan: "bronze", login: "stark-industries"

    @repo = create :repository, owner: @org
    @hook = create :hook, :org,
      installation_target: @org,
      config: { "url" => "http://example.com" },
      events: %w(public),
      oauth_application: @untrusted_oauth_app
    @repo_hook = create :hook, :web,
      installation_target: @repo,
      config: { "url" => "http://example.com" },
      events: %w(public),
      oauth_application: @untrusted_oauth_app

    @triggered_at = 10.minutes.ago
    @hook_event = Hook::Event::PublicEvent.new repo_id: @repo, triggered_at: @triggered_at, actor_id: @user.id
    @delivery = Hook::Delivery.new(@hook_event, @hook.hookshot_parent_id, [@hook])
  end

  context "#guid" do
    test "is based on when the hook_event was triggered" do
      assert_equal @triggered_at.to_i, SimpleUUID::UUID.new(@delivery.guid).to_time.to_i
    end

    test "is cached since every guid is unique" do
      assert_equal @delivery.guid, @delivery.guid
    end
  end

  context "#payload" do
    test "builds the payload using the specified version" do
      @hook_event.expects(:to_payload_hash)
      @delivery.payload
    end
  end

  context "#payload_size" do
    test "calls payload only once" do
      hook_event = Hook::Event::PublicEvent.new repo_id: @repo, triggered_at: @triggered_at, actor_id: @user.id
      delivery = Hook::Delivery.new(hook_event, @hook.hookshot_parent_id, [@hook])
      hook_event.expects(:to_payload_hash).once
      delivery.payload_size
      delivery.payload_size
    end

    test "returns payload size" do
      hook_event = Hook::Event::PublicEvent.new repo_id: @repo, triggered_at: @triggered_at, actor_id: @user.id
      delivery = Hook::Delivery.new(hook_event, @hook.hookshot_parent_id, [@hook])
      hook_event.expects(:to_payload_hash).once.returns("{}")
      payload_size = delivery.payload_size
      assert_equal 4, payload_size
    end
  end

  context "#hooks and #muted_hooks" do
    test "are split out based on the Oauth Application Policy" do
      accepted_policy = stub("AcceptedOAP", satisfied?: true)
      rejected_policy = stub("RejectedOAP", satisfied?: false)
      OauthApplicationPolicy::Hook.expects(:new).with(@hook, @hook_event).returns(accepted_policy)
      OauthApplicationPolicy::Hook.expects(:new).with(@repo_hook, @hook_event).returns(rejected_policy)

      delivery = Hook::Delivery.new(@hook_event, @hook.hookshot_parent_id, [@hook, @repo_hook])
      assert_equal [@hook], delivery.hooks
      assert_equal [@repo_hook], delivery.muted_hooks
    end
  end
end
