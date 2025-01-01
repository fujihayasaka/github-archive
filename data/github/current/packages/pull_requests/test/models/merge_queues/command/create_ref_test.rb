# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class CreateRefCommandTest < GitHub::TestCase
    include HookIntegrationTestHelper

    fixtures do
      enable_feature_flag(:merge_queue)

      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      @repository = create(:repository, :has_merge_queue)
      @queue = @repository.default_merge_queue
      @queue_entry = create(:merge_queue_entry, queue: @queue)
      @queue_entry_stat = create(:merge_queue_entry_stat, queue: @queue, entry: @queue_entry)
      @pr = @queue_entry.pull_request

      example_repo_snapshot
    end

    setup do
      Spokesd.enable_spokesd

      example_repo_restore
    end

    test "it returns an error if it can't find the MergeQueueEntry" do
      command = Command.new(@queue, @repository, [], [])
      invalid_id = T.must(T.must(MergeQueueEntry.last).id) + 1
      entry = Entry.new(
        merge_queue_entry_id: invalid_id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      )

      result = T.cast(command.create_ref!(entry, base_sha: "deadbeef", method: @queue.merge_method_type), ICommand::Result::Error)

      assert_instance_of(ICommand::Result::Error, result)

      assert_equal "not_found", result.message
    end

    test "it successfuly builds a queue ref for a valid entry" do
      entry = Entry.new({
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      })

      command = Command.new(@queue, @repository, [@queue_entry], [])

      result = T.cast(
        command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type),
        ICommand::Result::CreateRefSuccess
      )

      assert_instance_of(ICommand::Result::CreateRefSuccess, result)

      assert result.base_sha.present?
      assert result.head_sha.present?
      assert result.head_ref.present?
    end

    test "it handles merge conflicts" do
      commit_data = { message: "Add a conflict", committer: @repository.owner }

      @repository.heads.find(@pr.base_ref).append_commit(commit_data, @repository.owner) do |files|
        files.add("bar.txt", "this conflicts with the pull request")
      end

      entry = Entry.new({
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      })

      command = Command.new(@queue, @repository, [@queue_entry], [])

      result = command.create_ref!(entry, base_sha: @queue.branch_head_oid, method: @queue.merge_method_type)

      assert_instance_of(ICommand::Result::MergeConflictError, result)
    end

    test "it handles repeated calls with the same head OID" do
      entry = Entry.new(
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      )

      command = Command.new(@queue, @repository, [@queue_entry], [])

      first_result = command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type)
      assert_instance_of(ICommand::Result::CreateRefSuccess, first_result)

      second_result = command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type)
      assert_instance_of(ICommand::Result::CreateRefSuccess, second_result)
    end

    # TODO: With the freezing of the `enqueued_head_sha`, is this test still necessary?
    test "it handles repeated calls with different head OIDs diff_same" do
      entry = Entry.new(
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      )

      command = Command.new(@queue, @repository, [@queue_entry], [])

      first_result = command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type)
      assert_instance_of(ICommand::Result::CreateRefSuccess, first_result)

      new_commit = @repository.create_commit(
        @pr.head_sha,
        message: "A new commit",
        author: @repository.owner,
        files: {
          "merge-queue-test.txt" => "Wow! Such commit!",
        },
      )

      @pr.update!(head_sha: new_commit.oid)
      @pr.reload.create_merge_commit

      @queue_entry.update(enqueued_head_sha: new_commit.oid)
      @queue_entry.reload
      @queue.reload

      second_result = command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type)
      assert_instance_of(ICommand::Result::CreateRefSuccess, second_result)
    end

    test "it handles PRs that have already been merged" do
      entry = Entry.new(
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      )

      command = Command.new(@queue, @repository, [@queue_entry], [])

      result = command.create_ref!(entry, base_sha: @pr.head_sha, method: @queue.merge_method_type)
      assert_instance_of(ICommand::Result::AlreadyMergedError, result)
    end

    test "it handles timeouts from rebasing" do
      @queue.update(merge_method: "rebase")

      entry = Entry.new({
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      })

      # Simulate the timeout.
      exception = GitRPC::Backend::RebaseTimeout.new("Rebase timed out")
      GitRPC::Client.any_instance.expects(
        GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository) ? :rebase_tmp_objdir_experiment : :rebase
      ).raises(exception)

      command = Command.new(@queue, @repository, [@queue_entry], [])

      result = T.cast(
        command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type),
        ICommand::Result::Error
      )

      assert_instance_of(ICommand::Result::Error, result)
      assert_equal "rebase_timeout", result.message
      assert result.permit_retry
      assert_equal exception, result.exception
    end

    test "it handles a merge conflict from rebasing" do
      @queue.update(merge_method: "rebase")

      entry = Entry.new({
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      })

      # Simulate the timeout.
      if GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository)
        GitRPC::Client.any_instance.expects(:rebase_tmp_objdir_experiment).returns(
          [nil, [["rebase.dogstats.mock", 1, { tags: ["status:failure"] }]]]
        )
      else
        GitRPC::Client.any_instance.expects(:rebase).returns(nil)
      end

      command = Command.new(@queue, @repository, [@queue_entry], [])

      result = T.cast(
        command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type),
        ICommand::Result::RebaseConflictError
      )

      assert_instance_of(ICommand::Result::RebaseConflictError, result)
    end

    test "it handles branch protection errors on ref creation" do
      entry = Entry.new({
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      })

      error = Git::Ref::ProtectedBranchUpdateError.new(nil, nil, "branch is protected from pushing")

      MergeQueues::Ref.any_instance.expects(:create).raises(error).once

      command = Command.new(@queue, @repository, [@queue_entry], [])

      result = T.cast(
        command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type),
        ICommand::Result::BranchProtectionError
      )

      assert_equal "branch is protected from pushing", result.message
    end

    test "it handles branch rule errors on ref creation" do
      entry = Entry.new({
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      })

      error = Git::Ref::RepositoryRuleViolationError.new(RuleEngine::RuleSuite.new)

      MergeQueues::Ref.any_instance.expects(:create).raises(error).once

      command = Command.new(@queue, @repository, [@queue_entry], [])

      result = T.cast(
        command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type),
        ICommand::Result::BranchProtectionError
      )

      assert_equal "Repository rule violations found", result.message
    end

    test "it handles branch protection errors in ref removal" do
      entry = Entry.new({
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      })

      Git::Ref.any_instance.expects(:delete).raises(
        Git::Ref::ProtectedBranchUpdateError.new(nil, nil, "branch is protected from deleting")
      )

      command = Command.new(@queue, @repository, [@queue_entry], [])

      assert_instance_of(
        ICommand::Result::CreateRefSuccess,
        command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type)
      )

      # TODO: Should the service call this in an uncacheable way?
      @queue.repository.reset_refs

      result = T.cast(
        command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type),
        ICommand::Result::BranchProtectionError
      )

      assert_equal "branch is protected from deleting", result.message
    end

    test "it handles branch rule errors in ref removal" do
      entry = Entry.new({
        merge_queue_entry_id: @queue_entry.id,
        pull_request_number: @pr.number,
        pull_request_id: @pr.id,
        state: Entry::State::Queued.new,
        created_at: Time.now,
        requested_checks: [],
      })

      Git::Ref.any_instance.expects(:delete).raises(
        Git::Ref::RepositoryRuleViolationError.new(RuleEngine::RuleSuite.new)
      )

      command = Command.new(@queue, @repository, [@queue_entry], [])

      assert_instance_of(
        ICommand::Result::CreateRefSuccess,
        command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type)
      )

      # TODO: Should the service call this in an uncacheable way?
      @queue.repository.reset_refs

      result = T.cast(
        command.create_ref!(entry, base_sha: @pr.base_sha, method: @queue.merge_method_type),
        ICommand::Result::BranchProtectionError
      )

      assert_equal "Repository rule violations found", result.message
    end
  end
end
