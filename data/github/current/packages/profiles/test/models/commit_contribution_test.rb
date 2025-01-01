# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitContributionTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  fixtures do
    GitHub.flipper[:contributors_testing_use_no_merges].disable
    GitHub.flipper[:contributors_testing_skip_bots].disable

    @pages = create(:repository)
    @owner = create :user, plan: "medium"
    @facebox = create :repository, owner: @owner

    @sr = create :user, email: "simon@rozet.name"
    @rt = create :user, email: "rtomayko@gmail.com"
    @cw = create :user, email: "chris@ozmm.org"
    @cy = create :user, email: "chuyeow@gmail.com"
    @generic_user = create :user, email: "defunkt@example.com"

    @cw_repo    = create(:repository, owner: @cw)
    @cw_repo2   = create(:repository, owner: @cw)
  end

  setup do
    example_repo :pages, @pages
    example_repo :defunkt_facebox, @facebox
    example_repo :simple, @cw_repo
    example_repo :readmes, @cw_repo2

    @before = "2b862cbcbe8c8ead1549215240cb53ce272f73f9"
    @after  = "4598049ca87a10042263b2ccff24db1be5ebbfba"
  end

  test "queues a job to track pushes to tracked branches" do
    ref_update = stub(
      repository: @facebox,
      before: @before,
      after: @after,
      ref: "refs/heads/#{@facebox.default_branch}",
      pusher: @user,
      branch_name: @facebox.default_branch
    )
    assert_enqueued_jobs 1, only: [ContributionsTrackPushJob] do
      CommitContribution.track_push(ref_update: ref_update)
    end
  end

  test "does not queue a job to track pushes to untracked branches" do
    ref_update = stub(
      repository: @facebox,
      before: @before,
      after: @after,
      ref: "refs/heads/feature-branch",
      pusher: @user,
      branch_name: "feature-branch"
    )
    assert_enqueued_jobs 0, only: [ContributionsTrackPushJob] do
      CommitContribution.track_push(ref_update: ref_update)
    end
  end

  test "tracks a valid push" do
    assert_equal 0, @facebox.commit_contributions.count
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after
    assert_equal 9, CommitContribution.track_push!(push)
    assert @facebox.commit_contributions.count > 0
  end

  test "does not track a push without a repo" do
    push = build :push, repository: nil, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after
    assert_equal 0, CommitContribution.track_push!(push)
  end

  test "does not track a push to an untracked branch" do
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/feature-branch", before: @before, after: @after
    assert_equal 0, CommitContribution.track_push!(push)
  end

  test "does not track a push to a fork" do
    forked = create(:fork_repository, forker: @sr, fork_repo: @facebox, from_example: :defunkt_facebox)

    push = create :push, repository: forked, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after

    assert_equal 0, CommitContribution.track_push!(push)
  end

  test "counts both commit authors and co-authors if feature flag is enabled on repository" do
    assert_equal 0, @facebox.commit_contributions.count
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after
    same_day_commits = push.commits[5..7]
    other_day_commit = push.commits[10]
    [*same_day_commits, other_day_commit].each do |commit|
      commit.author_emails |= [@sr.email]
    end
    CommitContribution.track_push!(push)
    cw_contribs = @facebox.commit_contributions.where(user_id: @cw.id)
    assert_equal 18, cw_contribs.sum(:commit_count)
    sr_contribs = @facebox.commit_contributions.where(user_id: @sr.id)
    assert_equal 2, sr_contribs.count
    assert_equal 3, sr_contribs.first.commit_count
    assert_equal 1, sr_contribs.second.commit_count
    assert_equal push.commits[5].contributed_on, sr_contribs.first.committed_date
    assert_equal push.commits[10].contributed_on, sr_contribs.second.committed_date
  end

  test "ignores commits with generic email addresses" do
    assert_equal 0, @facebox.commit_contributions.count
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after
    CommitContribution.track_push!(push)
    assert @facebox.commit_contributions.none? { |cc| cc.user == @generic_user }
  end if GitHub.email_detect_generic_domains?

  test "ignores a push for a deleted repository" do
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      @facebox.remove(@owner)
    end

    assert_nil Repositories::Public.find_active(@facebox.id)

    CommitContribution.track_push!(push)
  end

  test "updates summaries from a push for a repository with summaries when the update flag is enabled" do
    GitHub.flipper[:update_existing_commit_contribution_summaries].enable
    @facebox.disable_feature(:commit_contribution_summaries)

    create(
      :commit_contribution_summary,
      repository: @facebox,
      user: @cw,
      year: 2024,
      counts: Array.new(365, 0).unshift(42)
    )

    push = create :push, repository: @facebox, pusher: @cw,
      ref: "refs/heads/master", before: @before, after: @after
    counts_by_date = CommitContribution.grouped_commit_counts_for_push(push, user: @cw)[@cw]
    expected_rows = counts_by_date.map do |date, count|
      [@cw.id, @facebox.id, date, count, "NOW()", "NOW()"]
    end

    refute_empty CommitContributionSummary.where(repository: @facebox)

    CommitContribution.expects(:update_commit_contribution_summaries).once.with(
      repository: @facebox,
      rows: expected_rows
    )
    BackfillCommitContributionSummariesJob.expects(:perform_later).never

    CommitContribution.track_push!(push)
  end

  test "does not update summaries from a push for a repository with summaries when the update flag is disabled" do
    GitHub.flipper[:update_existing_commit_contribution_summaries].disable
    @facebox.disable_feature(:commit_contribution_summaries)

    create(
      :commit_contribution_summary,
      repository: @facebox,
      user: @cw,
      year: 2024,
      counts: Array.new(365, 0).unshift(42)
    )

    push = create :push, repository: @facebox, pusher: @cw,
      ref: "refs/heads/master", before: @before, after: @after
    counts_by_date = CommitContribution.grouped_commit_counts_for_push(push, user: @cw)[@cw]

    refute_empty CommitContributionSummary.where(repository: @facebox)

    CommitContributionSummary.expects(:update_from_push).never
    BackfillCommitContributionSummariesJob.expects(:perform_later).never

    CommitContribution.track_push!(push)
  end

  test "does not update summaries from a push for a repository with no summaries when the update flag is enabled" do
    GitHub.flipper[:update_existing_commit_contribution_summaries].enable
    GitHub.flipper[:backfill_missing_commit_contribution_summaries].disable
    @facebox.disable_feature(:commit_contribution_summaries)

    push = create :push, repository: @facebox, pusher: @cw,
      ref: "refs/heads/master", before: @before, after: @after
    counts_by_date = CommitContribution.grouped_commit_counts_for_push(push, user: @cw)[@cw]

    assert_empty CommitContributionSummary.where(repository: @facebox)

    CommitContributionSummary.expects(:update_from_push).never
    BackfillCommitContributionSummariesJob.expects(:perform_later).never

    CommitContribution.track_push!(push)
  end

  test "backfills summaries from a push for a repository with no summaries when the flag is enabled" do
    GitHub.flipper[:backfill_missing_commit_contribution_summaries].enable

    push = create :push, repository: @facebox, pusher: @cw,
      ref: "refs/heads/master", before: @before, after: @after

    assert_empty CommitContributionSummary.where(repository: @facebox)

    CommitContributionSummary.expects(:update_from_push).never
    BackfillCommitContributionSummariesJob.expects(:perform_later).once.with(@facebox.id)

    CommitContribution.track_push!(push)
  end

  test "does not backfill summaries from a push for a repository with no summaries when the flag is enabled" do
    GitHub.flipper[:backfill_missing_commit_contribution_summaries].disable

    push = create :push, repository: @facebox, pusher: @cw,
      ref: "refs/heads/master", before: @before, after: @after

    assert_empty CommitContributionSummary.where(repository: @facebox)

    CommitContributionSummary.expects(:update_from_push).never
    BackfillCommitContributionSummariesJob.expects(:perform_later).never

    CommitContribution.track_push!(push)
  end
  test "updates summaries from a push for a repository with summaries when the flag is enabled" do
    @facebox.enable_feature(:commit_contribution_summaries)

    create(
      :commit_contribution_summary,
      repository: @facebox,
      user: @cw,
      year: 2024,
      counts: Array.new(365, 0).unshift(42)
    )

    push = create :push, repository: @facebox, pusher: @cw,
      ref: "refs/heads/master", before: @before, after: @after
    counts_by_date = CommitContribution.grouped_commit_counts_for_push(push, user: @cw)[@cw]
    expected_rows = counts_by_date.map do |date, count|
      [@cw.id, @facebox.id, date, count, "NOW()", "NOW()"]
    end

    refute_empty CommitContributionSummary.where(repository: @facebox)

    CommitContribution.expects(:update_commit_contribution_summaries).once.with(
      repository: @facebox,
      rows: expected_rows
    )
    BackfillCommitContributionSummariesJob.expects(:perform_later).never

    CommitContribution.track_push!(push)
  end

  test "excludes users without pull access when updating summaries from a push" do
    private_repo = create(:private_repository, owner: @cw, from_example: :simple)
    private_repo.enable_feature(:commit_contribution_summaries)

    other_user = create(:user)

    create(
      :commit_contribution_summary,
      repository: private_repo,
      user: @cw,
      year: 2023,
      counts: Array.new(365, 0).unshift(42)
    )

    CommitContribution.stubs(:grouped_commit_counts_for_push).returns({
      @cw => {
        Date.new(2024, 1, 1) => 42
      },
      other_user => {
        Date.new(2024, 1, 1) => 42
      }
    })

    push = create :push, repository: private_repo, pusher: @cw,
      ref: "refs/heads/master", before: @before, after: @after
    CommitContribution.track_push!(push)

    assert CommitContributionSummary.where(user: @cw, repository: private_repo, year: 2024).exists?, "Summary from user with access should exist"
    refute CommitContributionSummary.where(user: other_user, repository: private_repo, year: 2024).exists?, "Summary from user without access should not exist"
  end

  test "does not update summaries from a push for a repository with summaries when the flags are disabled" do
    GitHub.flipper[:update_existing_commit_contribution_summaries].disable
    @facebox.disable_feature(:commit_contribution_summaries)

    create(
      :commit_contribution_summary,
      repository: @facebox,
      user: @cw,
      year: 2024,
      counts: Array.new(365, 0).unshift(42)
    )

    push = create :push, repository: @facebox, pusher: @cw,
      ref: "refs/heads/master", before: @before, after: @after

    refute_empty CommitContributionSummary.where(repository: @facebox)

    CommitContributionSummary.expects(:update_from_push).never
    BackfillCommitContributionSummariesJob.expects(:perform_later).never

    CommitContribution.track_push!(push)
  end

  test "ignores non-master branches" do
    CommitContribution.backfill!(@facebox)

    commits = @cy.commit_contributions.where(repository_id: @facebox.id)
    assert_equal 0, commits.sum(:commit_count)
  end

  test "cares about gh-pages too" do
    CommitContribution.backfill!(@pages)

    commits = @rt.commit_contributions.where(repository_id: @pages.id)
    assert_equal 5, commits.sum(:commit_count)

    commits = @sr.commit_contributions.where(repository_id: @pages.id)
    assert_equal 6, commits.sum(:commit_count)
  end

  test "builds for one user" do
    CommitContribution.backfill_user!(@pages, @rt)

    commits = @rt.commit_contributions.where(repository_id: @pages.id)
    assert_equal 5, commits.sum(:commit_count)

    commits = @sr.commit_contributions.where(repository_id: @pages.id)
    assert_equal 0, commits.sum(:commit_count)
  end

  test "skips user backfill when the user does not have pull access to the repo" do
    private_repo = create(:private_repository, owner: @owner, from_example: :defunkt_facebox)
    private_repo.add_member(@cw)
    CommitContribution.backfill!(private_repo, true)
    private_repo.remove_member(@cw)

    assert CommitContribution.for_repository(private_repo).for_user(@cw).exists?
    refute private_repo.pullable_by?(@cw)

    CommitContribution.expects(:track_push!).never
    CommitContribution.backfill_user!(private_repo, @cw)
    refute CommitContribution.for_repository(private_repo).for_user(@cw).exists?
  end

  test "includes summaries when backfilling for a user when the summary feature flag is enabled" do
    @facebox.enable_feature(:commit_contribution_summaries)

    CommitContribution.backfill_user!(@facebox, @cw)

    assert_summaries_match_contributions(@facebox)
  end

  test "includes summaries when backfilling for a user when the update feature flag is enabled and summaries exist" do
    GitHub.flipper[:update_existing_commit_contribution_summaries].enable

    create(:commit_contribution_summary, repository: @facebox)
    CommitContribution.backfill_user!(@facebox, @cw)

    assert_summaries_match_contributions(@facebox)
  end

  test "does not include summaries when backfilling for a user when the update feature flag is enabled and no summaries exist" do
    @facebox.disable_feature(:commit_contribution_summaries)
    GitHub.flipper[:update_existing_commit_contribution_summaries].enable

    CommitContribution.backfill_user!(@facebox, @cw)

    assert_empty CommitContributionSummary.for_repository(@facebox)
  end

  test "does not include summaries when backfilling for a user when all summary feature flags are disabled" do
    @facebox.disable_feature(:commit_contribution_summaries)
    GitHub.flipper[:update_existing_commit_contribution_summaries].disable

    CommitContributionSummary.expects(:backfill_repository).never

    CommitContribution.backfill_user!(@facebox, @cw)
  end

  test "excludes users without pull access when backfilling" do
    private_repo = create(:private_repository, owner: @cw, from_example: :simple)
    private_repo.enable_feature(:commit_contribution_summaries)

    authorized_user = create(:user, email: "technoweenie@gmail.com")
    private_repo.add_member(authorized_user)
    unauthorized_user = create(:user, email: "rsanheim@gmail.com")

    CommitContribution.backfill!(private_repo, true)

    refute_nil CommitContributionSummary.find_by(repository: private_repo, user: authorized_user), "Summary from user with access should exist"
    assert_nil CommitContributionSummary.find_by(repository: private_repo, user: unauthorized_user), "Summary from user without access should not exist"
  end

  test "handles email case sensitivity" do
    @rt.primary_user_email.update_column :email, "RTomayko@GMail.com"
    CommitContribution.backfill_user!(@pages, @rt)

    commits = @rt.commit_contributions.where(repository_id: @pages.id)
    assert_equal 5, commits.sum(:commit_count)

    commits = @sr.commit_contributions.where(repository_id: @pages.id)
    assert_equal 0, commits.sum(:commit_count)
  end

  test "doesn't dupe stats when gh-pages is master branch" do
    example_repo :pages, @pages
    @pages.update_default_branch("gh-pages")

    CommitContribution.backfill!(@pages)

    commits = @rt.commit_contributions.where(repository_id: @pages.id)
    assert_equal 3, commits.sum(:commit_count)

    commits = @sr.commit_contributions.where(repository_id: @pages.id)
    assert_equal 5, commits.sum(:commit_count)
  end

  test "runs backfill job properly" do
    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    commits = @cw.commit_contributions.where(repository_id: @facebox.id)
    assert_equal 21, commits.sum(:commit_count)
  end

  test "runs backfill job with reset properly" do
    original_commit =
      CommitContribution.create!(
        repository: @facebox,
        user: @cw,
        committed_date: Time.now.to_date,
      )

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox, reset = true) }

    commits = @cw.commit_contributions.where(repository_id: @facebox.id)
    assert_equal 21, commits.sum(:commit_count)
    assert !commits.map(&:id).include?(original_commit.id)
  end

  test "knows if it should backfill" do
    assert CommitContribution.backfill?(@facebox)

    CommitContribution.backfill!(@facebox)
    commits = @cw.commit_contributions.where(repository_id: @facebox.id)
    assert_equal 21, commits.sum(:commit_count)

    assert !CommitContribution.backfill?(@facebox)
  end

  test "doesn't double backfill" do
    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }
    commits = @cw.commit_contributions.where(repository_id: @facebox.id)
    assert_equal 21, commits.sum(:commit_count)

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }
    commits = @cw.commit_contributions.where(repository_id: @facebox.id)
    assert_equal 21, commits.sum(:commit_count)

    CommitContribution.backfill!(@facebox)
    commits = @cw.commit_contributions.where(repository_id: @facebox.id)
    assert_equal 21, commits.sum(:commit_count)
  end

  test "backfills from scratch with reset" do
    CommitContribution.backfill!(@facebox)
    original_commits =
      @cw.commit_contributions.where(repository_id: @facebox.id)
    original_commit_ids = original_commits.map(&:id)
    assert_equal 21, original_commits.sum(:commit_count)

    @facebox.reload
    CommitContribution.backfill!(@facebox, reset = true)
    commits = @cw.commit_contributions.where(repository_id: @facebox.id)
    assert_equal 21, commits.sum(:commit_count)

    assert !original_commit_ids.include?(commits.last.id)
  end

  test "includes summaries when backfilling when the summary feature flag is enabled" do
    @facebox.enable_feature(:commit_contribution_summaries)

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    assert_summaries_match_contributions(@facebox)
  end

  test "adds summary counts across pushes when backfilling" do
    @facebox.enable_feature(:commit_contribution_summaries)

    # The "split_oid" commit here is in the middle of several commits from @cw on 2008-03-11
    head_oid = @facebox.ref_to_sha("master")
    split_oid = "42c23f435ee021ee30af912b112bc90980f661e7"
    ignore_merge_commits = @facebox.feature_enabled?(:contributors_testing_use_no_merges)
    commits = @facebox.commits.paged_history(head_oid, 1, 500, nil, ignore_merge_commits)
    split_point = commits.find_index { |c| c.oid == split_oid }
    batch1 = commits[0..split_point - 1]
    batch2 = commits[split_point..]

    @facebox.commits.stubs(:paged_history).returns(batch1, batch2, [])

    CommitContribution.backfill!(@facebox)

    assert summary = CommitContributionSummary.find_by(repository: @facebox, user: @cw, year: 2008)
    split_date = Date.new(2008, 3, 11)
    expected_count = ignore_merge_commits ? 5 : 6
    assert_equal expected_count, T.must(summary).counts[split_date.yday - 1]
  end

  test "adds summaries across years when backfilling" do
    owner = create(:user, email: "technoweenie@gmail.com")
    repo = create(:repository, owner: owner, from_example: :branch_and_tag_refs)
    repo.enable_feature(:commit_contribution_summaries)

    CommitContribution.backfill!(repo)

    refute_nil CommitContributionSummary.find_by(repository: repo, year: 2010)
    refute_nil CommitContributionSummary.find_by(repository: repo, year: 2014)
  end

  test "includes summaries when backfilling when the update feature flag is enabled and summaries exist" do
    GitHub.flipper[:update_existing_commit_contribution_summaries].enable

    create(:commit_contribution_summary, repository: @facebox)
    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    assert_summaries_match_contributions(@facebox)
  end

  test "does not include summaries when backfilling when the update feature flag is enabled and no summaries exist" do
    @facebox.disable_feature(:commit_contribution_summaries)
    GitHub.flipper[:update_existing_commit_contribution_summaries].enable

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    assert_empty CommitContributionSummary.for_repository(@facebox)
  end

  test "does not include summaries when backfilling when all summary feature flags are disabled" do
    @facebox.disable_feature(:commit_contribution_summaries)
    GitHub.flipper[:update_existing_commit_contribution_summaries].disable

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    assert_empty CommitContributionSummary.for_repository(@facebox)
  end

  test "tracks pushes to mirrors" do
    @facebox.create_mirror url: "http://example.org/facebox.git"
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    commits = @cw.commit_contributions.where(repository_id: @facebox.id)
    assert_equal 21, commits.sum(:commit_count)
  end

  test "doesn't track pushes to forks" do
    forked = create(:fork_repository, forker: @sr, fork_repo: @facebox, from_example: :defunkt_facebox)

    push = create :push, repository: forked, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    commits = @cw.commit_contributions.where(repository_id: forked.id)
    assert_equal 0, commits.sum(:commit_count)
  end

  test "doesn't track pushes to private repos by people who can't access them" do
    @facebox.update! private: true
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    commits = @cw.commit_contributions.where(repository_id: @facebox.id)
    assert_equal 0, commits.sum(:commit_count)
  end

  test "removes commit contributions when a repository is deleted" do
    CommitContribution.backfill_user!(@pages, @rt)

    commits = @rt.commit_contributions.where(repository_id: @pages.id)
    assert_equal 5, commits.sum(:commit_count)

    pages_id = @pages.id

    only = [DeleteDependentRecordsJob, RepositoryOrchestrationJob]
    perform_enqueued_jobs(only: only) do
      @pages.remove(@rt)

      # contributions are deleted when the repo is deleted from the repository table
      # which might be at delete time if we are archiving or at purge time if we are soft-deleting.
      @pages.purge(synchronous: true)
    end

    commits = CommitContribution.for_repository(pages_id)
    assert_equal 0, commits.size
  end

  test "ghost contribution exists if no contributors were found during backfill" do
    CommitContribution.backfill!(@cw_repo, reset = true)
    contributions = User.ghost.commit_contributions.where(repository_id: @cw_repo.id)

    assert_equal 1, contributions.count,
      "Expected 1 contribution for ghost in contributions timeline, but found #{contributions.count}"
    refute CommitContribution.backfill?(@cw_repo)
  end

  test "ghost contribution doesn't exist if contributors were found during backfill" do
    CommitContribution.backfill!(@facebox, reset = true)
    contributions = User.ghost.commit_contributions.where(repository_id: @facebox.id)

    assert_equal 0, contributions.count,
      "Expected 0 contribution for ghost in contributions timeline, but found #{contributions.count}"
    refute CommitContribution.backfill?(@facebox)
  end

  test "counts commits made before an email address was added to an account" do
    head_ref    = @cw_repo.ref_to_sha("master")
    committer   = User.new(email: "newuser@gmail.com", login: "Mr. New User")
    commit_data = { message: "test commit", committer: committer }

    commit = @cw_repo.commits.create(commit_data, head_ref) do |files|
      files.add("some-new-file.txt", "file contents")
    end

    @cw_repo.heads.find("master").update(commit.oid, @cw)

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@cw_repo) }

    commits = @cw.commit_contributions.where(repository_id: @cw_repo.id)
    assert_equal 0, commits.sum(:commit_count),
      "Expected 0 commits in contributions timeline, but found #{commits.sum(:commit_count)}"

    perform_enqueued_jobs(only: [UserContributionsBackfillJob]) do
      @cw.add_email("newuser@gmail.com")
    end

    commits = @cw.commit_contributions.where(repository_id: @cw_repo.id)
    assert_equal 1, commits.sum(:commit_count),
      "Expected 1 commit in contributions timeline, but found #{commits.sum(:commit_count)}"
  end

  test "count commits, across multiple repositories, made before an email address was added to an account" do
    committer   = User.new(email: "newuser@gmail.com", login: "Mr. New User")

    # create a new commit by new email address to @cw_repo
    head_ref    = @cw_repo.ref_to_sha("master")
    commit_data = { message: "test commit", committer: committer }
    commit = @cw_repo.commits.create(commit_data, head_ref) do |files|
      files.add("some-new-file.txt", "file contents")
    end
    @cw_repo.heads.find("master").update(commit.oid, @cw)

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@cw_repo) }

    commits = @cw.commit_contributions.where(repository_id: @cw_repo.id)
    assert_equal 0, commits.sum(:commit_count),
      "Expected 0 commits in contributions timeline, but found #{commits.sum(:commit_count)}"

    # create a new commit by new email address to @cw_repo2
    head_ref    = @cw_repo2.ref_to_sha("master")
    commit_data = { message: "test commit", committer: committer }
    commit = @cw_repo2.commits.create(commit_data, head_ref) do |files|
      files.add("some-new-file.txt", "file contents")
    end
    @cw_repo2.heads.find("master").update(commit.oid, @cw)

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@cw_repo2) }

    commits = @cw.commit_contributions.where(repository_id: @cw_repo2.id)
    assert_equal 0, commits.sum(:commit_count),
      "Expected 0 commits in contributions timeline, but found #{commits.sum(:commit_count)}"

    perform_enqueued_jobs(only: [UserContributionsBackfillJob]) do
      @cw.add_email("newuser@gmail.com")
    end

    commits = @cw.commit_contributions.where(repository_id: @cw_repo.id)
    assert_equal 1, commits.sum(:commit_count),
      "Expected 1 commit in contributions timeline, but found #{commits.sum(:commit_count)}"

    commits = @cw.commit_contributions.where(repository_id: @cw_repo2.id)
    assert_equal 1, commits.sum(:commit_count),
      "Expected 1 commit in contributions timeline, but found #{commits.sum(:commit_count)}"
  end

  test "uses a single job to destroy large amounts of commit contributions" do
    repo = create(:repository)
    committers = Array.new(3) { create(:user) }
    101.times do |i|
      committers.each do |user|
        create :commit_contribution,
          repository: repo,
          user: user,
          committed_date: i.days.ago.to_date
      end
    end

    current_count = CommitContribution.for_repository(repo.id).count
    assert_equal 101 * 3, current_count,
      "Expected 303 commit contributions to have been created, but found #{current_count}"

    args = ["CommitContribution", repo.id, :repository, { inverse_relationship: true }]
    assert_enqueued_with job: DeleteDependentRecordsJob, args: args do
      repo.remove(repo.owner, synchronous: true)
      # contributions are deleted when the repo is deleted from the repository table
      repo.purge(synchronous: true)
    end
  end

  test "clears the RepoGraph cache when backfilling" do
    GitHub::RepoGraph.expects(:clear_cache).with(@pages, "contributors")
    CommitContribution.backfill!(@pages)
  end

  test "clears the RepoGraph cache when backfilling for a user" do
    GitHub::RepoGraph.expects(:clear_cache).with(@pages, "contributors")
    CommitContribution.backfill_user!(@pages, @rt)
  end

  test "gets the number of distinct contributors for a repo" do
    repo = create(:repository)
    committers = Array.new(4) { create(:user) }
    committers.each do |user|
      create :commit_contribution,
        repository: repo,
        user: user,
        committed_date: 1.day.ago.to_date
    end

    assert_equal 4, CommitContribution.contributors_count_for_repository(repo)
  end

  context ".order_by_commit_count" do
    test "from most to least committed" do
      repo_one = create(:repository, name: "repo1", owner: @sr)
      repo_two = create(:repository, name: "repo2", owner: @sr)

      create(:commit_contribution, repository: repo_one, user: @sr)
      create(:commit_contribution, repository: repo_two, user: @sr, commit_count: 10)

      repositories = CommitContribution.order_by_commit_count(@sr).map(&:repository)
      assert_equal [repo_two, repo_one], repositories
    end

    test "sums commit counts to determine order per repository" do
      repo_one = create(:repository, name: "repo1", owner: @sr)
      repo_two = create(:repository, name: "repo2", owner: @sr)

      create(:commit_contribution, repository: repo_one, committed_date: Date.today, user: @sr)
      create(:commit_contribution, repository: repo_two, committed_date: 4.days.ago, user: @sr, commit_count: 2)

      repositories = CommitContribution.order_by_commit_count(@sr).map(&:repository)
      assert_equal [repo_one, repo_two], repositories

      create(:commit_contribution, repository: repo_two, committed_date: 2.days.ago, user: @sr, commit_count: 4)
      repositories = CommitContribution.order_by_commit_count(@sr).map(&:repository)
      assert_equal [repo_two, repo_one], repositories
    end

    test "excludes rows with no commits from user" do
      repo_one = create(:repository, name: "repo1", owner: @sr)
      repo_two = create(:repository, name: "repo2", owner: @sr)

      create(:commit_contribution, repository: repo_one, user: @sr)

      repositories = CommitContribution.order_by_commit_count(@sr).map(&:repository)
      assert_equal [repo_one], repositories
    end

    test "excludes contributions from other users" do
      repo_one = create(:repository, name: "repo1", owner: @sr)
      repo_two = create(:repository, name: "repo2", owner: @sr)

      create(:commit_contribution, repository: repo_one, user: @sr)
      create(:commit_contribution, repository: repo_two, user: @rt)

      repositories = CommitContribution.order_by_commit_count(@sr).map(&:repository)
      assert_equal [repo_one], repositories
    end

    test "excludes commits from more than a year ago" do
      repo_one = create(:repository, name: "repo1", owner: @sr)
      repo_two = create(:repository, name: "repo2", owner: @sr)

      create(:commit_contribution, repository: repo_one, user: @sr)
      create(:commit_contribution, repository: repo_two, committed_date: 13.months.ago, user: @sr)

      repositories = CommitContribution.order_by_commit_count(@sr).map(&:repository)
      assert_equal [repo_one], repositories
    end
  end

  test "is deleted with repository" do
    contribution = create(:commit_contribution, repository: @pages, user: @pages.owner)
    other_contribution = create(:commit_contribution, repository: @facebox, user: @facebox.owner)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @pages
      config.expect_destroyed = [contribution]
      config.expect_not_destroyed = [other_contribution]
    end
  end

  def assert_summaries_match_contributions(repository)
    contributions_by_user = CommitContribution.where(repository: repository).group_by(&:user)
    contributions_by_user.each do |user, user_contributions|
      contributions_by_year = user_contributions.group_by { |cc| T.must(cc.committed_date).year }
      contributions_by_year.each do |year, year_contributions|
        dec31 = Date.new(year, 12, 31)
        expected_counts = year_contributions.each_with_object(Array.new(dec31.yday, 0)) do |cc, counts|
          counts[T.must(cc.committed_date).yday - 1] = cc.commit_count
        end

        assert summary = CommitContributionSummary.find_by(repository: repository, user: user, year: year), "Summary not found"
        assert_equal expected_counts, T.must(summary).counts, "Summary count mismatch"
      end
    end
  end
end
