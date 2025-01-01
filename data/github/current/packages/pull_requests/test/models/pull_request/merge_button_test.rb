# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMergeButtonTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers
  include HydroTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @ari = create(:user, login: "ari")
    @source = create(:repository, owner: @ari, from_example: :pull_request_source)
    @bwalsh = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @bwalsh, fork_repo: @source, from_example: :pull_request_fork)
    @issue = create(:issue, user: @bwalsh, repository: @source)

    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
  end

  setup do
    reset_repo_root

    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    reset_cache
  end

  def commit_to_repo(repo, branch:, file: "README.txt", content: nil, author: repo.owner, committer: repo.owner, message: "commit", actor: repo.owner, **options)
    metadata = {
      message: message,
      author: author,
      committer: committer,
    }

    ref = repo.heads.find(branch)
    ref.append_commit(metadata, actor, options) do |files|
      files.add(file, content || "test content at #{Time.now.to_f}")
    end

    refute_nil ref.target_oid
    ref.target_oid
  end

  test "can create a merge commit" do
    assert_nil @pull.mergeable
    sha = @pull.create_merge_commit
    assert sha
    assert_equal true, @pull.mergeable
  end

  test "can create a merge commit when the author is deleted" do
    User.create_ghost

    assert_nil @pull.mergeable
    @pull.user.destroy
    assert_nil @pull.reload_user

    sha = @pull.create_merge_commit

    assert sha
    assert_equal true, @pull.mergeable
  end

  test "writes merge commit to pull/id/merge ref" do
    sha = @pull.create_merge_commit
    assert_equal sha, @pull.repository.ref_to_sha("refs/pull/#{@pull.number}/merge")
  end

  test "persists the merge commit sha without updating timestamp" do
    updated_at = @pull.updated_at
    sha = @pull.create_merge_commit
    assert_equal sha, @pull.merge_commit_sha
    assert_equal sha, @pull.reload[:merge_commit_sha]
    assert_equal updated_at, @pull.updated_at
  end

  test "can merge changes without conflicts" do
    commit_to_repo(@source, branch: "master", file: "code.rb")
    commit_to_repo(@fork, branch: "topic", file: "code.py")

    @pull.reload

    sha = @pull.create_merge_commit
    assert sha
    assert_equal true, @pull.mergeable

    @pull.catch_up

    status, msg = @pull.merge
    assert_equal true, status
  end

  test "tracks the base_sha_on_merge when merging" do
    expected_sha = nil

    expected_sha = commit_to_repo(@source, branch: "master", file: "code.rb")
    commit_to_repo(@fork, branch: "topic", file: "code.py")

    refute_nil expected_sha

    @pull.catch_up
    @pull.reload
    @pull.merge

    assert_equal expected_sha, @pull.base_sha_on_merge
  end

  test "merge author is user and committer is GitHub" do
    status, oid = @pull.merge
    assert status, "expected merge to be successful"
    merge = @source.commits.find(oid)

    assert_equal merge.author_name, @bwalsh.git_author_name
    assert_equal merge.author_email, @bwalsh.git_author_email
    assert_equal merge.committer_name, GitHub.web_committer_name
    assert_equal merge.committer_email, GitHub.web_committer_email
  end

  test "triggers PullRequest merge event" do
    commit_to_repo(@source, branch: "master", file: "code.rb")
    commit_to_repo(@fork, branch: "topic", file: "code.py")

    @pull.reload

    sha = @pull.create_merge_commit
    assert sha
    assert_equal true, @pull.mergeable

    T.unsafe(GitHub).reset_stratocaster

    @pull.catch_up
    perform_enqueued_jobs(only: ProcessEventJob) do
      status, msg = @pull.merge
      assert_equal true, status
    end

    assert event = GitHub.stratocaster.store.last
    assert_equal "PullRequestEvent", event.event_type

    assert_equal :closed, event.payload["action"]
    assert pull_hash = event.payload["pull_request"]
    assert_equal true, pull_hash["merged"]
    assert pull_hash["merged_at"]
    assert_equal @pull.reload.merge_commit_sha, pull_hash["merge_commit_sha"]
  end

  test "cannot create merge commit on conflicts" do
    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      commit_to_repo(@source, branch: "master")
      commit_to_repo(@fork, branch: "topic")
    end

    @pull.reload

    sha = @pull.create_merge_commit
    assert_equal false, sha
    assert_equal false, @pull.mergeable

    status, msg = @pull.merge
    assert_equal false, status
  end

  test "cannot merge when merge commit creation has failed" do
    Repository.any_instance.stubs(:disable_libgit2_to_git_experiments).returns(true)
    if GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository)
      @pull.repository.rpc.expects(:create_merge_commit).once.returns(
        [nil, "error", nil, nil, [["rebase.dogstats.mock", 1, { tags: ["status:failure"] }]]]
      )
    else
      @pull.repository.rpc.expects(:create_merge_commit).once.returns([nil, "error", nil])
    end
    Failbot.expects(:report).with do |exception|
      exception.kind_of?(CommitsCollection::MergeError)
    end

    sha = @pull.create_merge_commit
    assert_equal false, sha
    assert_equal false, @pull.mergeable

    status, msg = @pull.merge
    assert_equal false, status
  end

  test "git_merges_cleanly? queues background check" do
    assert_nil @pull.merge_commit_sha

    GitHub.expects(:merge_commit_update_refs_bot).returns(@ari)

    perform_enqueued_jobs(only: [PullRequests::MergeCommit::CreateMergeCommitsJob, PullRequests::MergeCommit::BatchRefUpdatesJob]) do
      assert_nil @pull.git_merges_cleanly?
    end

    @pull.reload
    assert_equal true, @pull.git_merges_cleanly?
  end

  test "includes mergeable information in api" do
    assert_nil @pull.mergeable
    assert @pull.create_merge_commit
    assert_equal true, @pull.mergeable
  end

  test "only mergeable if base_ref is a valid branch" do
    @pull.update_attribute(:base_ref, "no-such-branch")
    assert_nil @pull.current_base_sha
    refute @pull.currently_mergeable?
    assert_nil @pull.mergeable
    assert_equal false, @pull.git_merges_cleanly?
    assert_equal false, @pull.create_merge_commit
  end

  test "only mergeable if merge commit is up to date" do
    @pull.mergeable = true
    @pull.create_merge_commit

    commit_to_repo(@source, branch: "master", file: "code.js", content: "var hello;", post_receive: false)
    @pull.reload

    refute_predicate @pull, :git_merges_cleanly?

    @pull.create_merge_commit

    @pull.reload

    assert_predicate @pull, :git_merges_cleanly?
  end

  test "not mergeable if merge commit is out of date after a branch update" do
    # we simulate this situation here:
    #
    # --o---o---Z----+      <-- PR's base branch, Z = tip commit
    #    \   \   \    \
    #     \   \   \    M    <-- PR's merge commit
    #      \   \   \   |
    #       A---B---C  |    <-- PR's head branch, C = tip commit
    #            \     |
    #             +----+

    @pull.mergeable = true
    @pull.create_merge_commit
    merge_commit_sha_before = @pull.merge_commit_sha

    with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
      @pull.merge_base_into_head(user: @pull.user)
    end
    @pull.reload

    # merge_base_into_head did update the PR's mergeability, so we need
    # to reset it to create the desired situation.
    @pull.mergeable = true
    @pull.merge_commit_sha = merge_commit_sha_before

    refute_predicate @pull, :git_merges_cleanly?

    @pull.create_merge_commit

    @pull.reload

    assert_predicate @pull, :git_merges_cleanly?
  end

  test "not mergeable when merge commit is deleted by another process during the check" do
    # set the merge commit sha to a genuinely non-existent commit
    @pull.merge_commit_sha = "abcd" * 10
    @pull.mergeable = true

    # simulate that the commit exists when we verify its existence
    # but imagine that another process then gc's the merge commit before we can ensure
    # it is a decendant of the current base sha
    @pull.repository.commits.stubs(:exist?).returns(true)

    # should be false, not throwing exceptions
    refute @pull.git_merges_cleanly?
  end

  test "generates empty merge_commit_sha when asked for mergeability" do
    @pull.mergeable = true
    @pull.create_merge_commit
    @pull.update_attribute :merge_commit_sha, ""

    GitHub.expects(:merge_commit_update_refs_bot).returns(@ari)

    perform_enqueued_jobs(only: [PullRequests::MergeCommit::CreateMergeCommitsJob, PullRequests::MergeCommit::BatchRefUpdatesJob]) do
      assert_nil @pull.git_merges_cleanly?
    end

    @pull.reload
    assert_predicate @pull, :git_merges_cleanly?
    refute_equal "", @pull.merge_commit_sha
  end

  test "regenerates invalid merge_commit_sha when asked for mergeability" do
    sha = @pull.create_merge_commit
    assert sha
    assert_equal true, @pull.mergeable

    fake_sha = "1" * 40
    @pull.update_attribute :merge_commit_sha, fake_sha

    GitHub.expects(:merge_commit_update_refs_bot).returns(@ari)

    perform_enqueued_jobs(only: [PullRequests::MergeCommit::CreateMergeCommitsJob, PullRequests::MergeCommit::BatchRefUpdatesJob]) do
      assert_nil @pull.git_merges_cleanly?
    end

    @pull.reload
    assert_predicate @pull, :git_merges_cleanly?
    refute_equal fake_sha, @pull.merge_commit_sha
  end

  test "mergeable even after head branch is deleted" do
    # this is no longer true once this flag is enabled
    GitHub.flipper[:validate_repo_sha_when_merging].disable

    @fork.delete
    assert @pull.create_merge_commit
    status, msg = @pull.merge(@ari)
    assert status
  end

  test "not mergeable until PR sync has ran" do
    GitHub.flipper[:validate_repo_sha_when_merging].enable
    GitHub.flipper[:fail_on_head_repo_mismatch].enable

    commit_to_repo(@fork, branch: @pull.head_ref, file: "code.py")

    assert_equal @pull.merge, [false, "Head branch is out of date. Review and try the merge again.", :head_mismatch]

    @pull.catch_up
    @pull.reload

    assert @pull.merge
  end

  test "regenerates invalid/missing merge_commit_sha on merge" do
    sha = @pull.create_merge_commit
    assert sha
    assert_equal true, @pull.mergeable

    fake_sha = "1" * 40
    @pull.update_attribute :merge_commit_sha, fake_sha
    res = @pull.merge
    assert res.first, res.inspect
    @pull.reload
    refute_equal fake_sha, @pull.merge_commit_sha
  end

  test "never mergeable after merged" do
    assert @pull.merge.first
    @pull.reload
    assert_nil @pull.git_merges_cleanly?
    assert_nil @pull.create_merge_commit
    assert_nil @pull.mergeable
  end

  test "deletes merge ref after merge" do
    assert @pull.maintain_tracking_ref(@pull.user)
    assert @pull.create_merge_commit
    assert @pull.repository.ref_to_sha("refs/pull/#{@pull.number}/head")
    assert @pull.repository.ref_to_sha("refs/pull/#{@pull.number}/merge")

    perform_enqueued_jobs(only: [DestroyMergeRefsJob]) do
      assert @pull.merge.first
    end
    @pull.reload

    assert @pull.repository.ref_to_sha("refs/pull/#{@pull.number}/head")
    assert_nil @pull.repository.ref_to_sha("refs/pull/#{@pull.number}/merge")
  end

  test "deletes merge ref after close" do
    assert @pull.maintain_tracking_ref(@pull.user)
    assert @pull.create_merge_commit
    assert @pull.repository.ref_to_sha("refs/pull/#{@pull.number}/head")
    assert @pull.repository.ref_to_sha("refs/pull/#{@pull.number}/merge")

    perform_enqueued_jobs(only: [DestroyMergeRefsJob]) do
      assert @pull.close(@pull.user)
    end
    @pull.reload

    assert @pull.repository.ref_to_sha("refs/pull/#{@pull.number}/head")
    assert_nil @pull.repository.ref_to_sha("refs/pull/#{@pull.number}/merge")
  end

  test "maintains tracking ref when replicas disagree" do
    skip if GitHub.dgit_default_copies == 1
    assert_equal GitHub.dgit_default_copies, @source.dgit_write_routes.size
    res_rev_parse = { "argv" => %w[git foo], "ok" => false, "out" => "", "err" => "", "status" => 1 }
    res_fail = { "argv" => %w[git foo], "ok" => false, "out" => "", "err" => "", "status" => 1 }
    res_ok   = { "argv" => %w[git foo], "ok" => true,  "out" => "", "err" => "", "status" => 0 }
    GitRPC::Backend.any_instance.stubs(:spawn_git).returns(res_rev_parse, res_fail, res_ok)
    GitHub::DGit::Delegate::Repository.any_instance.expects(:on_disagreement).once
    GitHub::DGit::Delegate.any_instance.expects(:on_route_error).never
    GitHub::DGit::Delegate.any_instance.expects(:on_app_error).once

    # copy commits from @fork -> @source
    assert @pull.maintain_tracking_ref(@pull.user)
  end

  test "merge fails when not mergeable" do
    @pull.create_merge_commit
    @pull.update_attribute(:mergeable, false)
    assert_equal false, @pull.git_merges_cleanly?
    status, msg = @pull.merge(@ari)
    assert_equal false, status
  end

  test "merge a pull request" do
    assert !@pull.merged?
    status, new_sha = @pull.merge(@ari)

    assert_equal true, status, "pull#merge failed"
    assert_equal @source.ref_to_sha("master"), new_sha

    @pull.reload
    assert @pull.merged?, "pull is not merged"
  end

  test "pull request retrieved through the issue after merging reflects merged status" do
    @pull.merge(@ari)

    assert @pull.merged?
    assert @pull.issue.pull_request.merged?
  end

  test "merge a pull request when the author has been deleted" do
    User.create_ghost

    assert !@pull.merged?
    assert @pull.user != @ari
    @pull.user.destroy
    assert_nil @pull.reload_user

    status, new_sha = @pull.merge(@ari)

    assert_equal true, status, "pull#merge failed"
    assert_equal @source.ref_to_sha("master"), new_sha

    @pull.reload
    assert @pull.merged?, "pull is not merged"
  end

  test "standard merge commit message" do
    @pull.merge(@ari)
    commit = @source.commit_for_ref("master")
    assert_equal "Merge pull request ##{@pull.number} from bwalsh/topic\n\n#{@pull.title}",
                 commit.message
  end

  test "custom merge commit message" do
    @pull.merge(@ari, message: "fixes all of the things")
    commit = @source.commit_for_ref("master")
    assert_equal "Merge pull request ##{@pull.number} from bwalsh/topic\n\nfixes all of the things",
                 commit.message
  end

  test "empty merge commit message" do
    @pull.merge(@ari, message: "")
    commit = @source.commit_for_ref("master")
    assert_equal "Merge pull request ##{@pull.number} from bwalsh/topic",
                 commit.message
  end

  test "should write to reflog" do
    @source.rpc.fs_write("logs/refs/heads/master", "")
    @pull.merge(@ari, reflog_data: { remote_ip: "ari.local" })
    reflog = @source.rpc.fs_read("logs/refs/heads/master").split("\n").last
    assert_match /ari\.local/, reflog
    assert_match /#{@ari.login} <#{@ari.email}>/, reflog
  end

  test "#merged? should be consistent with #merged_by even when the #merge code is in progress (race condition)" do
    @pull.issue.events.create!(
      event: "merged",
      actor: @ari,
      commit_id: "whatever",
    )

    assert !@pull.merged?, "pull request should not think it is merged until merged_at is set"
    assert_nil @pull.merged_by, "pull request should not think it is merged until merged_at is set"
  end

  test "should fail when base has changed" do
    @pull.create_merge_commit
    commit_to_repo(@source, branch: "master")

    @pull = PullRequest.find_by(id: @pull.id)
    assert_equal true, @pull&.mergeable

    status, sha = @pull&.merge(@ari)
    assert_equal false, status
    assert_match /branch was modified/, sha

    assert_nil @pull&.mergeable
  end

  test "should fail when head has changed" do
    assert @pull.create_merge_commit
    sha = commit_to_repo(@fork, branch: "topic", file: "code.js")

    @pull = PullRequest.find_by(id: @pull.id)
    assert_equal true, @pull&.mergeable

    @pull&.head_sha = sha

    status, message = @pull&.merge(@ari)
    assert_equal false, status
    assert_match /branch was modified/, message

    assert_nil @pull&.mergeable
  end

  test "should fail when base changed" do
    assert @pull.create_merge_commit
    base_sha = @source.ref_to_sha("master")
    commit_to_repo(@source, branch: "master")

    # this is the new branch head
    updated_base_sha = @source.heads.read("master").target_oid
    refute_equal base_sha, updated_base_sha

    # reset the pull, should see that the base branch has moved
    @pull = PullRequest.find_by(id: @pull.id)
    assert_equal updated_base_sha, @pull&.mergeable_base_sha

    # we can detect the change in the app since we know the base changed
    res, message = @pull&.merge(@ari)
    assert !res, "failed status expected"
    assert message
  end

  test "should fail when atomic update-ref detects base has changed" do
    assert @pull.create_merge_commit
    base_sha = @source.ref_to_sha("master")
    commit_to_repo(@source, branch: "master")
    assert_equal base_sha, @pull.mergeable_base_sha

    # we've moved the base sha without the pull knowing it, only
    # git-update-ref should be able to detect the change
    res, message = @pull.merge(@ari)
    assert !res, "failed status expected"
    assert message
  end

  test "kicks off push processing" do
    @pull.merge(@ari)

    with_hydro_publisher(GitHub.sync_hydro_publisher) { assert_hydro_messages(count: 1, schema: "github.repositories.v1.Pushed") }
  end

  test "can squash commits during merge" do
    commit_count = @source.rpc.fast_commit_count(@source.ref_to_sha("master"), limit = 10_000)
    @source.reset_refs

    status, new_sha = @pull.merge(@ari, method: :squash)
    assert_equal true, status, "pull#merge failed"
    assert_equal @source.ref_to_sha("master"), new_sha

    @pull.reload
    assert @pull.merged?, "pull is not merged"

    assert_equal commit_count + 1, @source.rpc.fast_commit_count(new_sha, limit = 10_000)
  end

  test "squash merge author is PR creator" do
    status, oid = @pull.merge(@ari, method: :squash)
    assert status, "expected merge to be successful"
    merge = @source.commits.find(oid)

    assert_equal merge.author_name, @bwalsh.git_author_name
    assert_equal merge.author_email, @bwalsh.git_author_email
  end

  test "squash merge committer is GitHub's web committer" do
    status, oid = @pull.merge(@ari, method: :squash)
    assert status, "expected merge to be successful"
    merge = @source.commits.find(oid)

    assert_equal GitHub.web_committer_name, merge.committer_name
    assert_equal GitHub.web_committer_email, merge.committer_email
  end

  test "squash merge commit includes PR commit (co-)authors as co-authors" do
    forker = create(:user, :verified, login: "forker")
    opener = create(:user, :verified, login: "opener")
    author_1 = create(:user, :verified, login: "author-1")
    author_2 = create(:user, :verified, login: "author-2")
    committer = create(:user, :verified, login: "committer")
    co_author = create(:user, :verified, login: "co-author")
    merger = create(:user, :verified, login: "merger")
    new_fork = create(:fork_repository, forker: forker, fork_repo: @source, from_example: :pull_request_source)
    issue = create(:issue, user: opener, repository: @source)
    author_2_custom_name = "author-2-custom"
    author_2_custom_email = create(:verified_user_email, user: author_2, primary: false).email
    unknown_name, unknown_email = "unknown", Sham.email

    commit_to_repo(new_fork, branch: "master", file: "a.txt", author: author_1, message: "A")
    commit_to_repo(new_fork, branch: "master", file: "b.txt", author: author_1, message: <<~MSG)
      B

      Co-authored-by: #{co_author.git_author_name} <#{co_author.git_author_email}>
      Signed-off-by: #{co_author.git_author_name} <#{co_author.git_author_email}>
      MSG
    commit_to_repo(new_fork, branch: "master", file: "c.txt", author: author_2, message: "C")
    commit_to_repo(new_fork, branch: "master", file: "d.txt", author: author_2, committer: committer, message: "D")
    commit_to_repo(new_fork, branch: "master", file: "e.txt", author: opener, message: "E")
    commit_to_repo(new_fork, branch: "master", file: "f.txt", author: { name: author_2_custom_name, email: author_2_custom_email }, message: "F")
    commit_to_repo(new_fork, branch: "master", file: "g.txt", author: { name: unknown_name, email: unknown_email }, message: "G")

    pull = PullRequest.create_for(
      @source,
      base: "master",
      head: "#{new_fork.user}:master",
      user: opener,
      issue: issue,
    )

    status, oid = pull.merge(merger, method: :squash)
    assert status, "expected merge to be successful"
    merge = @source.commits.find(oid)

    assert_equal opener.git_author_name, merge.author_name
    assert_equal opener.git_author_email, merge.author_email
    assert_equal [
        opener.git_author_name,
        author_1.git_author_name,
        co_author.git_author_name,
        author_2.git_author_name,
        author_2_custom_name,
        unknown_name,
      ], merge.author_names
    assert_equal [
        opener.git_author_email,
        author_1.git_author_email,
        co_author.git_author_email,
        author_2.git_author_email,
        author_2_custom_email,
        unknown_email,
      ], merge.author_emails
    assert_equal <<~MSG.chomp, merge.message
      #{pull.title} (##{pull.number})

      * A

      * B

      Co-authored-by: #{co_author.git_author_name} <#{co_author.git_author_email}>
      Signed-off-by: #{co_author.git_author_name} <#{co_author.git_author_email}>

      * C

      * D

      * E

      * F

      * G

      ---------

      Signed-off-by: #{co_author.git_author_name} <#{co_author.git_author_email}>
      Co-authored-by: #{author_1.git_author_name} <#{author_1.git_author_email}>
      Co-authored-by: #{co_author.git_author_name} <#{co_author.git_author_email}>
      Co-authored-by: #{author_2.git_author_name} <#{author_2.git_author_email}>
      Co-authored-by: #{author_2_custom_name} <#{author_2_custom_email}>
      Co-authored-by: #{unknown_name} <#{unknown_email}>
      MSG
  end

  test "single-commit squash merge commit with pr body setting includes commit (co-)authors as co-authors" do
    @source.set_squash_merge_commit_message_setting(setting: Configurable::SquashMergeCommitMessage::PR_BODY, actor: @source.owner)

    forker = create(:user, :verified, login: "forker")
    opener = create(:user, :verified, login: "opener")
    author = create(:user, :verified, login: "author")
    merger = create(:user, :verified, login: "merger")
    new_fork = create(:fork_repository, forker: forker, fork_repo: @source, from_example: :pull_request_source)
    issue = create(:issue, user: opener, repository: @source, body: "This is a pull request body")

    commit_to_repo(new_fork, branch: "master", file: "a.txt", author: author,
      message: "Single commit message\n\nSigned-off-by: #{author.git_author_name} <#{author.git_author_email}>")

    pull = PullRequest.create_for(
      @source,
      base: "master",
      head: "#{new_fork.user}:master",
      user: opener,
      issue: issue,
    )

    status, oid = pull.merge(merger, method: :squash)
    assert status, "expected merge to be successful"
    merge = @source.commits.find(oid)

    assert_equal opener.git_author_name, merge.author_name
    assert_equal opener.git_author_email, merge.author_email
    assert_equal [opener.git_author_name, author.git_author_name], merge.author_names
    assert_equal [opener.git_author_email, author.git_author_email], merge.author_emails
    assert_equal <<~MSG.chomp, merge.message
      #{pull.default_squash_commit_title}

      This is a pull request body

      Signed-off-by: #{author.git_author_name} <#{author.git_author_email}>
      Co-authored-by: #{author.git_author_name} <#{author.git_author_email}>
      MSG
  end

  test "single-commit squash merge commit with commit messages setting includes commit (co-)authors as co-authors" do
    @source.set_squash_merge_commit_message_setting(setting: Configurable::SquashMergeCommitMessage::COMMIT_MESSAGES, actor: @source.owner)

    forker = create(:user, :verified, login: "forker")
    opener = create(:user, :verified, login: "opener")
    author = create(:user, :verified, login: "author")
    merger = create(:user, :verified, login: "merger")
    new_fork = create(:fork_repository, forker: forker, fork_repo: @source, from_example: :pull_request_source)
    issue = create(:issue, user: opener, repository: @source, body: "This is a pull request body")

    commit_to_repo(new_fork, branch: "master", file: "a.txt", author: author,
      message: "Single commit message\n\nSigned-off-by: #{author.git_author_name} <#{author.git_author_email}>")

    pull = PullRequest.create_for(
      @source,
      base: "master",
      head: "#{new_fork.user}:master",
      user: opener,
      issue: issue,
    )

    status, oid = pull.merge(merger, method: :squash)
    assert status, "expected merge to be successful"
    merge = @source.commits.find(oid)

    assert_equal opener.git_author_name, merge.author_name
    assert_equal opener.git_author_email, merge.author_email
    assert_equal [opener.git_author_name, author.git_author_name], merge.author_names
    assert_equal [opener.git_author_email, author.git_author_email], merge.author_emails
    assert_equal <<~MSG.chomp, merge.message
      #{pull.default_squash_commit_title}

      Signed-off-by: #{author.git_author_name} <#{author.git_author_email}>
      Co-authored-by: #{author.git_author_name} <#{author.git_author_email}>
      MSG
  end

  test "single-commit squash merge commit includes commit (co-)authors as co-authors" do
    @source.set_squash_merge_commit_title_setting(setting: Configurable::SquashMergeCommitTitle::PR_TITLE, actor: @source.owner)

    forker = create(:user, :verified, login: "forker")
    opener = create(:user, :verified, login: "opener")
    author = create(:user, :verified, login: "author")
    merger = create(:user, :verified, login: "merger")
    new_fork = create(:fork_repository, forker: forker, fork_repo: @source, from_example: :pull_request_source)
    issue = create(:issue, user: opener, repository: @source)

    commit_to_repo(new_fork, branch: "master", file: "a.txt", author: author,
      message: "Single commit message\n\nSigned-off-by: #{author.git_author_name} <#{author.git_author_email}>")

    pull = PullRequest.create_for(
      @source,
      base: "master",
      head: "#{new_fork.user}:master",
      user: opener,
      issue: issue,
    )

    status, oid = pull.merge(merger, method: :squash)
    assert status, "expected merge to be successful"
    merge = @source.commits.find(oid)

    assert_equal opener.git_author_name, merge.author_name
    assert_equal opener.git_author_email, merge.author_email
    assert_equal [opener.git_author_name, author.git_author_name], merge.author_names
    assert_equal [opener.git_author_email, author.git_author_email], merge.author_emails
    assert_equal <<~MSG.chomp, merge.message
      #{pull.default_squash_commit_title}

      Single commit message

      Signed-off-by: #{author.git_author_name} <#{author.git_author_email}>
      Co-authored-by: #{author.git_author_name} <#{author.git_author_email}>
      MSG
  end

  test "squash merge succeeds if the pull request opener disappears" do
    @source.set_squash_merge_commit_title_setting(setting: Configurable::SquashMergeCommitTitle::PR_TITLE, actor: @source.owner)

    forker = create(:user, :verified, login: "forker")
    opener = create(:user, :verified, login: "opener")
    author = create(:user, :verified, login: "author")
    merger = create(:user, :verified, login: "merger")
    new_fork = create(:fork_repository, forker: forker, fork_repo: @source, from_example: :pull_request_source)
    issue = create(:issue, user: opener, repository: @source)

    commit_to_repo(new_fork, branch: "master", file: "a.txt", author: author,
      message: "Single commit message\n\nSigned-off-by: #{author.git_author_name} <#{author.git_author_email}>")

    pull_id = PullRequest.create_for(
      @source,
      base: "master",
      head: "#{new_fork.user}:master",
      user: opener,
      issue: issue,
    ).id
    opener.destroy!
    pull = PullRequest.find(pull_id)

    status, oid = pull.merge(merger, method: :squash)
    assert status, "expected merge to be successful"
    merge = @source.commits.find(oid)

    assert_equal merger.git_author_name, merge.author_name
    assert_equal merger.git_author_email, merge.author_email
    assert_equal [merger.git_author_name, author.git_author_name], merge.author_names
    assert_equal [merger.git_author_email, author.git_author_email], merge.author_emails
    assert_equal <<~MSG.chomp, merge.message
      #{pull.default_squash_commit_title}

      Single commit message

      Signed-off-by: #{author.git_author_name} <#{author.git_author_email}>
      Co-authored-by: #{author.git_author_name} <#{author.git_author_email}>
      MSG
  end

  test "default_merge_commit_title uses PR title if Use PR Title setting enabled" do
    @source.set_merge_commit_title_setting(setting: Configurable::MergeCommitTitle::PR_TITLE, actor: @source.owner)

    assert_equal "#{@pull.title} (##{@pull.number})", @pull.default_merge_commit_title
  end

  test "default_merge_commit_title uses number and branch name if Use Merge Message settings enabled" do
    @source.set_merge_commit_title_setting(setting: Configurable::MergeCommitTitle::MERGE_MESSAGE, actor: @source.owner)

    assert_equal "Merge pull request ##{@pull.number} from bwalsh/topic", @pull.default_merge_commit_title
  end

  test "default_merge_commit_message uses the PR title if Use PR Title setting enabled" do
    @source.set_merge_commit_message_setting(setting: Configurable::MergeCommitMessage::PR_TITLE, actor: @source.owner)

    assert_equal @pull.title, @pull.default_merge_commit_message
  end

  test "default_merge_commit_message uses the PR body if Use PR Body setting enabled" do
    @source.set_merge_commit_message_setting(setting: Configurable::MergeCommitMessage::PR_BODY, actor: @source.owner)

    assert_equal PullRequest::CommitMessageWrapper.new(@pull.body).wrap, @pull.default_merge_commit_message
  end

  test "default_merge_commit_message correctly omits the PR body if Use PR Body setting enabled with omission tags" do
    GitHub.flipper[:omit_pr_body_commits].enable
    starting_tag = Configurable::MergeCommitMessage::PR_BODY_OMISSION_STARTING_TAG
    ending_tag = Configurable::MergeCommitMessage::PR_BODY_OMISSION_ENDING_TAG

    @source.set_merge_commit_message_setting(setting: Configurable::MergeCommitMessage::PR_BODY, actor: @source.owner)

    @pull.issue.update_attribute :body, <<~BODY
      <!-- Exclude from commit message -->
      REMOVE
      <!-- End of exclude from commit message -->
      Secretly
      <!-- Exclude from commit message -->
      REMOVE
      <!-- End of exclude from commit message -->
      Encoded message
      <!-- Exclude from commit message -->
      REMOVE
    BODY

    filtered_body = PullRequest::CommitMessageWrapper.new <<~BODY
      Secretly

      Encoded message
    BODY

    assert_equal filtered_body.wrap, @pull.default_merge_commit_message

    @pull.issue.update_attribute :body, <<~BODY
      Please don't remove me
      <!-- Exclude from commit message -->
      REMOVE ALL OF THIS
      And this too!
    BODY

    filtered_body = PullRequest::CommitMessageWrapper.new <<~BODY
       Please don't remove me
    BODY

    assert_equal filtered_body.wrap, @pull.default_merge_commit_message

    @pull.issue.update_attribute :body, <<~BODY


        Correctly trims this


    BODY

    filtered_body = PullRequest::CommitMessageWrapper.new <<~BODY
       Correctly trims this
    BODY

    assert_equal filtered_body.wrap, @pull.default_merge_commit_message
  end

  test "default_merge_commit_message is blank if Use Blank setting enabled" do
    @source.set_merge_commit_message_setting(setting: Configurable::MergeCommitMessage::BLANK, actor: @source.owner)

    assert_equal "", @pull.default_merge_commit_message
  end

  test "default_squash_commit_title uses PR title if multiple commits" do
    @source.set_squash_merge_commit_title_setting(setting: Configurable::SquashMergeCommitTitle::COMMIT_OR_PR_TITLE, actor: @source.owner)

    commit_to_repo(@source, branch: "master", file: "code.rb")

    assert_equal "#{@pull.title} (##{@pull.number})", @pull.default_squash_commit_title
  end

  test "can squash commits during merge with required status checks" do
    @source.reset_refs

    protected_branch = create(:protected_branch, repository: @source, creator: @source.owner, required_status_checks_enforcement_level: :everyone, strict_required_status_checks_policy: false)
    protected_branch.replace_status_contexts(%w[ci/janky])

    create :status, repository: @source, creator: @ari, sha: @pull.head_sha, context: "ci/janky", state: "success"

    assert @pull.behind_base?, "pull is not behind base"

    status, new_sha = @pull.merge(@ari, method: :squash)

    @source.reload
    @pull.reload

    assert_equal true, status, "pull#merge failed"
    assert_equal @source.ref_to_sha("master"), new_sha
    assert @pull.merged?, "pull is not merged"
  end
end
