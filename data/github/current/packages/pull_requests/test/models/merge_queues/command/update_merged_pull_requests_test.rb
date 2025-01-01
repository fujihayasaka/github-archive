# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class UpdatedMergedPullReqestsCommandTest < GitHub::TestCase
    include HydroTestHelpers
    include PullRequestSynchronizationTestHelpers

    if GitHub.merge_queues_enabled?
      fixtures do
        GitHub.flipper[:merge_queue].enable

        make_trusted_oauth_apps_owner
        create(:merge_queue_integration)

        @repository = create(:repository, :has_merge_queue)
        @queue = @repository.default_merge_queue
        @queue_entry = create(:merge_queue_entry, queue: @queue)
        @queue_entry_stat = create(:merge_queue_entry_stat, queue: @queue, entry: @queue_entry)
        @pr = @queue_entry.pull_request

        @bot = make_integration_installation(repository: @repository, permissions: { "contents" => :write }).bot
        @bot_queue_entry = create(:merge_queue_entry, queue: @queue, enqueuer: @bot, head_ref_name: "other_pr")
        @bot_queue_entry_stat = create(:merge_queue_entry_stat, queue: @queue, entry: @bot_queue_entry)
        @bot_pr = @bot_queue_entry.pull_request

        example_repo_snapshot
      end

      setup do
        example_repo_restore

        @entry = Entry.new({
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          base_sha: @pr.base_sha,
          state: Entry::State::Queued.new,
          created_at: Time.now,
          requested_checks: [],
        })

        @bot_entry = Entry.new({
          merge_queue_entry_id: @bot_queue_entry.id,
          pull_request_number: @bot_pr.number,
          pull_request_id: @bot_pr.id,
          base_sha: @bot_pr.base_sha,
          state: Entry::State::Queued.new,
          created_at: Time.now,
          requested_checks: [],
        })

        @command = Command.new(@queue, @repository, [@queue_entry, @bot_queue_entry], [])

        [@entry, @bot_entry].each do |entry|
          create_ref_result = @command.create_ref!(entry, base_sha: T.must(entry.base_sha), method: @queue.merge_method_type)
          fail "Expected a successful result, got #{create_ref_result.inspect}" unless create_ref_result.is_a?(ICommand::Result::CreateRefSuccess)
          entry.head_sha = create_ref_result.head_sha
          entry.head_ref = create_ref_result.head_ref
          entry.base_sha = create_ref_result.base_sha
        end

        update_result = @command.update!([@entry, @bot_entry])

        fail "Expected a successful update, got #{update_result.inspect}" unless update_result.is_a?(ICommand::Result::Success)

        [@entry, @bot_entry].each do |entry|
          # mimic succesful check run after build requests a check
          create(:check_run, :success,
            check_suite: create(:check_suite, repository: @repository, head_sha: entry.head_sha),
            display_name: "required-run",
          )
        end

        # mimic the call to update by updating the entry's head sha
        @merge_result = @command.merge!(@bot_entry, expected_base_sha: @pr.base_sha)

        fail "Expected a successful merge, got #{@merge_result.inspect}" unless @merge_result.is_a?(ICommand::Result::MergeSuccess)

        # Clear the job queue so we can verify the correct Push jobs were enqueued.
        queue_adapter.enqueued_jobs.clear
      end

      test "success" do
        GitHub.flipper[:load_installation_for_merge_queue_post_merge_job].enable

        reset_hydro
        @repository.allow_auto_deleting_branches(actor: @repository.owner)

        result = perform_enqueued_jobs(only: [MergeQueuePostMergeJob]) do
          @command.update_merged_pull_requests!([@entry, @bot_entry], merge_result: @merge_result, merge_method: IConfiguration::MergeMethod::Merge)
        end

        with_hydro_publisher(GitHub.sync_hydro_publisher) { assert_hydro_messages(count: 3, schema: "github.repositories.v1.Pushed") }
        assert_instance_of(ICommand::Result::Success, result)
        assert @pr.reload.merged?, "PullRequest#post_merge should have transitioned the PR to merged"
        assert_nil @repository.reload.refs.find(@pr.head_ref), "the pull request head ref should be deleted"

        assert @bot_pr.reload.merged?, "PullRequest#post_merge should have transitioned the PR to merged"
        assert_nil @repository.reload.refs.find(@bot_pr.head_ref), "the pull request head ref should be deleted"
      end

      test "does not enqueue PR sync jobs for merged PRs" do
        Spokesd.enable_spokesd

        reset_hydro
        @repository.allow_auto_deleting_branches(actor: @repository.owner)

        result = with_enqueued_pr_sync_jobs do
          @command.update_merged_pull_requests!([@entry], merge_result: @merge_result, merge_method: IConfiguration::MergeMethod::Merge)
        end

        assert_instance_of(ICommand::Result::Success, result)
        refute @pr.reload.merged?, "pull request sync should not have transitioned the PR to merged"
      end
    end
  end
end
