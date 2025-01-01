# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "integration_test_case"

module MergeQueues
  class MultipleQueuesTest < IntegrationTestCase
    include DogstatsTestHelpers

    fixtures do
      Spokesd.enable_spokesd

      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      @org = create(:organization, plan: "business_plus")
      @repo = create(:public_repository, :has_merge_queue, owner: @org)
      @user = create(:user)
      @repo.add_member @user, action: :write
      @org.add_member @user, action: :write
      disable_feature_flag(:merge_queue_uses_queue_refs, @repo)

      @queue = @repo.default_merge_queue

      # Create a mirrored main branch.
      @repo.refs.create("refs/heads/main-2", @repo.ref_to_sha("refs/heads/#{@queue.branch}"), @user)

      @queue_2 = create(:merge_queue, repository: @repo, branch: "main-2")

      @queue_2.protected_branch.tap do |pb|
        # The merge queue bot is an internal actor within our system. Set the branch protection rules
        # to only allow the repo user so we can validate the branch protection does not fail utilizing
        # the bot push actor.
        pb.replace_authorized_actors(user_ids: [@user.id], team_ids: [], integration_ids: [])
        pb.required_status_checks.create! context: "required-run"
        pb.required_status_checks_enforcement_level = :everyone
      end.save!

      create :hook, :web, installation_target: @repo, events: %w(merge_group pull_request)

      example_repo_snapshot
    end

    test "pull requests targeting each queue are allowed to enqueue" do
      pull_1, entry_1 = enqueue_pull_request!(queue: @queue)
      pull_2, entry_2 = enqueue_pull_request!(queue: @queue_2, ref_name: pull_1.head_ref)

      invoke_merge_queue_job!(queue: @queue)
      invoke_merge_queue_job!(queue: @queue_2)

      assert_entry_hook_delivered(entry_1, "checks_requested")
      assert_entry_hook_delivered(entry_2, "checks_requested")

      simulate_check(entry_1, :success)
      simulate_check(entry_2, :success)

      # It should not queue a job in the future because everything settled.
      MergeQueues.expects(:delayed_execute!).never

      invoke_merge_queue_job!(queue: @queue)
      invoke_merge_queue_job!(queue: @queue_2)

      assert_queue_size(0, queue: @queue)
      assert_queue_size(0, queue: @queue_2)

      assert pull_1.merged?
      assert_pull_request_hook_delivered(pull_1, "dequeued")

      assert pull_2.merged?
      assert_pull_request_hook_delivered(pull_2, "dequeued")
    end
  end
end
