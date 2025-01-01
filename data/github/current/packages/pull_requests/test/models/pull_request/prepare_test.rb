# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestPrepareTest < GitHub::TestCase
  include HydroTestHelpers
  include PullRequestSynchronizationTestHelpers
  include DogstatsTestHelpers

  # All tests in this class need share_spokesdb
  Spokesd.share_spokesdb(self)

  fixtures do
    @owner = create(:user, login: "ari")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: @forker, repository: @source)
    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    Spokesd.enable_spokesd
  end

  def stub_create_merge_commit_to_error(pull)
    Repository.any_instance.stubs(:disable_libgit2_to_git_experiments).returns(true)
    if GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository)
      @pull.repository.rpc.expects(:create_merge_commit).once.returns(
        ["BOOM", "error", nil, nil, [["rebase.dogstats.mock", 1, { tags: ["status:failure"] }]]]
      )
    else
      @pull.repository.rpc.expects(:create_merge_commit).once.returns(%w[BOOM error])
    end
  end

  def ensure_pull_has_merge_conflict
    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      @source.refs.find("master").append_commit({
        message: "Commit on master",
        committer: @owner,
      }, @owner) do |files|
        files.add("README.md", "Will this conflict?")
      end

      @fork.refs.find("topic").append_commit({
        message: "Commit on topic",
        committer: @forker,
      }, @forker) do |files|
        files.add("README.md", "This will conflict")
      end
    end

    @pull.reload
  end

  def ensure_pull_has_rebase_conflict
    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      @source.refs.find("master").append_commit({
        message: "Commit on master",
        committer: @owner,
      }, @owner) do |files|
        files.add("README.md", "Will this conflict?")
      end

      topic_ref = @fork.refs.find("topic")

      topic_ref.append_commit({
        message: "Commit on topic",
        committer: @forker,
      }, @forker) do |files|
        files.add("README.md", "This will conflict")
      end

      topic_ref.append_commit({
        message: "Commit on topic",
        committer: @forker,
      }, @forker) do |files|
        files.remove("README.md")
      end

      topic_ref.append_commit({
        message: "Commit on topic",
        committer: @forker,
      }, @forker) do |files|
        files.add("README.md", "Will this conflict?")
      end
    end

    @pull.reload
  end

  def assert_ref_exists(refname)
    assert_predicate @source.refs.read(@pull.rebase_ref), :exist?
  end

  def refute_ref_exists(refname)
    refute_predicate @source.refs.read(@pull.rebase_ref), :exist?
  end

  context "#perform" do
    test "prepares a merge commit and returns the prepared commit's id" do
      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable

      merge_commit = @source.commits.find(merge_commit_id)
      assert_equal [@pull.base_sha, @pull.head_sha], merge_commit.parent_oids
    end

    test "returns the expected data" do
      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable

      merge_commit = @source.commits.find(merge_commit_id)
      assert_equal [@pull.base_sha, @pull.head_sha], merge_commit.parent_oids
    end

    test "stores the prepared merge commit in the merge ref" do
      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable

      ref = @source.refs.read(@pull.merge_ref)
      assert_predicate ref, :exist?
      assert_equal merge_commit_id, ref.target_oid
    end

    test "returns a false mergeability status and no merge commit id when running into a conflict" do
      ensure_pull_has_merge_conflict

      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal false, mergeable
      assert_nil merge_commit_id
    end

    test "emits a conflict event when conflict occurs" do
      ensure_pull_has_merge_conflict

      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      refute mergeable, "expected unmergeable due to conflict"
      assert_nil merge_commit_id, "expected no merge commit id"
      assert_hydro_published(
        {
          repository_id: @pull.repository_id,
          base_commit_oid: @pull.current_base_oid,
          head_commit_oid: @pull.current_head_oid,
          conflicts: [
            {
              path: "README.md",
              ours: {
                blob_oid: "c2a29b67203cbc5f3a8cc1ad1c237761bd6df818",
                size: 18,
                is_binary: false
              },
              theirs: {
                blob_oid: "0a6f52f9dd32066f56517dee8fa218495f8056ba",
                size: 19,
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
          pull_request_id: @pull.id
        },
        schema: "github.pull_requests.v1.MergeConflict",
        count: 1,
        partition_key: @pull.repository_id
      )
    end

    test "can resolve merge commits based on the given conflict resolutions" do
      ensure_pull_has_merge_conflict

      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform(conflict_resolutions: {
        "README.md" => "This resolves the conflict.",
      })
      assert_equal true, mergeable

      merge_commit = @source.commits.find(merge_commit_id)
      assert_equal [
        @source.refs.find("master").target_oid,
        @fork.refs.find("topic").target_oid,
      ], merge_commit.parent_oids

      tree_entry = @source.rpc.read_tree_entry(merge_commit.tree_oid, "README.md")
      assert_equal "This resolves the conflict.", tree_entry["data"]
    end

    test "does not modify the merge ref when running into a conflict" do
      mergeable, old_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable
      assert old_merge_commit_id

      ensure_pull_has_merge_conflict

      mergeable, new_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal false, mergeable
      assert_nil new_merge_commit_id

      ref = @source.refs.read(@pull.merge_ref)
      assert_predicate ref, :exist?
      assert_equal old_merge_commit_id, ref.target_oid
    end

    test "does not try to prepare a rebase when running into a conflict" do
      ensure_pull_has_merge_conflict
      @pull.repository.rpc.expects(
        GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository) ? :rebase_tmp_objdir_experiment : :rebase
      ).never

      mergeable, new_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal false, mergeable
      assert_nil new_merge_commit_id
    end

    test "returns a false mergeability status and no merge commit id when the pull request was already merged" do
      mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable
      refute_nil temp_merge_commit_id

      @pull.merge

      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal false, mergeable

      refute merge_commit_id
    end

    test "does not modify the merge ref when the pull request was already merged" do
      mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable
      refute_nil temp_merge_commit_id

      perform_enqueued_jobs(only: [DestroyMergeRefsJob]) do
        @pull.merge
      end

      ref = @source.refs.read(@pull.merge_ref)
      refute_predicate ref, :exist?

      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal false, mergeable
      assert_nil merge_commit_id

      ref = @source.refs.read(@pull.merge_ref)
      refute_predicate ref, :exist?
    end

    test "does not try to prepare a rebase when the pull request was already merged" do
      mergeable, temp_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable
      refute_nil temp_merge_commit_id

      @pull.merge

      mergeable, new_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal false, mergeable
      assert_nil new_merge_commit_id
    end

    test "returns a false mergeability status and no merge commit id when an unknown error happens during merge commit creation" do
      stub_create_merge_commit_to_error(@pull)

      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal false, mergeable
      refute merge_commit_id
    end

    test "does not modify the merge ref when an unknown error happens during merge commit creation" do
      mergeable, old_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable
      assert old_merge_commit_id

      stub_create_merge_commit_to_error(@pull)

      mergeable, new_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal false, mergeable
      assert_nil new_merge_commit_id

      ref = @source.refs.read(@pull.merge_ref)
      assert_predicate ref, :exist?
      assert_equal old_merge_commit_id, ref.target_oid
    end

    test "does not try to prepare a rebase when an unknown error happens during merge commit creation" do
      stub_create_merge_commit_to_error(@pull)
      @pull.repository.rpc.expects(
        GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository) ? :rebase_tmp_objdir_experiment : :rebase
      ).never

      mergeable, new_merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal false, mergeable
      assert_nil new_merge_commit_id
    end

    test "rebase_tmp_objdir_experiment" do
      GitHub.flipper[:tmp_objdir_experiment].enable
      GitHub.flipper[:tmp_objdir_experiment_pack].disable

      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable

      assert_dogstats_count_value(3, "rebase.loose_objects_count_delta", tags: ["status:success"])

      # force the DGit backends to disagree on the DogStats while merging
      # need to create stubbed content with real tree & commit parent OIDs
      base = @source.heads.find(@pull.base_ref).target_oid
      tree = @source.commits.find(merge_commit_id).tree_oid
      stubbed = [1, 2, 3].map do |count|
        [
          "tree #{tree}\nparent #{base}\nauthor foo <f@f.com> 1706562368 +0000\ncommitter GitHub <noreply@github.com> 1706562368 +0000\n\nMessage\n",
          nil,
          nil,
          tree,
          %w[
            loose_objects_count, loose_objects_count_delta, loose_objects_size, loose_objects_size_delta,
            packfiles_count, packfiles_count_delta, packfiles_size, packfiles_size_delta
          ].map { |key| ["merge_tree.#{key}", count, { tags: ["status:success"] }] }
        ]
      end
      GitRPC::Backend.any_instance.stubs(:stage_signed_merge_commit).returns(*stubbed)

      # force the DGit backends to disagree on the DogStats while rebasing
      rebase_commit_oid = @pull.repository.rpc.rev_parse("refs/__gh__/pull/1/rebase")
      stubbed = [1, 2, 3].map do |count|
        [
          rebase_commit_oid,
          %w[
            loose_objects_count, loose_objects_count_delta, loose_objects_size, loose_objects_size_delta,
            packfiles_count, packfiles_count_delta, packfiles_size, packfiles_size_delta
          ].map { |key| ["rebase.#{key}", count, { tags: ["status:success"] }] }
        ]
      end
      GitRPC::Backend.any_instance.stubs(:rebase_tmp_objdir_experiment).returns(*stubbed)

      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable

      assert_dogstats_increment(2, "pull_request.prepare.commits.rebase", tags: ["result:success}"])
    end

    test "rebases and stores the result in the hidden rebase ref" do
      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable

      assert_ref_exists(@pull.rebase_ref)

      commit_oid = @source.refs.read(@pull.rebase_ref).target_oid

      original_commits = @pull.comparison.commits

      # We have 3 initial commits here, but only 2 of those get reapplied.
      # The contents of the third commit is already included in the base branch,
      # and so it gets dropped.
      assert_equal 3, original_commits.size

      c = @source.commits.find(commit_oid)
      # Commit id changes, tree id is stable
      assert_equal "931244c2872cd67049d710a288b6361c0289fe96", c.tree_oid
      assert_equal original_commits[2].message, c.message
      assert_equal original_commits[2].author_name, c.author_name
      assert_equal original_commits[2].author_email, c.author_email
      assert_equal @forker.git_author_name, c.committer_name
      assert_equal @forker.git_author_email, c.committer_email

      c = @source.commits.find(c.parent_oids[0])
      # Commit id changes, tree id is stable
      assert_equal "84a3d27e743a9a8504002752cd452d864c2ed0bc", c.tree_oid
      assert_equal original_commits[1].message, c.message
      assert_equal original_commits[1].author_name, c.author_name
      assert_equal original_commits[1].author_email, c.author_email
      assert_equal @forker.git_author_name, c.committer_name
      assert_equal @forker.git_author_email, c.committer_email

      assert_equal [@source.heads.find(@pull.base_ref).target_oid], c.parent_oids
    end

    test "skips rebase if flag is set" do
      @pull.repository.rpc.expects(
        GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository) ? :rebase_tmp_objdir_experiment : :rebase
      ).never

      mergeable, new_merge_commit_id = PullRequest::Prepare.new(pull: @pull, skip_rebase: true).perform
    end

    test "deletes the hidden ref if the rebase fails" do
      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable
      refute @pull.rebase_conflicts?

      assert_ref_exists(@pull.rebase_ref)

      ensure_pull_has_rebase_conflict

      mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
      assert_equal true, mergeable

      assert @pull.rebase_conflicts?
      assert @pull.rebase_conflict.present?
      refute_ref_exists(@pull.rebase_ref)
    end

    test "handles single-replica rebase timeouts properly" do
      GitRPC::Backend.any_instance.stubs(:rebase)
        .raises(GitRPC::Backend::RebaseTimeout)
        .then.returns(@fork.refs["master"].sha)

      PullRequest::Prepare.new(pull: @pull).perform

      refute_ref_exists(@pull.rebase_ref)
    end

    test "handles two-replica rebase timeouts properly" do
      GitRPC::Backend.any_instance.stubs(:rebase)
        .raises(GitRPC::Backend::RebaseTimeout)
        .then.raises(GitRPC::Backend::RebaseTimeout)
        .then.returns(@fork.refs["master"].sha)

      PullRequest::Prepare.new(pull: @pull).perform

      refute_ref_exists(@pull.rebase_ref)
    end

    test "handles ResponseError rebase timeouts properly" do
      routes = @source.dgit_write_routes
      errors = routes.each_with_index.map do |r, idx|
        [r, idx % 2 == 0 ? GitRPC::Backend::RebaseTimeout.new : BERTRPC::ProtocolError.new(BERTRPC::ProtocolError::NO_HEADER)]
      end.to_h
      error = GitRPC::Protocol::DGit::ResponseError.new("catchme".dup, errors: errors)
      GitRPC::Client.any_instance.stubs(
        GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository) ? :rebase_tmp_objdir_experiment : :rebase
      ).raises(error)

      PullRequest::Prepare.new(pull: @pull).perform

      refute_ref_exists(@pull.rebase_ref)
    end

    context "pull_request_prepare_repo_size_tags" do
      test "tags repositories 'massive' for size" do
        Repository.any_instance.stubs(:disk_usage).returns(10.gigabyte / 1024)
        GitHub.flipper.enable(:pull_request_prepare_repo_size_tags)

        Timecop.freeze do
          mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
          assert_equal true, mergeable

          merge_commit = @source.commits.find(merge_commit_id)
          assert_equal [@pull.base_sha, @pull.head_sha], merge_commit.parent_oids

          assert_dogstats_distribution 1, "pullrequest.merge.create_merge_commit", tags: ["repo_size:massive"]
          assert_dogstats_distribution 1, "pullrequest.merge.batch_write_refs", tags: ["repo_size:massive"]
        end
      end

      test "tags repositories 'small' for size" do
        Repository.any_instance.stubs(:disk_usage).returns(10.kilobyte / 1024)
        GitHub.flipper.enable(:pull_request_prepare_repo_size_tags)


        Timecop.freeze do
          mergeable, merge_commit_id = PullRequest::Prepare.new(pull: @pull).perform
          assert_equal true, mergeable

          merge_commit = @source.commits.find(merge_commit_id)
          assert_equal [@pull.base_sha, @pull.head_sha], merge_commit.parent_oids

          assert_dogstats_distribution 1, "pullrequest.merge.create_merge_commit", tags: ["repo_size:small"]
          assert_dogstats_distribution 1, "pullrequest.merge.batch_write_refs", tags: ["repo_size:small"]
        end
      end
    end
  end
end
