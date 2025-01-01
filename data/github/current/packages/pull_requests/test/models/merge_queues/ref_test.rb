# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  # Base test class for testing the creation of a branch for a PR.
  class RefTest < GitHub::TestCase
    include PullRequestSynchronizationTestHelpers
    include HydroMessageJobTestHelpers
    include DogstatsTestHelpers

    include HydroTestHelpers
    fixtures do
      Spokesd.enable_spokesd

      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      enable_feature_flag(:merge_queue)

      @queue = create(:merge_queue)
      @queue_entry = create(:merge_queue_entry, queue: @queue)

      @repo = @queue.repository
      @queue_branch = @repo.heads.find(@queue.branch).freeze

      @pr = @queue_entry.pull_request
      @pr.issue.title = "a meaningful title"
      @pr.issue.body = "a meaningful body"
      @pr.issue.save!

      @protected_branch = @repo.protect_branch(
        @pr.base_ref_name,
        creator: @repo.owner,
        enforce_merge_queue: true,
        required_status_checks: { contexts: %w[required-run] },
      )

      @protected_branch.enable_merge_queue
      @protected_branch.save
      example_repo_snapshot
    end

    setup do
      example_repo_restore
    end

    def perform_push_jobs(&block)
      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob], &block)
    end

    sig { params(entry: MergeQueueEntry, target: String).returns(Ref::Result::Success) }
    def create_branch!(entry:, target: @queue.branch_head_oid)
      branch = Ref.new(
        entry:,
        base_sha: target,
        head_sha: entry.enqueued_head_sha,
        repository: @repo,
        queue: @queue,
        merge_method: @queue.merge_method_type,
        timestamp: entry.enqueued_at.utc,
        enqueuer: entry.enqueuer,
        pull_request: T.must(entry.pull_request),
      ).create

      fail "Expected a successful result, got: #{branch.inspect}" unless branch.is_a?(Ref::Result::Success)

      branch
    end

    sig { params(entry: MergeQueueEntry, target: String).returns(Ref::Result) }
    def attempt_create_branch!(entry:, target: @queue.branch_head_oid)
      branch = Ref.new(
        entry:,
        base_sha: target,
        head_sha: entry.enqueued_head_sha,
        repository: @repo,
        queue: @queue,
        merge_method: @queue.merge_method_type,
        timestamp: entry.enqueued_at.utc,
        enqueuer: entry.enqueuer,
        pull_request: T.must(entry.pull_request),
      ).create
    end

    sig { params(name: String).returns(Git::Ref) }
    def find_ref(name)
      T.let(@queue.queue_ref_collection.find(name), Git::Ref).tap do |ref|
        assert ref.exists?
        assert ref.commit?
      end
    end
  end

  class PrivateRefRefTest < RefTest
    setup do
      enable_feature_flag(:merge_queue_uses_queue_refs, @repo)
    end

    %w(merge squash rebase).each do |merge_method|
      test "performs creation using the #{merge_method} strategy" do
        @queue.update!(merge_method:)

        branch = perform_push_jobs do
          create_branch!(entry: @queue_entry, target: @queue.branch_head_oid)
        end

        ref = find_ref(branch.head_ref)

        parent_count = merge_method == "merge" ? 2 : 1
        assert_equal parent_count, ref.commit.parent_oids.count

        assert_equal MergeQueue::READ_ONLY_REF_PREFIX, ref.prefix
        assert_equal 0, @repo.pushes.count
        assert_equal 0, MergeQueueLockedRef.where(ref: ref.qualified_name).count
      end
    end
  end

  class PublicRefRefTest < RefTest
    setup do
      disable_feature_flag(:merge_queue_uses_queue_refs, @repo)
    end

    %w(merge squash rebase).each do |merge_method|
      context "with strategy: #{merge_method}" do
        test "creates a ref in the public namespace" do
          @queue.update!(merge_method:)

          branch = perform_push_jobs do
            create_branch!(entry: @queue_entry, target: @queue.branch_head_oid)
          end

          ref = find_ref(branch.head_ref)

          parent_count = merge_method == "merge" ? 2 : 1
          assert_equal parent_count, ref.commit.parent_oids.count

          assert_equal MergeQueue::READ_ONLY_BRANCH_PREFIX, ref.prefix
          assert_equal 1, @repo.pushes.where(ref: ref.qualified_name, before: GitHub::NULL_OID, after: ref.sha).count
          assert_equal 1, MergeQueueLockedRef.where("ref LIKE ?", "%#{ref.name}").count
        end

        test "idempotently executes creation" do
          @queue.update!(merge_method:)

          2.times do
            create_branch!(entry: @queue_entry, target: @queue.branch_head_oid)
          end

          assert_equal 1, @queue.queue_ref_collection.count
        end
      end
    end
  end

  class SquashRefTest < RefTest
    setup do
      @queue.update!(merge_method: "squash")
    end

    test "uses the default squash commit title" do
      branch = create_branch!(entry: @queue_entry, target: @queue.branch_head_oid)
      ref = find_ref(branch.head_ref)

      assert_equal @pr.default_squash_commit_title, ref.commit.message
    end
  end

  class RebaseRefTest < RefTest
    setup do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @queue.update!(merge_method: "rebase")
    end

    test "rebase_tmp_objdir_experiment" do
      enable_feature_flag(:tmp_objdir_experiment)

      example_repo_restore # must start from clean slate
      result = create_branch!(
        entry: @queue_entry,
        target: @queue.branch_head_oid,
      )

      assert_dogstats_count(1, "rebase.loose_objects_count", tags: ["status:success"])
      assert_dogstats_count(1, "merge_tree.loose_objects_count", tags: ["status:success"])
    end

    test "rebases the all the commits on branch creation" do
      commit = @repo.heads.find(@pr.base_ref).append_commit({ message: "Add a file", committer: @repo.owner }, @repo.owner) do |files|
        files.add("a_new_commit.txt", "new commit")
      end
      reset_hydro

      branch = create_branch!(entry: @queue_entry, target: @queue.branch_head_oid)

      # Ensure we only ever fire one of them.
      with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) { assert_hydro_messages(count: 1, schema: "github.repositories.v1.Pushed") }

      ref = find_ref(branch.head_ref)

      assert_equal 1, ref.commit.parent_oids.count
      assert_equal commit.oid, ref.commit.parent_oids.first
    end

    test "it errors if a rebase merge method returns nil and is treated as a conflict" do
      MergeQueues.remove!(queue: @queue, entry: @queue_entry, actor: @pr.user)

      # Ensure we have a rebase conflict at the end of this block.
      with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do

        @repo.refs.find(@pr.base_ref).append_commit({
          message: "Commit on master",
          committer: @repo.owner,
        }, @repo.owner) do |files|
          files.add("README.md", "Will this conflict?")
        end

        pr_ref = @repo.refs.find(@pr.head_ref)

        pr_ref.append_commit({
          message: "Commit on topic",
          committer: @pr.user,
        }, @pr.user) do |files|
          files.add("README.md", "This will conflict")
        end

        pr_ref.append_commit({
          message: "Commit on topic",
          committer: @pr.user,
        }, @pr.user) do |files|
          files.remove("README.md")
        end

        pr_ref.append_commit({
          message: "Commit on topic",
          committer: @pr.user,
        }, @pr.user) do |files|
          files.add("README.md", "Will this conflict?")
        end
      end

      GitHub.expects(:merge_commit_update_refs_bot).returns(@pr.user)

      # We must have a valid merge commit to re-enqueue the PR.
      PullRequests::MergeCommit::CreateMergeCommitsJob.perform_now(@pr)
      PullRequests::MergeCommit::BatchRefUpdatesJob.perform_now(@pr.repository)

      @pr.reload

      # We must have a valid check suite to re-enqueue the PR.
      create(:check_suite,
        :success,
        repository: @repo,
        head_sha: @pr.head_sha,
        head_branch: @pr.head_ref_name,
        creator: @repo.owner,
        display_name: "required-run",
      )

      entry = @queue.enqueue!(pull_request: @pr, enqueuer: @pr.user)

      branch = attempt_create_branch!(
        entry: entry,
        target: @repo.ref_to_sha(@queue.branch),
      )

      fail "Expected an error result" if branch.is_a?(MergeQueues::Ref::Result::Success)

      assert_equal MergeQueues::Ref::ErrorCode::RebaseConflict, branch.error
    end

    test "it errors if a rebase merge method raises a timeout error" do
      # Simulate a timeout.
      exception = GitRPC::Backend::RebaseTimeout.new("Rebase timed out")
      GitRPC::Client.any_instance.expects(
        @repo.feature_enabled?(:tmp_objdir_experiment) ? :rebase_tmp_objdir_experiment : :rebase
      ).raises(exception)

      result = attempt_create_branch!(
        entry: @queue_entry,
        target: @queue.branch_head_oid,
      )

      fail "Expected an error result" if result.is_a?(Ref::Result::Success)

      assert_equal Ref::ErrorCode::RebaseTimeout, result.error
      assert_equal exception, result.exception
    end

    test "when the commit produces an identical base/head sha it is treated as a failure" do
      # Simulate an already merged PR by fast fowarding the target branch.
      @repo.refs.find(@queue.branch).update(@pr.head_sha, @repo.owner, reflog_data: {}, force: true)

      result = attempt_create_branch!(
        entry: @queue_entry,
        target: @queue.reload.branch_head_oid,
      )

      fail "Expected an error result" unless result.is_a?(Ref::Result::Error)

      assert_equal Ref::ErrorCode::AlreadyMerged, result.error
    end
  end

  class MergeRefTest < RefTest
    setup do
      @queue.update!(merge_method: "merge")
    end

    test "it errors if the merge command returns an invalid payload" do
      CommitsCollection.any_instance.expects(:create_merge_commit).returns([nil, nil, nil])

      result = attempt_create_branch!(
        entry: @queue_entry,
        target: @queue.branch_head_oid,
      )

      fail "Expected an error result" if result.is_a?(Ref::Result::Success)

      assert_equal Ref::ErrorCode::FailedMerge, result.error
    end

    test "creates a merge with the expected message when merge method is 'merge' (default)" do
      @repo.config.delete(Configurable::MergeCommitMessage::KEY)

      branch = attempt_create_branch!(
        entry: @queue_entry,
        target: @queue.branch_head_oid,
      )

      fail "Expected a successful result, got: #{branch.inspect}" unless branch.is_a?(Ref::Result::Success)
      ref = find_ref(branch.head_ref)
      expected_message = "#{@pr.default_merge_commit_title}\n\n#{@pr.default_merge_commit_message}"
      assert_equal expected_message, ref.commit.message
    end

    test "creates a merge with the expected message when merge method is 'merge' (body)" do
      @repo.set_merge_commit_message_setting(
        setting: Configurable::MergeCommitMessage::PR_BODY,
        actor: @repo.owner
      )

      branch = create_branch!(entry: @queue_entry, target: @queue.branch_head_oid)
      ref = find_ref(branch.head_ref)
      expected_message = "#{@pr.default_merge_commit_title}\n\n#{@pr.default_merge_commit_message}"

      assert_equal expected_message, ref.commit.message
    end

    test "creates a merge with the expected message when merge method is 'merge' (title)" do
      @repo.set_merge_commit_message_setting(
        setting: Configurable::MergeCommitMessage::PR_TITLE,
        actor: @repo.owner
      )

      branch = create_branch!(entry: @queue_entry, target: @queue.branch_head_oid)
      ref = find_ref(branch.head_ref)
      expected_message = "#{@pr.default_merge_commit_title}\n\n#{@pr.default_merge_commit_message}"

      assert_equal expected_message, ref.commit.message
    end

    test "creates a merge with the expected message when merge method is 'merge' (blank)" do
      @repo.set_merge_commit_message_setting(
        setting: Configurable::MergeCommitMessage::BLANK,
        actor: @repo.owner
      )

      branch = create_branch!(entry: @queue_entry, target: @queue.branch_head_oid)
      ref = find_ref(branch.head_ref)

      assert_equal @pr.default_merge_commit_title, ref.commit.message
    end

    test "is invalid and no ref is created if there is a merge conflict" do
      @repo.heads.find(@pr.base_ref).append_commit({ message: "Add a conflict", committer: @repo.owner }, @repo.owner) do |files|
        files.add("bar.txt", "this conflicts with the pull request")
      end

      branch = attempt_create_branch!(
        entry: @queue_entry,
        target: @queue.branch_head_oid,
      )

      fail "Expected an error result" if branch.is_a?(Ref::Result::Success)

      assert_equal Ref::ErrorCode::MergeConflict, branch.error
      assert @queue.queue_ref_collection.empty?

      assert_hydro_published(
        {
          repository_id: @pr.repository.id,
          base_commit_oid: @pr.current_base_oid,
          head_commit_oid: @pr.current_head_oid,
          conflicts: [
            {
              path: "bar.txt",
              ours: {
                blob_oid: "8318c86b357b6ddbf674ad238b8745d2781cab4b",
                size: 4,
                is_binary: false
              },
              theirs: {
                blob_oid: "2383650fc3bc2cbca6b38a4cb792fd916239e506",
                size: 36,
                is_binary: false
              },
              ancestor: {
                blob_oid: "",
                size: 0,
                is_binary: false
              },
              conflict_type: :REGULAR
            }
          ],
          more_conflicts_exist: false,
          pull_request_id: @pr.id,
          queued: true
        },
        schema: "github.pull_requests.v1.MergeConflict",
        count: 1,
        partition_key: @pr.repository.id
      )
    end
  end

  class DiffSameRefTest < RefTest
    def merge_and_add_required_run_check(pr)
      pr.reload.create_merge_commit
      check_suite = create(:check_suite, creator: pr.user, repository: @repo, head_sha: pr.merge_commit_sha)
      create(:check_run, :success, check_suite:, display_name: "required-run")
    end

    # In this exploit, the attacker takes advatage of the fact that Git drops merge commits when performing a rebase.
    # By including a non-empty merge commit in the pull request, changes can be displayed during PR review which will
    # disappear when the merge queue is creates a rebase.
    #
    #                      master
    #                    ↙
    # o—————o—— · · · ——o · · · · · · ◌
    #        ╲         ╱             ·
    #         *——————(A) ←——— random·previously-merged PR -- contents don't matter
    #          ╲       ╲           ·
    #           ╲       *——(C)———(D) ←—— exploit / pull request
    #            ╲     ╱
    #             *——(B)
    [
      # Merge not blocked
      { method: "merge",  expect_error: false },
      # Rebase blocked iff enforced
      { method: "rebase", expect_error: true },
      # Squash not blocked
      { method: "squash", expect_error: false },
    ]
    .each do |opts|
      test "diffsame check rejects 'merge commit removal' exploit #{opts[:method]}" do
        @queue.update!(merge_method: opts[:method])

        base_ref_name = @pr.base_ref_name

        ref_a = @repo.heads.create("ref-a", @repo.heads.find(base_ref_name).target, @pr.user)
        ref_a.append_commit({ message: "ref-a-#{SecureRandom.hex}", committer: @pr.user }, @pr.user) do |files|
          files.add("file-a-b.txt", "unrelated change")
        end

        @repo.heads.find(base_ref_name).merge(@repo.owner, "ref-a")

        ref_b = @repo.heads.create("ref-b", @repo.heads.find(base_ref_name).target, @pr.user)
        ref_b.append_commit({ message: "ref-b-#{SecureRandom.hex}", committer: @pr.user }, @pr.user) do |files|
          files.add("file-a-b.txt", "unrelated change")
        end

        commit_c = ref_a.merge(@repo.owner, "ref-b").first
        added_file_commit = ref_a.append_commit({ message: "ref-a-b-addfile-#{SecureRandom.hex}", committer: @pr.user }, @pr.user) do |files|
          files.add("file-added.txt", "disappearing change")
        end

        # Create a custom merge commit with extra changes that disappear during merge
        custom_merge_commit_oid = @repo.create_merge_commit(
          commit_c.parent_oids.first, commit_c.parent_oids.second,
          { name: "Author Name", email: "Internal email", time: Time.now },
          "Merge commit with disappearing changes",
          { tree: added_file_commit.tree_oid }
        ).first

        ref_exploit = @repo.heads.create("exploit", custom_merge_commit_oid, @pr.user)
        commit_d = ref_exploit.append_commit({ message: "ref-exploit-#{SecureRandom.hex}", committer: @pr.user }, @pr.user) do |files|
          files.add("file-exploit.txt", "persisted change")
        end

        pull_request = create(:pull_request, repository: @repo, head_ref: "exploit", head_sha: commit_d.oid)
        merge_and_add_required_run_check(pull_request)

        entry = create(:merge_queue_entry, queue: @queue, pull_request:)

        result = attempt_create_branch!(
          target: @queue.branch_head_oid,
          entry:
        )

        if opts[:expect_error]
          assert result.is_a?(Ref::Result::Error)
          assert_equal Ref::ErrorCode::InvalidMergeCommit, T.cast(result, Ref::Result::Error).error
        else
          fail "Expected success, got: #{result.inspect}" unless result.is_a?(Ref::Result::Success)
        end
      end
    end

    # In this exploit, the attacker adds PR1 to the merge queue before PR2. When PR1 merges, it shifts the merge base
    # of PR2 in such a way that when commit D is merged onto @base_sha, it will introduce the exploit code.
    #
    #                      master
    #                    ↙
    # o—————o———————————o · · · ◌ · · ◌
    #        ╲         ╱       ·     ·
    #        (A)—————(B)      ·     ·
    #          ╲       ╲     ·     ·
    #           ╲       *———o ←—— exploit-1 / PR1
    #            ╲     ╱         ·
    #             *——(C)        ·
    #                  ╲       ·
    #                   *———(D) ←— exploit-2 / PR2
    [
      # Merge blocked iff enforced
      { method: "merge",  expect_error: true },
      # Rebase blocked iff enforced
      { method: "rebase", expect_error: true },
      # Squash not blocked
      { method: "squash", expect_error: false },
    ]
    .each do |opts|
      test "diffsame check rejects 'merge base shift' exploit #{opts[:method]}" do
        @queue.update!(merge_method: opts[:method])

        base_ref_name = @pr.base_ref_name

        exploit_2 = @repo.heads.create("exploit-2", @repo.heads.find(base_ref_name).target, @pr.user)
        commit_a = exploit_2.append_commit({ message: "commit-a-#{SecureRandom.hex}", committer: @pr.user }, @pr.user) do |files|
          files.add("commit-a.txt", "unrelated change")
          files.add("exploit.txt", "EXPLOIT")
        end

        commit_c = exploit_2.append_commit({ message: "commit-c-#{SecureRandom.hex}", committer: @pr.user }, @pr.user) do |files|
          files.add("commit-c.txt", "unrelated change")
          files.remove("exploit.txt")
        end

        commit_d = exploit_2.append_commit({ message: "commit-d-#{SecureRandom.hex}", committer: @pr.user }, @pr.user) do |files|
          files.add("commit-d.txt", "unrelated change")
          files.add("exploit.txt", "EXPLOIT")
        end

        exploit_1 = @repo.heads.create("exploit-1", commit_a.oid, @pr.user)
        commit_b = exploit_1.append_commit({ message: "commit-b-#{SecureRandom.hex}", committer: @pr.user }, @pr.user) do |files|
          files.add("commit-b.txt", "unrelated change")
          files.remove("exploit.txt")
        end

        @repo.heads.find(base_ref_name).merge(@repo.owner, commit_b.oid)

        b_c_merge_commit = exploit_1.merge(@repo.owner, commit_c.oid).first

        pull_request_1 = create(:pull_request, repository: @repo, head_ref: "exploit-1", head_sha: b_c_merge_commit.oid)
        merge_and_add_required_run_check(pull_request_1)

        pull_request_2 = create(:pull_request, repository: @repo, head_ref: "exploit-2", head_sha: commit_d.oid)
        merge_and_add_required_run_check(pull_request_2)

        # Merge PR 1 first in the group
        entry_1 = create(:merge_queue_entry, queue: @queue, pull_request: pull_request_1)
        result = attempt_create_branch!(
          target: @queue.branch_head_oid,
          entry: entry_1,
        )

        fail "Expected success, got: #{result.inspect}" unless result.is_a?(Ref::Result::Success)
        new_base_sha = T.cast(result, Ref::Result::Success).head_oid

        # Now merge PR 2 first on top of PR 1
        entry_2 = create(:merge_queue_entry, queue: @queue, pull_request: pull_request_2)
        result = attempt_create_branch!(
          target: new_base_sha,
          entry: entry_2,
        )

        if opts[:expect_error]
          assert result.is_a?(Ref::Result::Error)
          assert_equal Ref::ErrorCode::InvalidMergeCommit, T.cast(result, Ref::Result::Error).error
        else
          fail "Expected success, got: #{result.inspect}" unless result.is_a?(Ref::Result::Success)
        end
      end
    end

    # This attack exploits a feature in Git rebase called "duplicate cherry-pick removal" -- you can read about it here:
    # https://tlatsas.github.io/2013/07/28/using-git-rebase-to-remove-duplicate-cherry-picked-commits
    #
    # The attacker finds any exploitable piece of code anywhere in the history of master, and creates a commit which
    # duplicates its removal. The duplicate can be arbitrarily far removed from the current HEAD of master. They then
    # add the exploit back in, along with harmless changes so that the PR doesn't appear empty. The exploit code will
    # not appear in the PR review page, but it will be silenty added to master during the merge queue rebase operation.
    #
    #                                   master
    #                                 ↙
    # o————(A)——————(B)— · · · —o——o
    #        ╲
    #         ╲         C tree-equal to B
    #          ╲      ↙
    #           *———(C)————(D) ←—— exploit / pull request
    [
      # Merge not blocked
      { method: "merge",  expect_error: false },
      # Rebase blocked iff enforced
      { method: "rebase", expect_error: true },
      # Squash not blocked
      { method: "squash", expect_error: false },
    ]
    .each do |opts|
      test "diffsame check rejects 'duplicate cherry-pick removal' exploit #{opts[:method]}" do
        @queue.update!(merge_method: opts[:method])

        base_ref_name = @pr.base_ref_name

        ref_base = @repo.heads.find(base_ref_name)
        commit_a = ref_base.append_commit({ message: "commit-a-#{SecureRandom.hex}", committer: @repo.owner }, @repo.owner) do |files|
          files.add("commit-a.txt", "unrelated change")
          files.add("exploit.txt", "EXPLOIT")
        end

        commit_b = ref_base.append_commit({ message: "commit-b-#{SecureRandom.hex}", committer: @repo.owner }, @repo.owner) do |files|
          files.remove("exploit.txt")
        end

        ref_exploit = @repo.heads.create("exploit", commit_a.oid, @pr.user)
        commit_c = ref_exploit.append_commit({ message: "commit-c-#{SecureRandom.hex}", committer: @pr.user }, @pr.user) do |files|
          files.remove("exploit.txt")
        end

        commit_d = ref_exploit.append_commit({ message: "commit-d-#{SecureRandom.hex}", committer: @pr.user }, @pr.user) do |files|
          files.add("commit-d.txt", "unrelated change")
          files.add("exploit.txt", "EXPLOIT")
        end

        pull_request = create(:pull_request, repository: @repo, head_ref: "exploit", head_sha: commit_d.oid)
        merge_and_add_required_run_check(pull_request)

        entry = create(:merge_queue_entry, queue: @queue, pull_request: pull_request)
        result = attempt_create_branch!(
          target: @queue.branch_head_oid,
          entry: entry,
        )

        if opts[:expect_error]
          assert result.is_a?(Ref::Result::Error)
          assert_equal Ref::ErrorCode::InvalidMergeCommit, T.cast(result, Ref::Result::Error).error
        else
          fail "Expected success, got: #{result.inspect}" unless result.is_a?(Ref::Result::Success)
        end
      end
    end
  end
end
