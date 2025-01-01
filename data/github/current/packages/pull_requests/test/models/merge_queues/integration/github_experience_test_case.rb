# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "integration_test_case"

module MergeQueues
  class GithubExperienceTest < IntegrationTestCase
    fixtures do
      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      @org = Organization.find_by!(login: "github")
      @repo = create(:repository, :has_merge_queue, owner: @org)
      @user = create(:user)
      @repo.add_member @user, action: :write
      @org.add_member @user, action: :write

      enable_feature_flag(:merge_queue, @repo)
      enable_feature_flag(:merge_queue_deploy_then_merge, @repo)
      enable_feature_flag(:merge_queue_uses_queue_refs, @repo)

      create :hook, :web, installation_target: @repo, events: %w(merge_group pull_request)

      @queue = @repo.default_merge_queue
      @queue.update(merging_strategy: IConfiguration::GroupingStrategy::HeadGreen.serialize)

      example_repo_snapshot
    end

    test "a PR is added to the queue, turns green, is locked, and then merged via API" do
      pulls_and_entries = [
        enqueue_pull_request!(ref_name: "cr-line-endings"),
        enqueue_pull_request!,
        enqueue_pull_request!,
      ]

      invoke_merge_queue_job!

      pulls_and_entries.each do |_, entry|
        assert_entry_hook_delivered(entry, "checks_requested")
        simulate_check(entry, :success)
      end

      invoke_merge_queue_job!

      # We do not attempt to automatically merge, we wait for API calls.
      assert_queue_size 3

      simulate_graphql_lock!

      pulls_and_entries.each do |_, entry|
        assert entry.locked?
      end

      simulate_graphql_merge!

      pulls_and_entries.each do |pull, _|
        assert pull.merged?
        assert_pull_request_hook_delivered(pull, "dequeued")

        # TODO: This is a bug!
        # assert_entry_hook_delivered(entry, "destroyed")
      end
    end

    test "a PR is added to the queue, turns green, is locked, and then cleared via API" do
      pulls_and_entries = [
        enqueue_pull_request!(ref_name: "cr-line-endings"),
        enqueue_pull_request!,
        enqueue_pull_request!,
      ]

      invoke_merge_queue_job!

      pulls_and_entries.each do |_, entry|
        simulate_check(entry, :success)
      end

      invoke_merge_queue_job!

      simulate_graphql_lock!

      assert pulls_and_entries.all? { |_, entry| entry.locked? }

      simulate_graphql_clear!

      assert_queue_size 0

      pulls_and_entries.each do |pull, entry|
        assert entry.destroyed?
        refute pull.merged?
        assert_pull_request_hook_delivered(pull, "dequeued")

        # TODO: This is a bug!
        # assert_entry_hook_delivered(entry, "destroyed")
      end
    end

    test "a PR is added to the queue, turns green, is locked, and then unlocked via API" do
      pulls_and_entries = [
        enqueue_pull_request!(ref_name: "cr-line-endings"),
        enqueue_pull_request!,
        enqueue_pull_request!,
      ]

      invoke_merge_queue_job!

      pulls_and_entries.each do |_, entry|
        simulate_check(entry, :success)
      end

      invoke_merge_queue_job!
      simulate_graphql_lock!
      simulate_graphql_unlock!

      assert_queue_size 3

      pulls_and_entries.each do |pull, entry|
        refute pull.merged?
        refute entry.destroyed?
        refute entry.locked?
      end
    end

    private

    sig { void }
    def simulate_graphql_merge!
      execute_service do
        MergeQueues.merge_locked_entry!(repository: @repo, branch: @queue.branch, actor: @user)
      end
    end

    sig { void }
    def simulate_graphql_lock!
      execute_service do
        MergeQueues.lock_best_entry!(repository: @repo, branch: @queue.branch, actor: @user)
      end
    end

    sig { void }
    def simulate_graphql_clear!
      execute_service do
        MergeQueues.clear!(repository: @repo, branch: @queue.branch, actor: @user)
      end
    end

    sig { void }
    def simulate_graphql_unlock!
      execute_service do
        MergeQueues.unlock!(repository: @repo, branch: @queue.branch, actor: @user, merge_queue: @queue)
      end
    end

    def execute_service(&block)
      perform_enqueued_merge_queue_jobs(&block)
      reload_cache!
    end
  end
end
