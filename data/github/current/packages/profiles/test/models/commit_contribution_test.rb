# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitContributionTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  fixtures do
    disable_feature_flag(:contributors_testing_use_no_merges)
    disable_feature_flag(:contributors_testing_skip_bots)

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
    snapshot_spokesdb
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
    assert_equal 0, commit_contribution_count(repository: @facebox)
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after
    assert_equal 9, CommitContribution.track_push!(push)
    assert commit_contribution_count(repository: @facebox) > 0
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
    assert_equal 0, commit_contribution_count(repository: @facebox)
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after
    same_day_commits = push.commits[5..7]
    other_day_commit = push.commits[10]
    [*same_day_commits, other_day_commit].each do |commit|
      commit.author_emails |= [@sr.remove_shortcode(@sr.email)]
    end
    CommitContribution.track_push!(push)

    assert_equal 18, commit_contribution_count(repository: @facebox, user: @cw)
    assert_equal 4, commit_contribution_count(repository: @facebox, user: @sr)
    sr_contribs = commit_contributions(repository: @facebox, user: @sr)
    assert_equal 2, sr_contribs.count
    assert_equal 3, T.must(sr_contribs.first).commit_count
    assert_equal 1, T.must(sr_contribs.second).commit_count
    assert_equal push.commits[5].contributed_on, T.must(sr_contribs.first).committed_date
    assert_equal push.commits[10].contributed_on, T.must(sr_contribs.second).committed_date
  end

  test "ignores commits with generic email addresses" do
    assert_equal 0, commit_contribution_count(repository: @facebox)
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after
    CommitContribution.track_push!(push)
    assert commit_contributions(repository: @facebox).none? { |cc| cc.user == @generic_user }
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

  if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
    test "does not update summaries from a push when summaries are not enabled" do
      push = create :push, repository: @facebox, pusher: @cw,
        ref: "refs/heads/master", before: @before, after: @after
      counts_by_date = CommitContribution.grouped_commit_counts_for_push(push, user: @cw)[@cw]

      CommitContributionSummary.expects(:update_from_push).never

      CommitContribution.track_push!(push)
    end
  else
    test "updates summaries from a push when summaries are enabled" do
      push = create :push, repository: @facebox, pusher: @cw,
        ref: "refs/heads/master", before: @before, after: @after
      counts_by_date = CommitContribution.grouped_commit_counts_for_push(push, user: @cw)[@cw]
      expected_rows = counts_by_date.map do |date, count|
        [@cw.id, @facebox.id, date, count, "NOW()", "NOW()"]
      end

      CommitContribution.expects(:update_commit_contribution_summaries).once.with(
        repository: @facebox,
        rows: expected_rows
      )

      CommitContribution.track_push!(push)
    end
  end

  unless GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
    test "excludes users without pull access when updating summaries from a push" do
      private_repo = create(:private_repository, owner: @cw, from_example: :simple)

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

      refute_empty commit_contributions(repository: private_repo, user: @cw)
      assert_empty commit_contributions(repository: private_repo, user: other_user)
    end
  end

  test "ignores non-master branches" do
    CommitContribution.backfill!(@facebox)

    commits = CommitContribution.for_repository(@facebox).for_user(@cy)
    assert_equal 0, commits.sum(:commit_count)
  end

  test "cares about gh-pages too" do
    CommitContribution.backfill!(@pages)

    assert_equal 5, commit_contribution_count(user: @rt, repository: @pages)
    assert_equal 6, commit_contribution_count(user: @sr, repository: @pages)
  end

  test "builds for one user" do
    CommitContribution.backfill_user!(@pages, @rt)

    assert_equal 5, commit_contribution_count(user: @rt, repository: @pages)
    assert_equal 0, commit_contribution_count(user: @sr, repository: @pages)
  end

  test "skips user backfill when the user does not have pull access to the repo" do
    pullable_repo = create(:private_repository, :org_owned, from_example: :defunkt_facebox)
    member_org = pullable_repo.owner
    member_org.add_member(@cw)

    non_pullable_repo = create(:private_repository, :org_owned, from_example: :defunkt_facebox)

    assert pullable_repo.pullable_by?(@cw)
    CommitContribution.backfill!(pullable_repo, true)
    refute_empty commit_contributions(repository: pullable_repo, user: @cw)

    refute non_pullable_repo.pullable_by?(@cw)
    CommitContribution.expects(:track_push!).never
    CommitContribution.backfill_user!(non_pullable_repo, @cw)
    assert_empty commit_contributions(repository: non_pullable_repo, user: @cw)
  end

  if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
    test "does not include summaries when backfilling for a user when summaries are not enabled" do
      CommitContribution.backfill_user!(@facebox, @cw)

      assert_empty CommitContributionSummary.for_repository(@facebox)
    end
  else
    test "includes summaries when backfilling for a user when summaries are enabled" do
      CommitContribution.backfill_user!(@facebox, @cw)

      assert_summaries_match_contributions(@facebox)
    end
  end

  test "excludes users without pull access when backfilling" do
    authorized_user = create(:user, email: "technoweenie@gmail.com")
    unauthorized_user = create(:user, email: "rsanheim@gmail.com")

    private_repo = create(:private_repository, :org_owned, from_example: :simple)
    org = private_repo.owner
    org.add_member(authorized_user)

    assert private_repo.pullable_by?(authorized_user)
    refute private_repo.pullable_by?(unauthorized_user)

    CommitContribution.backfill!(private_repo, true)

    refute_empty commit_contributions(repository: private_repo, user: authorized_user), "Contributions from user with access should exist"
    assert_empty commit_contributions(repository: private_repo, user: unauthorized_user), "Contributions from user without access should not exist"

    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      assert_empty CommitContributionSummary.for_repository(private_repo).for_user(authorized_user), "Summary from user with access not should exist in non-summary-enabled environments"
    else
      refute_empty CommitContributionSummary.for_repository(private_repo).for_user(authorized_user), "Summary from user with access should exist in summary-enabled environments"
    end
    assert_empty CommitContributionSummary.for_repository(private_repo).for_user(unauthorized_user), "Summary from user without access should not exist"
  end

  test "clears existing contributions and summaries when backfilling" do
    contribution_date = Date.new(2023, 1, 1)

    existing_cw_cc = create(:commit_contribution, repository: @facebox, user: @cw, committed_date: contribution_date)
    existing_rt_cc = create(:commit_contribution, repository: @facebox, user: @rt, committed_date: contribution_date)
    existing_cw_summary = create(:commit_contribution_summary, repository: @facebox, user: @cw, year: 2023, counts: [1])
    existing_rt_summary = create(:commit_contribution_summary, repository: @facebox, user: @rt, year: 2023, counts: [1])

    CommitContribution.backfill!(@facebox, true)

    assert_empty CommitContribution.where(id: [existing_cw_cc.id, existing_rt_cc.id])
    assert_empty CommitContributionSummary.where(id: [existing_cw_summary.id, existing_rt_summary.id])

    assert_equal 21, commit_contribution_count(user: @cw, repository: @facebox)
    assert_equal 0, commit_contribution_count(user: @rt, repository: @facebox)
  end

  test "clears existing user contributions and summaries when backfilling a user" do
    contribution_date = Date.new(2023, 1, 1)

    existing_cw_cc = create(:commit_contribution, repository: @facebox, user: @cw, committed_date: contribution_date)
    existing_rt_cc = create(:commit_contribution, repository: @facebox, user: @rt, committed_date: contribution_date, commit_count: 42)
    existing_cw_summary = create(:commit_contribution_summary, repository: @facebox, user: @cw, year: 2023, counts: [1])
    existing_rt_summary = create(:commit_contribution_summary, repository: @facebox, user: @rt, year: 2023, counts: [42])

    CommitContribution.backfill_user!(@facebox, @cw)

    assert_nil CommitContribution.find_by(id: existing_cw_cc.id)
    refute_nil CommitContribution.find_by(id: existing_rt_cc.id)
    assert_nil CommitContributionSummary.find_by(id: existing_cw_summary.id)
    refute_nil CommitContributionSummary.find_by(id: existing_rt_summary.id)

    assert_equal 21, commit_contribution_count(user: @cw, repository: @facebox)
    assert_equal 42, commit_contribution_count(user: @rt, repository: @facebox)
  end

  test "clears existing contributions and summaries when backfilling a user without pull access" do
    private_repo = create(:private_repository, :org_owned, from_example: :defunkt_facebox)

    contribution_date = Date.new(2023, 1, 1)
    existing_cc = create(:commit_contribution, repository: private_repo, user: @cw, committed_date: contribution_date)
    existing_summary = create(:commit_contribution_summary, repository: private_repo, user: @cw, year: 2023, counts: [1])

    refute private_repo.pullable_by?(@cw)

    CommitContribution.backfill_user!(private_repo, @cw)

    assert_nil CommitContribution.find_by(id: existing_cc.id)
    assert_nil CommitContributionSummary.find_by(id: existing_summary.id)

    assert_empty CommitContribution.where(repository: private_repo, user: @cw)
    assert_empty CommitContributionSummary.where(repository: private_repo, user: @cw)
  end

  test "handles email case sensitivity" do
    # Ensure this works properly in multi-tenant enterprise mode, where email addresses
    # include the business's shortcode.
    email_with_shortcode = @rt.add_emu_shortcode_to_emails("RTomayko@GMail.com")
    @rt.primary_user_email.update_column :email, email_with_shortcode
    CommitContribution.backfill_user!(@pages, @rt)

    assert_equal 5, commit_contribution_count(user: @rt, repository: @pages)
    assert_equal 0, commit_contribution_count(user: @sr, repository: @pages)
  end

  test "doesn't dupe stats when gh-pages is master branch" do
    example_repo :pages, @pages
    @pages.update_default_branch("gh-pages")

    CommitContribution.backfill!(@pages)

    assert_equal 3, commit_contribution_count(user: @rt, repository: @pages)
    assert_equal 5, commit_contribution_count(user: @sr, repository: @pages)
  end

  test "runs backfill job properly" do
    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    assert_equal 21, commit_contribution_count(user: @cw, repository: @facebox)
  end

  test "runs backfill job with reset properly" do
    create(:commit_contribution, :with_summaries, repository: @facebox, user: @cw, committed_date: Time.now.to_date)

    original_commit_ids = {
      CommitContribution => CommitContribution.for_repository(@facebox).for_user(@cw).pluck(:id),
      CommitContributionSummary => CommitContributionSummary.for_repository(@facebox).for_user(@cw).pluck(:id),
    }
    assert_equal 5, commit_contribution_count(user: @cw, repository: @facebox)

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox, reset = true) }

    original_commit_ids.each do |klass, original_ids|
      assert_empty klass.where(id: original_ids)
    end
    assert_equal 21, commit_contribution_count(user: @cw, repository: @facebox)
  end

  test "knows if it should backfill" do
    assert CommitContribution.backfill?(@facebox)

    CommitContribution.backfill!(@facebox)
    assert_equal 21, commit_contribution_count(repository: @facebox, user: @cw)

    assert !CommitContribution.backfill?(@facebox)
  end

  test "doesn't double backfill" do
    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }
    assert_equal 21, commit_contribution_count(user: @cw, repository: @facebox)

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }
    assert_equal 21, commit_contribution_count(user: @cw, repository: @facebox)

    CommitContribution.backfill!(@facebox)
    assert_equal 21, commit_contribution_count(user: @cw, repository: @facebox)
  end

  test "backfills from scratch with reset" do
    CommitContribution.backfill!(@facebox)

    original_commit_ids = {
      CommitContribution => CommitContribution.for_repository(@facebox).for_user(@cw).pluck(:id),
      CommitContributionSummary => CommitContributionSummary.for_repository(@facebox).for_user(@cw).pluck(:id),
    }
    assert_equal 21, commit_contribution_count(user: @cw, repository: @facebox)

    @facebox.reload
    CommitContribution.backfill!(@facebox, reset = true)

    original_commit_ids.each do |klass, original_ids|
      assert_empty klass.where(id: original_ids)
    end
    assert_equal 21, commit_contribution_count(user: @cw, repository: @facebox)
  end

  if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
    test "does not include summaries when backfilling when summaries are not enabled" do
      perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

      assert_empty CommitContributionSummary.for_repository(@facebox)
    end
  else
    test "includes summaries when backfilling when summaries are enabled" do
      perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

      assert_summaries_match_contributions(@facebox)
    end
  end

  unless GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
    test "adds summary counts across pushes when backfilling" do
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

      CommitContribution.backfill!(repo)

      refute_nil CommitContributionSummary.find_by(repository: repo, year: 2010)
      refute_nil CommitContributionSummary.find_by(repository: repo, year: 2014)
    end
  end

  test "tracks pushes to mirrors" do
    @facebox.create_mirror url: "http://example.org/facebox.git"
    push = create :push, repository: @facebox, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    assert_equal 21, commit_contribution_count(user: @cw, repository: @facebox)
  end

  test "doesn't track pushes to forks" do
    forked = create(:fork_repository, forker: @sr, fork_repo: @facebox, from_example: :defunkt_facebox)

    push = create :push, repository: forked, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@facebox) }

    commits = CommitContribution.for_repository(forked).for_user(@cw)
    assert_equal 0, commits.sum(:commit_count)
  end

  test "doesn't track pushes to private repos by people who can't access them" do
    private_repo = create(:private_repository, :org_owned, from_example: :defunkt_facebox)
    push = create :push, repository: private_repo, pusher: @user,
      ref: "refs/heads/master", before: @before, after: @after

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(private_repo) }

    commits = CommitContribution.for_repository(private_repo).for_user(@cw)
    assert_equal 0, commits.sum(:commit_count)
  end

  test "removes commit contributions and summaries when a repository is deleted" do
    create(:commit_contribution, :with_summaries, repository: @pages, user: @rt)

    refute_empty CommitContribution.for_repository(@pages)
    refute_empty CommitContributionSummary.for_repository(@pages)

    pages_id = @pages.id

    only = [DeleteDependentRecordsJob, DestroyDependentRecordsJob, RepositoryOrchestrationJob]
    perform_enqueued_jobs(only: only) do
      @pages.remove(@rt)

      # contributions are deleted when the repo is deleted from the repository table
      # which might be at delete time if we are archiving or at purge time if we are soft-deleting.
      @pages.purge(synchronous: true)
    end

    assert_empty CommitContribution.for_repository(@pages)
    assert_empty CommitContributionSummary.for_repository(@pages)
  end

  test "ghost contribution exists if no contributors were found during backfill" do
    CommitContribution.backfill!(@cw_repo, reset = true)

    count = commit_contributions(user: User.ghost, repository: @cw_repo).count
    assert_equal 1, count, "Expected 1 contribution for ghost in contributions timeline, but found #{count}"
    refute CommitContribution.backfill?(@cw_repo)
  end

  test "ghost contribution doesn't exist if contributors were found during backfill" do
    CommitContribution.backfill!(@facebox, reset = true)

    count = commit_contribution_count(user: User.ghost, repository: @facebox)
    assert_equal 0, count, "Expected 0 contribution for ghost in contributions timeline, but found #{count}"
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

    commit_count = commit_contribution_count(user: @cw, repository: @cw_repo)
    assert_equal 0, commit_count, "Expected 0 commits in contributions timeline, but found #{commit_count}"

    perform_enqueued_jobs(only: [UserContributionsBackfillJob]) do
      email_with_shortcode = @cw.add_emu_shortcode_to_emails("newuser@gmail.com")
      @cw.add_email(email_with_shortcode)
    end

    commit_count = commit_contribution_count(user: @cw, repository: @cw_repo)
    assert_equal 1, commit_count, "Expected 1 commit in contributions timeline, but found #{commit_count}"
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

    commit_count = commit_contribution_count(user: @cw, repository: @cw_repo)
    assert_equal 0, commit_count, "Expected 0 commits in contributions timeline, but found #{commit_count}"

    # create a new commit by new email address to @cw_repo2
    head_ref    = @cw_repo2.ref_to_sha("master")
    commit_data = { message: "test commit", committer: committer }
    commit = @cw_repo2.commits.create(commit_data, head_ref) do |files|
      files.add("some-new-file.txt", "file contents")
    end
    @cw_repo2.heads.find("master").update(commit.oid, @cw)

    perform_enqueued_jobs(only: [ContributionsBackfillJob]) { CommitContribution.backfill(@cw_repo2) }

    commit_count = commit_contribution_count(user: @cw, repository: @cw_repo2)
    assert_equal 0, commit_count, "Expected 0 commits in contributions timeline, but found #{commit_count}"

    perform_enqueued_jobs(only: [UserContributionsBackfillJob]) do
      email_with_shortcode = @cw.add_emu_shortcode_to_emails("newuser@gmail.com")
      @cw.add_email(email_with_shortcode)
    end

    commit_count = commit_contribution_count(user: @cw, repository: @cw_repo)
    assert_equal 1, commit_count, "Expected 1 commit in contributions timeline, but found #{commit_count}"

    commit_count = commit_contribution_count(user: @cw, repository: @cw_repo2)
    assert_equal 1, commit_count, "Expected 1 commit in contributions timeline, but found #{commit_count}"
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
      create :commit_contribution, :with_summaries,
        repository: repo,
        user: user,
        committed_date: 1.day.ago.to_date
    end

    assert_equal 4, CommitContributions.domain.contributors_count_for_repository(repo)
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

  # Used by GitHub::RepoGraph::ContributionInsights.fetch_contributors_data for eg. the repository insights contributors graph
  context "repository_contribution_history" do
    test "returns a hash in GitHub::RepoGraph::ContributionInsights#fetch_contributors_data format" do
      expected_dates = {
        @owner.git_author_email => [],
        @generic_user.git_author_email => [],
      }

      # Give the owner a long contribution history
      1.upto(3) do |year|
        1.upto(12) do |month|
          contribution_date = Date.new(2020 + year, month, 1)
          create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: contribution_date, commit_count: 42)
          expected_dates[@owner.git_author_email] << contribution_date
        end
      end

      # Give the generic_user a short contribution history
      3.upto(6) do |month|
        contribution_date = Date.new(2022, month, 1)
        create(:commit_contribution, :with_summaries, repository: @facebox, user: @generic_user, committed_date: contribution_date, commit_count: 42)
        expected_dates[@generic_user.git_author_email] << contribution_date
      end

      users = [@owner, @generic_user]
      contribution_history = CommitContributions.domain.repository_contribution_history(repository: @facebox, users: users)
      commit_history = T.must(contribution_history[:commits])
      addition_history = T.must(contribution_history[:additions])
      deletion_history = T.must(contribution_history[:deletions])

      assert_same_elements [@owner.git_author_email, @generic_user.git_author_email], commit_history.keys
      assert_same_elements [@owner.git_author_email, @generic_user.git_author_email], addition_history.keys
      assert_same_elements [@owner.git_author_email, @generic_user.git_author_email], deletion_history.keys

      expected_owner_commits = expected_dates[@owner.git_author_email].inject({}) { |hash, date| hash.merge!(date.to_time.to_i => 42) }
      expected_owner_changes = expected_dates[@owner.git_author_email].inject({}) { |hash, date| hash.merge!(date.to_time.to_i => 0) }
      assert_equal expected_owner_commits, commit_history[@owner.git_author_email]
      assert_equal expected_owner_changes, addition_history[@owner.git_author_email]
      assert_equal expected_owner_changes, deletion_history[@owner.git_author_email]

      expected_generic_user_commits = expected_dates[@generic_user.git_author_email].inject({}) { |hash, date| hash.merge!(date.to_time.to_i => 42) }
      expected_generic_user_changes = expected_dates[@generic_user.git_author_email].inject({}) { |hash, date| hash.merge!(date.to_time.to_i => 0) }
      assert_equal expected_generic_user_commits, commit_history[@generic_user.git_author_email]
      assert_equal expected_generic_user_changes, addition_history[@generic_user.git_author_email]
      assert_equal expected_generic_user_changes, deletion_history[@generic_user.git_author_email]
    end

    test "limits results to specified users" do
      committed_date = Date.new(2024, 1, 1)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: committed_date)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @generic_user, committed_date: committed_date)

      contribution_history = CommitContributions.domain.repository_contribution_history(repository: @facebox, users: [@owner])

      assert_equal [@owner.git_author_email], T.must(contribution_history[:commits]).keys
      assert_equal [@owner.git_author_email], T.must(contribution_history[:additions]).keys
      assert_equal [@owner.git_author_email], T.must(contribution_history[:deletions]).keys
    end
  end

  # Used by GitHub::RepoGraph::ContributionInsights.fetch_commit_activity_data for eg. the repository insights commits graph
  context "repository_commit_activity" do
    test "returns a hash in GitHub::RepoGraph::ContributionInsights#fetch_commit_activity_data format" do
      today = Date.parse("2023-06-15")
      one_year_ago = today - 1.year

      # Give the owner a long contribution history
      contribution_dates = []
      1.upto(3) do |year|
        1.upto(12) do |month|
          date = Date.new(2020 + year, month, 1)
          if date > one_year_ago
            contribution_dates << date
            contribution_dates << date + 1.day
          end

          create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: date, commit_count: 42)
          create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: date + 1.day, commit_count: 42)
        end
      end

      # Give the generic_user a short contribution history
      overlap_dates = []
      6.upto(9) do |month|
        date = Date.new(2022, month, 1)
        overlap_dates << date if date > one_year_ago

        create(:commit_contribution, :with_summaries, repository: @facebox, user: @generic_user, committed_date: date, commit_count: 42)
      end

      # Expect counts from @owner on the first and second day of each month in range,
      # and overlapping counts from @generic on the first of September-November.
      expected_counts = contribution_dates.inject({}) { |hash, date| hash.merge!(date.to_time.to_i => 42) }
      overlap_dates.each { |date| expected_counts[date.to_time.to_i] += 42 }

      commit_activity = travel_to(today) do
        CommitContributions.domain.repository_commit_activity(repository: @facebox)
      end

      assert_equal expected_counts.to_a, commit_activity
    end
  end

  context "contributed_repo_ids" do
    test "returns the repository ids for which the user has contributions" do
      other_repo = create(:repository, owner: @owner)

      committed_date = Date.new(2022, 1, 1)

      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: committed_date)
      create(:commit_contribution, :with_summaries, repository: other_repo, user: @owner, committed_date: committed_date)

      contributed_repo_ids = CommitContributions.domain.contributed_repo_ids(user: @owner).sort
      assert_equal [@facebox.id, other_repo.id].sort, contributed_repo_ids
    end

    test "finds repos the user committed to before a given date" do
      other_repo = create(:repository, owner: @owner)

      committed_date1 = Date.new(2022, 1, 1)
      committed_date2 = Date.new(2023, 1, 1)

      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: committed_date1)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: committed_date2)
      create(:commit_contribution, :with_summaries, repository: other_repo, user: @owner, committed_date: committed_date2)

      prior_to = Date.new(2022, 6, 1)
      contributed_repo_ids = CommitContributions.domain.contributed_repo_ids(user: @owner, prior_to: prior_to)
      assert_equal [@facebox.id], contributed_repo_ids
    end

    test "finds repos the user committed to after a given date" do
      other_repo = create(:repository, owner: @owner)

      committed_date1 = Date.new(2022, 1, 1)
      committed_date2 = Date.new(2023, 1, 1)
      committed_date3 = Date.new(2024, 1, 1)

      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: committed_date1)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: committed_date2)
      create(:commit_contribution, :with_summaries, repository: other_repo, user: @owner, committed_date: committed_date3)

      since = Date.new(2023, 6, 1)
      contributed_repo_ids = CommitContributions.domain.contributed_repo_ids(user: @owner, since: since)
      assert_equal [other_repo.id], contributed_repo_ids
    end

    test "finds repos the user committed to between two dates" do
      too_early = create(:repository, owner: @owner)
      too_late = create(:repository, owner: @owner)
      just_right = create(:repository, owner: @owner)

      committed_date1 = Date.new(2022, 1, 1)
      committed_date2 = Date.new(2023, 1, 1)
      committed_date3 = Date.new(2024, 1, 1)

      create(:commit_contribution, :with_summaries, repository: too_early, user: @owner, committed_date: committed_date1)
      create(:commit_contribution, :with_summaries, repository: too_late, user: @owner, committed_date: committed_date3)
      create(:commit_contribution, :with_summaries, repository: just_right, user: @owner, committed_date: committed_date2)

      since = Date.new(2022, 6, 1)
      prior_to = Date.new(2023, 6, 1)
      contributed_repo_ids = CommitContributions.domain.contributed_repo_ids(user: @owner, since: since, prior_to: prior_to)
      assert_equal [just_right.id], contributed_repo_ids
    end
  end

  context "contributed_user_ids" do
    test "returns the user ids for which the repository has contributions" do
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @generic_user)

      contributed_user_ids = CommitContributions.domain.contributed_user_ids(repository: @facebox)
      assert_same_elements [@owner.id, @generic_user.id], contributed_user_ids
    end

    test "scopes to a recent date range" do
      committed_date1 = Date.new(2022, 1, 1)
      committed_date2 = Date.new(2023, 1, 1)

      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: committed_date1)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: committed_date2)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @generic_user, committed_date: committed_date1)

      since = Date.new(2022, 6, 1)
      contributed_user_ids = CommitContributions.domain.contributed_user_ids(repository: @facebox, since: since)
      assert_same_elements [@owner.id], contributed_user_ids
    end

    test "scopes to specific users" do
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @generic_user)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: create(:user))

      contributed_user_ids = CommitContributions.domain.contributed_user_ids(repository: @facebox, users: [@owner, @generic_user])
      assert_same_elements [@owner.id, @generic_user.id], contributed_user_ids
    end

    test "excludes contributions from the ghost user" do
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: User.ghost)

      contributed_user_ids = CommitContributions.domain.contributed_user_ids(repository: @facebox, exclude_ghost: true)
      assert_same_elements [@owner.id].sort, contributed_user_ids
    end
  end

  context "has_recent_contributions?" do
    test "true when a repository on the list has recent contributions" do
      other_repo1, other_repo2 = create_list(:repository, 2, owner: @owner)

      committed_date1 = Date.new(2022, 1, 1)
      committed_date2 = Date.new(2023, 1, 1)

      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: committed_date1)
      create(:commit_contribution, :with_summaries, repository: other_repo1, user: @owner, committed_date: committed_date2)
      create(:commit_contribution, :with_summaries, repository: other_repo2, user: @owner, committed_date: committed_date1)

      assert CommitContributions.domain.has_recent_contributions?(repository_ids: [@facebox.id, other_repo1.id, other_repo2.id], since: Date.new(2022, 7, 1))
    end

    test "false when no repositories on the list have recent contributions" do
      other_repo1, other_repo2 = create_list(:repository, 2, owner: @owner)

      committed_date1 = Date.new(2022, 1, 1)
      committed_date2 = Date.new(2023, 1, 1)

      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: committed_date1)
      create(:commit_contribution, :with_summaries, repository: other_repo1, user: @owner, committed_date: committed_date2)
      create(:commit_contribution, :with_summaries, repository: other_repo2, user: @owner, committed_date: committed_date1)

      refute CommitContributions.domain.has_recent_contributions?(repository_ids: [@facebox.id, other_repo2.id], since: Date.new(2022, 7, 1))
      refute CommitContributions.domain.has_recent_contributions?(repository_ids: [@facebox.id, other_repo1.id, other_repo2.id], since: Date.new(2023, 7, 1))
    end
  end

  context "days_with_commits_count_by_repo" do
    test "returns the number of days with commits in the date range for each repository" do
      other_repo1, other_repo2 = create_list(:repository, 2, owner: @owner)
      repos = [@facebox, other_repo1, other_repo2]

      [2021, 2022, 2023].each do |year|
        repos.each do |repo|
          1.upto(12).each do |month|
            date = Date.new(year, month, 1)
            create(:commit_contribution, :with_summaries, repository: repo, user: @owner, committed_date: date)
          end

          1.upto(12).each do |month|
            date = Date.new(year, month, 4)
            create(:commit_contribution, :with_summaries, repository: repo, user: @generic_user, committed_date: date)
          end
        end
      end

      counts = CommitContributions.domain.days_with_commits_count_by_repo(user: @owner, since: Date.new(2022, 6, 15))
      assert_equal [@facebox.id, other_repo1.id, other_repo2.id].sort, counts.keys.sort
      assert_equal [18, 18, 18], counts.values
    end
  end

  context "last_contribution_date" do
    test "returns the most recent commit date" do
      date = Date.new(2023, 7, 1)

      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: date)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: date - 1.day)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: date - 1.year)

      assert_equal date, CommitContributions.domain.last_contribution_date(user: @owner, repository: @facebox)
    end

    test "returns nil when no contribution was found" do
      other_repo = create(:repository, owner: @owner)

      date = Date.new(2023, 7, 1)

      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: date)

      assert_nil CommitContributions.domain.last_contribution_date(user: @owner, repository: other_repo)
    end
  end

  context "first_contribution_date" do
    test "returns the oldest commit date" do
      date1 = Date.new(2007, 10, 19)
      date2 = Date.new(2011, 9, 26)

      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: date2)
      create(:commit_contribution, :with_summaries, repository: @facebox, user: @owner, committed_date: date1)

      assert_equal date1, CommitContributions.domain.first_contribution_date(user: @owner)
    end

    test "returns nil when no contribution was found" do
      assert_empty CommitContributionSummary.for_user(@owner)
      assert_nil CommitContributionSummary.first_contribution_date(user: @owner)
    end
  end

  # Returns commit contribution records from either CommitContribution or CommitContributionSummary
  # data depending on the environment.
  def commit_contributions(user: nil, repository: nil)
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      scope = CommitContribution.all
      scope = scope.for_user(user) if user
      scope = scope.for_repository(repository) if repository
      scope.to_a
    else
      repositories = repository.present? ? [repository] : nil
      CommitContributionSummary.commit_contributions_for(date_range: nil, user: user, repositories: repositories)
    end
  end

  # Counts commit contributions from either CommitContribution or CommitContributionSummary
  # data depending on the environment.
  def commit_contribution_count(user: nil, repository: nil)
    if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      scope = CommitContribution
      attr = :commit_count
    else
      scope = CommitContributionSummary
      attr = :total_count
    end

    scope = scope.for_user(user) if user
    scope = scope.for_repository(repository) if repository
    scope.sum(attr)
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
