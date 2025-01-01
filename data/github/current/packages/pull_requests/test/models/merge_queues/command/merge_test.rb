# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class MergeCommandTest < GitHub::TestCase
    include HookIntegrationTestHelper

    fixtures do
      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      @repository = create(:repository, :has_merge_queue)
      enable_feature_flag(:merge_queue_prevent_duplicate_merges, @repository)
      @queue = @repository.default_merge_queue

      @pr = create(:pull_request, :with_mergeable_head,
        repository: @repository,
        user: @repository.owner
      )

      @queue_entry = create(:merge_queue_entry, queue: @queue, pull_request: @pr)

      example_repo_snapshot
    end

    setup do
      skip unless GitHub.merge_queues_enabled?
      example_repo_restore
    end

    test "invoking merge twice for github repos performs a noop" do
      enable_feature_flag(:merge_queue_noop_merge)
      @repository.stubs(:github_owned?).returns(true)

      entry = Entry.new({
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      })

      command = Command.new(@queue, @repository, [@queue_entry], [])

      create_ref_result = command.create_ref!(entry, base_sha: @pr.base_sha, method: IConfiguration::MergeMethod::Merge)

      fail "Expected a successful result, got #{create_ref_result.inspect}" unless create_ref_result.is_a?(ICommand::Result::CreateRefSuccess)

      @queue_entry.update(
        head_sha: create_ref_result.head_sha,
        head_ref: create_ref_result.head_ref,
        base_sha: create_ref_result.base_sha
      )

      entry.head_sha = create_ref_result.head_sha

      # Perform the first merge.
      first_result = command.merge!(entry, expected_base_sha: @pr.base_sha)

      fail "Expected a successful result, got #{first_result.inspect}" unless first_result.is_a?(MergeQueues::ICommand::Result::MergeSuccess)

      # Perform the same merge, but it noops.
      second_result = command.merge!(entry, expected_base_sha: @pr.base_sha)

      fail "Expected a successful result, got #{second_result.inspect}" unless second_result.is_a?(MergeQueues::ICommand::Result::MergeSuccess)

      assert_equal first_result.new_oid, second_result.new_oid
      assert_equal first_result.old_oid, second_result.old_oid
    end

    MergeQueue::ALLOWED_MERGE_METHODS.each do |merge_method|
      test "idempotent merging occurs while merging with #{merge_method}" do
        @queue.update!(merge_method:)

        entry = Entry.new({
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::Queued.new,
          created_at: Time.now,
          requested_checks: [],
        })

        command = Command.new(@queue, @repository, [@queue_entry], [])
        create_ref_result = command.create_ref!(entry, base_sha: @pr.base_sha, method: IConfiguration::MergeMethod.deserialize(merge_method))

        fail "Expected a successful result, got #{create_ref_result.inspect}" unless create_ref_result.is_a?(ICommand::Result::CreateRefSuccess)

        @queue_entry.update(
          head_sha: create_ref_result.head_sha,
          head_ref: create_ref_result.head_ref,
          base_sha: create_ref_result.base_sha
        )

        # Mimic the call to update by updating the entry's head sha
        entry.head_sha = create_ref_result.head_sha
        result = command.merge!(entry, expected_base_sha: @pr.base_sha)

        # Attempting to Merge the same entry again should result in an AlreadyMergedError.
        result = command.merge!(entry, expected_base_sha: create_ref_result.head_sha)
        assert_instance_of ICommand::Result::AlreadyMergedError, result
      end

      test "git failures while querying if the merge occurred already are retryable merging with #{merge_method}" do
        skip unless @repository.feature_enabled?(:merge_queue_prevent_duplicate_merges)

        @queue.update!(merge_method:)

        entry = Entry.new({
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::Queued.new,
          created_at: Time.now,
          requested_checks: [],
        })

        command = Command.new(@queue, @repository, [@queue_entry], [])
        create_ref_result = command.create_ref!(entry, base_sha: @pr.base_sha, method: IConfiguration::MergeMethod.deserialize(merge_method))

        fail "Expected a successful result, got #{create_ref_result.inspect}" unless create_ref_result.is_a?(ICommand::Result::CreateRefSuccess)

        @queue_entry.update(
          head_sha: create_ref_result.head_sha,
          head_ref: create_ref_result.head_ref,
          base_sha: create_ref_result.base_sha
        )

        # mimic the call to update by updating the entry's head sha
        entry.head_sha = create_ref_result.head_sha

        GitRPC::Client.any_instance.stubs(:descendant_of).raises(GitRPC::Timeout)

        result = T.cast(command.merge!(entry, expected_base_sha: @pr.base_sha), ICommand::Result::Error)

        assert_instance_of ICommand::Result::Error, result
        assert_equal "git_error", result.message
        assert result.permit_retry
      end
    end
  end
end
