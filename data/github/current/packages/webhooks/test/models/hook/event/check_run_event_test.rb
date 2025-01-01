# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventCheckRunEventTest < GitHub::TestCase
  include HookEventTestHelper
  include HookIntegrationTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @github_app = create(:integration, :with_active_hook, default_permissions: { "checks" => :write }, url: "http://super-duper.com")
    @user = create(:user)

    @repo = create :repository, owner: @user, name: "hello-world"
    @installation = make_integration_installation(integration: @github_app, repository: @repo)

    @push = create(:push, repository: @repo)
    @check_suite = create(:check_suite, push_id: @push.id, repository: @repo, github_app: @github_app)
    @check_run = create(:check_run, check_suite: @check_suite)

    other_repository = create(:repository, owner: @user, created_by_user_id: @user)
    @check_suite_without_push = create(:check_suite, repository: other_repository, creator: @user)
    @check_run_without_push = create(:check_run, check_suite: @check_suite_without_push)

    @event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id)
  end

  test "required attributes" do
    assert_event_required_attributes(Hook::Event::CheckRunEvent, :check_run_id, :action)
  end

  context "#check_run" do
    test "is found using check_run_id" do
      assert_equal @check_run, @event.check_run
    end

    unless GitHub.enterprise?
      test "instruments mysql metrics" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id)

        mysql_metrics = GitHub.dogstats.distributions("hook.event.prehydration_check_run_event_queries", tags: ["cluster:application_record/repositories_actions_checks"])
        assert_equal 0, mysql_metrics.length

        assert_equal @check_run.id, event.check_run.id
        mysql_metrics = GitHub.dogstats.distributions("hook.event.prehydration_check_run_event_queries", tags: ["cluster:application_record/repositories_actions_checks"])
        assert_equal 1, mysql_metrics.length
      end

      test "does not instrument mysql metrics when primary resource present" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        ENV["P"] = "1"
        GitHub.flipper[:prehydrate_primary_webhook_data_for_check_run].disable
        event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id, primary_resource_data: @check_run.attributes)
        assert_equal @check_run.id, event.check_run.id
        mysql_metrics = GitHub.dogstats.distributions("hook.event.prehydration_check_run_event_queries", tags: ["cluster:application_record/repositories_actions_checks"])
        assert_equal 1, mysql_metrics.length
        assert_equal 1, mysql_metrics.first.value

        GitHub.dogstats.reset
        GitHub.flipper[:prehydrate_primary_webhook_data_for_check_run].enable
        event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id, primary_resource_data: @check_run.attributes)
        assert_equal @check_run.id, event.check_run.id
        mysql_metrics = GitHub.dogstats.distributions("hook.event.prehydration_check_run_event_queries", tags: ["cluster:application_record/repositories_actions_checks"])
        assert_equal 1, mysql_metrics.length
        assert_equal 0, mysql_metrics.first.value
      end
    end
  end

  context "#check_suite" do
    test "is the check_suite associated with the check run" do
      assert_equal @check_suite, @event.check_suite
    end
  end

  context "#actor" do
    test "is looked up using the actor_id" do
      event = Hook::Event::CheckRunEvent.new action: :rerequested,
        check_run_id: @check_run.id,
        actor_id: @user.id

      assert_equal @user, event.actor
    end

    test "with no actor_id, defaults to the pusher" do
      event = Hook::Event::CheckRunEvent.new(action: :requested, check_run_id: @check_run.id)
      assert_equal @push.pusher, event.actor
    end

    test "with no actor_id or pusher, falls back to creator" do
      event = Hook::Event::CheckRunEvent.new(action: :requested, check_run_id: @check_run_without_push.id)
      assert_equal @check_suite_without_push.creator, event.actor
    end

    test "with no actor_id, creator, or pusher, falls back to Ghost user" do
      @check_suite_without_push.update!(creator: nil)
      event = Hook::Event::CheckRunEvent.new(action: :requested, check_run_id: @check_run_without_push.id)
      assert_equal User.ghost, event.actor
    end
  end

  context "does not send hook event when app is no longer installed" do
    test "#rerequest" do
      @installation.uninstall(actor: @user)

      deliveries = subscribe_to_hook_delivery "check_run"
      @check_run.rerequest(actor: @user)


      assert_equal 0, deliveries.count
    end

    test "#request_action" do
      @installation.uninstall(actor: @user)

      deliveries = subscribe_to_hook_delivery "check_run"
      @check_run.request_action(actor: @user, requested_action: { identifier: "fix_me" })


      assert_equal 0, deliveries.count
    end
  end

  context "does not send hook event when app installation is suspended" do
    test "#rerequest" do
      @installation.suspend!

      deliveries = subscribe_to_hook_delivery "check_run"
      @check_run.rerequest(actor: @user)


      assert_equal 0, deliveries.count
    end

    test "#request_action" do
      @installation.suspend!

      deliveries = subscribe_to_hook_delivery "check_run"
      @check_run.request_action(actor: @user, requested_action: { identifier: "fix_me" })

      assert_equal 0, deliveries.count
    end
  end

  context "#initialize_primary_resource" do
    test "sets primary_resource_data when available" do
      GitHub.flipper[:prehydrate_primary_webhook_data_for_check_run].enable
      event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id)

      assert_nil event.instance_variable_get(:@check_run)

      event.primary_resource_data = @check_run.as_json(root: false, dangerously_allow_all_keys: true)
      event.initialize_primary_resource

      assert_equal @check_run, event.instance_variable_get(:@check_run)
    end

    test "does not set primary_resource_data when not available" do
      GitHub.flipper[:prehydrate_primary_webhook_data_for_check_run].enable
      event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id)
      assert_nil event.instance_variable_get(:@check_run)
      event.initialize_primary_resource
      assert_nil event.instance_variable_get(:@check_run)
    end
  end

  test "extra attributes should be deleted and not raise error" do
    GitHub.flipper[:prehydrate_primary_webhook_data_for_check_run].enable
    extra_attributes = { super_fake_attribute: "bad data to break AR!" }
    primary_resource_data = @check_run.attributes.merge(extra_attributes)
    event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id, primary_resource_data: primary_resource_data)
  end


  test "target_repository resturns nil when check_suite is nil" do
    check_suite = create(:check_suite, push_id: @push.id, repository: @repo)
    check_run = create(:check_run, check_suite: check_suite)
    check_suite.destroy
    check_run.reload
    event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: check_run.id)
    # assert target_repository can be nil and do not raise exceptions
    assert_nil event.check_suite
    assert_nil event.target_repository
  end

  context "#app_installation_ids" do
    test "returns the installation ids for the app" do
      event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id)
      assert_includes event.app_installation_ids, @installation.id
    end

    test "does not include suspended installations" do
      event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id)
      @installation.suspend!
      refute_includes event.app_installation_ids, @installation.id
    end

    test "returns empty when the app is suspended" do
      event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id)
      app = event.app
      app.suspend(actor: create(:staff_admin_user), reason: "test")
      app.reload

      assert_equal [], event.app_installation_ids
    end
  end

  context "#subscribed_hooks" do
    test "returns the hooks that are subscribed to the event", feature_disabled: :checks_request_hook_when_permissions_and_subscription do
      event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id, specific_app_only: true)

      assert_equal [@github_app.hook], event.subscribed_hooks
    end

    test "returns no hooks when app is not subscribed", feature_enabled: :checks_request_hook_when_permissions_and_subscription do
      event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id, specific_app_only: true)

      assert_equal [], event.subscribed_hooks
    end

    test "returns no hooks if the app is suspended" do
      event = Hook::Event::CheckRunEvent.new(action: "created", check_run_id: @check_run.id, specific_app_only: true)
      app = event.app
      app.suspend(actor: create(:staff_admin_user), reason: "test")
      app.reload

      assert_equal [], event.subscribed_hooks
    end
  end
end
