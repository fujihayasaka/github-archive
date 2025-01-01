# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventCheckSuiteEventTest < GitHub::TestCase
  include HookEventTestHelper
  include HookIntegrationTestHelper
  include PushTestHelper

  fixtures do
    @github_app = create(:integration, default_permissions: { "checks" => :write }, url: "http://super-duper.com")
    @user  = create(:user)

    @repo = create :repository, owner: @user, name: "hello-world", from_example: :rebase_pull_request
    @installation = make_integration_installation(integration: @github_app, repository: @repo)

    # Use existing git repo `rebase_pull_request`
    # Which lives in test/fixtures/git/examples/rebase_pull_request.git

    # Make a new commit on contrib branch,
    # so that there is a diff to compare after a Push of that commit
    @before = @repo.heads.find("contrib").target_oid
    metadata = { message: "blah", committer: @user }
    commit = @repo.heads.find("contrib").append_commit(metadata, @user) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end
    @head_sha = commit.oid

    # Create a Push for the fresh commit(s) on the feature branch.
    perform_enqueued_jobs(only: [CreateCheckSuitesJob]) do
      trigger_push_event(
        @repo.shard_path,
        @user.login,
        [["refs/heads/contrib", @before, @head_sha]],
        Time.now,
        perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
      )

      @push = @repo.pushes.first
    end

    @check_suite = CheckSuite.where(push_id: @push.id).last

    @event_attrs = {
      action: "created",
      check_suite_id: T.must(@check_suite).id,
    }

    other_repository = create(:repository, owner: @user, created_by_user_id: @user)
    @check_suite_without_push = create(:check_suite, repository: other_repository, creator: @user)
  end

  test "required attributes" do
    assert_event_required_attributes(Hook::Event::CheckSuiteEvent, :check_suite_id, :action)
  end

  context "#check_suite" do
    test "is found using check_suite_id" do
      event = Hook::Event::CheckSuiteEvent.new(@event_attrs)
      assert_equal @check_suite, event.check_suite
    end

    test "test query counts" do
      query_counts = {
        check_suites: 1,
        pushes: 0,
      }

      assert_query_count_per_table(query_counts) do
        event = Hook::Event::CheckSuiteEvent.new(@event_attrs)
        assert_equal @check_suite, event.check_suite
      end
    end
  end

  context "#actor" do
    test "is looked up using the actor_id" do
      event = Hook::Event::CheckSuiteEvent.new action: :rerequested,
        check_suite_id: @check_suite.id,
        actor_id: @user.id

      assert_equal @user, event.actor
    end

    test "with no actor_id, defaults to the pusher" do
      event = Hook::Event::CheckSuiteEvent.new(action: :requested, check_suite_id: @check_suite.id)
      assert_equal @push.pusher, event.actor
    end

    test "with no actor_id or pusher, falls back to creator" do
      event = Hook::Event::CheckSuiteEvent.new(action: :requested, check_suite_id: @check_suite_without_push.id)
      assert_equal @check_suite_without_push.creator, event.actor
    end

    test "with no actor_id, creator, or pusher, falls back to Ghost user" do
      @check_suite_without_push.update!(creator: nil)
      event = Hook::Event::CheckSuiteEvent.new(action: :requested, check_suite_id: @check_suite_without_push.id)
      assert_equal User.ghost, event.actor
    end
  end

  context "#deliverable" do
    test "is deliverable if the repo exists and the commit exists" do
      event = Hook::Event::CheckSuiteEvent.new(@event_attrs)
      assert_equal true, event.deliverable?
    end

    test "is not deliverable if the repo has been deleted" do
      event = Hook::Event::CheckSuiteEvent.new(@event_attrs)
      @check_suite.repository.delete
      @check_suite.reload
      assert_equal false, event.deliverable?
    end

    test "is not deliverable if the repo exists but the commit does not exist" do
      event = Hook::Event::CheckSuiteEvent.new(@event_attrs)
      @check_suite.update(head_sha: "0000000000000000000000000000000000000000") # this commit sha doesn't exist
      assert_equal false, event.deliverable?
    end
  end

  context "does not send hook event when app is no longer installed" do
    test "#request" do
      @installation.uninstall(actor: @user)

      deliveries = subscribe_to_hook_delivery "check_suite"
      @check_suite.request

      assert_equal 0, deliveries.count
    end
    test "#rerequest" do
      @installation.uninstall(actor: @user)

      deliveries = subscribe_to_hook_delivery "check_suite"
      @check_suite.rerequest(actor: @user)


      assert_equal 0, deliveries.count
    end
  end

  context "does not send hook event when app installation is suspended" do
    test "#request" do
      @installation.suspend!

      deliveries = subscribe_to_hook_delivery "check_suite"
      @check_suite.request

      assert_equal 0, deliveries.count
    end

    test "#rerequest" do
      @installation.suspend!

      deliveries = subscribe_to_hook_delivery "check_suite"
      @check_suite.rerequest(actor: @user)

      assert_equal 0, deliveries.count
    end
  end

  context "#filterable_for_actions?" do
    test "filterable_for_actions? returns false when the repository does not exist" do
      event = Hook::Event::CheckSuiteEvent.new(@event_attrs)
      event.check_suite.repository = nil

      refute event.filterable_for_actions?
    end

    test "filterable_for_actions? returns false for rerequested check suites" do
      event = Hook::Event::CheckSuiteEvent.new({
        action: "rerequested",
        check_suite_id: @check_suite.id,
      })

      refute event.filterable_for_actions?
    end

    test "filterable_for_actions? returns true for valid check suites" do
      event = Hook::Event::CheckSuiteEvent.new(@event_attrs)

      assert event.filterable_for_actions?
    end
  end

  test "extra attributes should be deleted and not raise error" do
    GitHub.flipper[:prehydrate_primary_webhook_data_for_check_suite].enable
    extra_attributes = { super_fake_attribute: "bad data to break AR!" }
    primary_resource_data = @check_suite.attributes.merge(extra_attributes)
    event = Hook::Event::CheckSuiteEvent.new(action: "created", check_suite_id: @check_suite.id, primary_resource_data: primary_resource_data)
  end

end
