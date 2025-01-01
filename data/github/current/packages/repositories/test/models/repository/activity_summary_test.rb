# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryActivitySummaryTest < GitHub::TestCase
  include AvatarHelper

  fixtures do
    Spokesd.enable_spokesd

    @source_owner = create(:user, login: "source-owner")
    @source       = create(:repository, owner: @source_owner, from_example: :pull_request_source)

    @fork_owner = create(:user, login: "fork-owner")
    @fork = create(:fork_repository, forker: @fork_owner, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue,
      user: @fork_owner,
      repository: @source,
      body: "hey @source-owner, this is @fork-owner. Thought we should work together.",
    )

    # Enable reflogs for the repository
    @source.rpc.config_store("core.logAllRefUpdates", true)
    @fork.rpc.config_store("core.logAllRefUpdates", true)

    # Generate a pull request
    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue,
    )
    @pull.save!
    @issue.pull_request = @pull

    issue_created_at   = 10.days.ago
    comment_created_at = 5.days.ago

    # Generate some issues
    5.times do
      issue = create(:issue,
        repository: @source,
        user: @source.owner,
        created_at: issue_created_at,
        body: "This references #the-milestone",
      )

      create(:issue_comment,
        issue: issue,
        repository: @source,
        user: @source_owner,
        created_at: comment_created_at,
      )
    end

    # Mark some issues closed
    @source.issues.open_issues[0..1].each { |i| i.close(@source_owner) }
    @source.issues.closed_issues.first.open(@user)

    # ensure the PR is open
    @pull.reload_issue.open(@source_owner)

    # Generate some commits as the owner
    ref = @source.heads.find("master")
    3.times do |i|
      ref.append_commit({ message: "test #{i}", committer: @source_owner }, @source_owner) do |files|
        files.add("some/great/path-#{i}.txt", "here's\nthree\nlines\n")
        files.remove("file#{i + 1}")
      end
    end

    # Generate some commits as the forker
    5.times do |i|
      ref.append_commit({ message: "test #{i}", committer: @fork_owner }, @fork_owner) do |files|
        files.add("some/great/path-#{i}.txt", "here's\nthree\nlines\n")
      end
    end

    @orphan = { name: "Orphan", email: "orphan@example.com" }
    ref.append_commit({ message: "test no user", committer: @orphan }, @source_owner) do |files|
      files.add("some/great/committer-with-unrecognizable-email.txt", "here's\nthree\nlines\n")
    end

    # Generate some commits on a non-master branch
    ref2 = @source.heads.create("feature-branch", ref.target_oid, @source_owner)
    5.times do |i|
      ref2.append_commit({ message: "working on feature #{i}", committer: @source_owner }, @source_owner) do |files|
        files.add("best/feature/ever-#{i}.txt", "here's\nthree\nlines\n")
      end
    end

    # Releases
    @release = create(:release,
      tag_name: "v1",
      state: :published,
      repository: @source,
      author: @source.owner,
    )
    @draft_release = create(:release,
      tag_name: "v2",
      state: :draft,
      repository: @source,
      author: @source.owner,
    )

    @spammy_user = create(:user, login: "spammer", spammy: false)
    @spammy_fork = create(:fork_repository, forker: @spammy_user, fork_repo: @source, from_example: :pull_request_fork)
    perform_enqueued_jobs(only: UpdateTableUserHiddenJob) { @spammy_user.mark_as_spammy }
    example_repo_snapshot
  end

  setup do
    example_repo_restore
    @summary = Repository::ActivitySummary.new(@source, viewer: @source.owner)
  end

  def summary_for(viewer)
    Repository::ActivitySummary.new(@source, viewer: viewer)
  end

  context ".new" do
    test "creates an activity summary with defaults" do
      assert_equal @summary.period, 1.week
      assert_equal @summary.since, @summary.now - @summary.period
      assert_equal "master", @summary.branch

      branch_head_oid = @source.heads.find("master").target_oid
      commit = @source.rpc.list_revision_history(branch_head_oid, until: @summary.since, limit: 1).first

      assert_equal "#{commit}...master", @summary.range
    end

    test "allows specifying a specific since time value" do
      Timecop.freeze(2014, 10, 15) do
        summary = Repository::ActivitySummary.new(@source, viewer: @source.owner, since: 5.days.ago)

        assert_equal 5.days.ago.to_i, summary.since.to_i
        assert_equal 5.days, summary.period
      end
    end

    test "allows specifying a specific period value" do
      Timecop.freeze(2014, 10, 15) do
        summary = Repository::ActivitySummary.new(@source, viewer: @source.owner, period: "daily")

        assert_equal 1.day.ago.to_i, summary.since.to_i
        assert_equal 1.day, summary.period
      end
    end
  end

  context "#committers" do
    test "returns a list of commit counts and committer information" do
      travel_to Date.parse("2020-12-19") do
        summary = Repository::ActivitySummary.new(@source, viewer: @source.owner)
        expected = [
          [8, @source_owner.git_author_name, @source_owner.git_author_email],
          [5, @fork_owner.git_author_name, @fork_owner.git_author_email],
          [2, @orphan[:name], @orphan[:email]],
        ]

        assert_equal expected, summary.committers
      end
    end
  end

  context "#committer_emails" do
    test "returns a list of commiter emails" do
      expect = [@source_owner.git_author_email, @fork_owner.git_author_email, @orphan[:email]]
      assert_equal expect, @summary.committer_emails
    end
  end

  test "#committer_users_by_email" do
    expect = { @source_owner.git_author_email => @source_owner, @fork_owner.git_author_email => @fork_owner }
    assert_equal expect, @summary.committer_users_by_email
  end

  test "#authors_with_commits" do
    travel_to Date.parse("2020-12-19") do
      summary = Repository::ActivitySummary.new(@source, viewer: @source.owner)
      authors = summary.authors_with_commits
      assert_equal 3, authors.size

      assert_equal @source_owner.login, authors[0][:login]
      assert_equal 8, authors[0][:commits]
      assert_equal HovercardHelper.user_hovercard_path(user_login: @source_owner.display_login), authors[0][:hovercard_url]

      assert_equal @fork_owner.login, authors[1][:login]
      assert_equal 5, authors[1][:commits]
      assert_equal HovercardHelper.user_hovercard_path(user_login: @fork_owner.display_login), authors[1][:hovercard_url]

      assert_equal gravatar_url_for(@orphan[:email], proxied: true), authors[2][:gravatar]
      assert_equal 2, authors[2][:commits]
      assert_nil authors[2][:hovercard_url]
    end
  end

  context "#commit_count" do
    test "returns the total commit count on all branches" do
      travel_to Date.parse("2020-12-19") do
        summary = Repository::ActivitySummary.new(@source, viewer: @source.owner)
        # 9 on master, 6 on feature-branch
        assert_equal 15, summary.commit_count
      end
    end
  end

  context "#default_branch_commit_count" do
    test "returns the total commit count on the default branch" do
      assert_equal 9, @summary.default_branch_commit_count
    end

    test "ignores conflicting refs when finding commit count on default branch" do
      original_commit_count = @summary.default_branch_commit_count!
      # Create a conflicting ref with master
      ref = @source.heads.find("master")
      @source.refs.create("refs/master", ref.target_oid, @source_owner)
      # Add a new commit to the true master
      ref.append_commit({ message: "test commit", committer: @source_owner }, @source_owner) do |files|
        files.add("howdy.txt", "howdy")
      end
      # The conflicting ref is ignored, so the new commit is counted
      assert_equal original_commit_count + 1, @summary.default_branch_commit_count!
    end

    test "returns 0 for a repo that has commits but no default branch" do
      empty_repo = create(:repository, owner: @source_owner, from_example: :empty)

      summary = empty_repo.activity_summary(viewer: @source_owner)

      assert_equal 0, summary.default_branch_commit_count
    end
  end

  context "#max_commits" do
    test "returns the largest commit count by a single user" do
      assert_equal 8, @summary.max_commits
    end

    test "returns 0 if there are no commits" do
      summary = Repository::ActivitySummary.new(@source, viewer: @source.owner, since: 1.week.from_now)

      assert_equal 0, summary.max_commits
    end
  end

  context "#commits_ratio" do
    test "returns the ratio of the given number to the largest commit count by a single user" do
      assert_equal 0.5, @summary.commits_ratio(4)
    end

    test "returns 0 if there are no commits" do
      summary = Repository::ActivitySummary.new(@source, viewer: @source.owner, since: 1.week.from_now)

      assert_equal 0, summary.commits_ratio(4)
    end
  end

  context "#diffstat" do
    test "returns a diff stat" do
      assert_equal({
        files: 9,
        deletions: 10,
        insertions: 18,
      }, @summary.diffstat)

      summary = Repository::ActivitySummary.new(@source, viewer: @source.owner, since: 1.week.from_now)

      assert_equal({
        files: 0,
        deletions: 0,
        insertions: 0,
      }, summary.diffstat)
    end

    test "works without ref logs" do
      @source.rpc.fs_delete(".git/logs/*")
      assert_equal({
        files: 9,
        deletions: 10,
        insertions: 18,
      }, @summary.diffstat)
    end
  end

  context "#pull_requests?" do
    test "returns true if the summary includes pull requests" do
      assert_predicate @summary, :pull_requests?
    end

    test "returns false if the summary does not include pull requests" do
      summary = Repository::ActivitySummary.new(@source, viewer: @source.owner, since: 1.week.from_now)

      refute_predicate summary, :pull_requests?
    end
  end

  test "closed pull requests are ignored" do
    pull_request_count = lambda do
      summary = Repository::ActivitySummary.new(@source, viewer: @source.owner)
      summary.new_pulls.count
    end

    assert_difference pull_request_count, -1 do
      @pull.reload_issue.close(@source_owner)
      @pull.reload
    end
  end

  context "#releases?" do
    test "returns true if the summary includes releases" do
      assert_predicate @summary, :releases?
    end

    test "returns false if the summary does not include pull requests" do
      summary = Repository::ActivitySummary.new(@source, viewer: @source.owner, since: 1.week.from_now)

      refute_predicate summary, :releases?
    end
  end

  context "#releases" do
    test "returns all releases for the summary" do
      assert_equal [@release], @summary.releases
    end
  end

  context "#issues?" do
    test "returns true if the summary includes issues" do
      assert_predicate @summary, :issues?
    end

    test "returns false if the summary does not include pull requests" do
      summary = Repository::ActivitySummary.new(@source, viewer: @source.owner, since: 1.week.from_now)

      refute_predicate summary, :issues?
    end
  end

  context "#user_count_for" do
    test "can return the number of distinct issue closers" do
      repo       = create(:repository)
      issues     = 3.times.map { create(:issue, repository: repo, user: create(:user)) }
      closer_one = create(:user)
      closer_two = create(:user)

      repo.add_member(closer_one)
      repo.add_member(closer_two)

      assert_equal 0, repo.issues.closed_issues.count
      assert_equal 0, Repository::ActivitySummary.new(repo, viewer: repo.owner).user_count_for(:closed_issues)

      issues[0].close(closer_one)
      assert_equal 1, repo.issues.closed_issues.count
      assert_equal 1, Repository::ActivitySummary.new(repo, viewer: repo.owner).user_count_for(:closed_issues)

      issues[1].close(closer_two)
      assert_equal 2, repo.issues.closed_issues.count
      assert_equal 2, Repository::ActivitySummary.new(repo, viewer: repo.owner).user_count_for(:closed_issues)

      issues[2].close(closer_two)
      assert_equal 3, repo.issues.closed_issues.count
      assert_equal 2, Repository::ActivitySummary.new(repo, viewer: repo.owner).user_count_for(:closed_issues)
    end
  end

  def create_issue(created_at)
    Timecop.freeze(created_at) do
      create(:issue, repository: @source, user: @source_owner)
    end
  end

  def create_pull_request(created_at)
    Timecop.freeze(created_at) do
      PullRequest.create_for(@source,
        base:  "master",
        head:  "#{@source_owner}:feature-branch",
        user:  @source_owner,
        issue: create_issue(created_at),
      )
    end
  end

  def create_spammy_issue(created_at)
    Timecop.freeze(created_at) do
      create(:issue, repository: @source, user: @spammy_user)
    end
  end

  def create_non_spammy_issue_on_spammy_repo(created_at)
    Timecop.freeze(created_at) do
      repo = create(:repository, owner: @spammy_user)
      create(:issue, repository: repo, user: @source_owner)
    end
  end

  def create_spammy_pull_request(created_at)
    Timecop.freeze(created_at) do
      PullRequest.create_for(@source,
        base:  "master",
        head:  "#{@spammy_user}:topic",
        user:  @spammy_user,
        issue: create_spammy_issue(created_at),
      )
    end
  end

  def create_issue_comment(issue, created_at)
    Timecop.freeze(created_at) do
      create(:issue_comment, issue: issue, repository: @source, user: @source_owner)
    end
  end

  def create_spammy_issue_comment(issue, created_at)
    Timecop.freeze(created_at) do
      create(:issue_comment, issue: issue, repository: @source, user: @spammy_user)
    end
  end

  def create_spammy_pull_request_review_comment(pull, created_at)
    Timecop.freeze(created_at) do
      create(:pull_request_review_comment, pull_request: pull, user: @spammy_user)
    end
  end

  context "#active" do
    test "returns a list containing tuples with pulse items and their comment counts" do
      active_items = @summary.active

      assert_equal active_items.size, 4
    end

    if GitHub.spamminess_check_enabled?
      test "does not include spammy issues" do
        spammy_issue = create_spammy_issue(10.days.ago)
        create_spammy_issue_comment(spammy_issue, 3.days.ago)

        active_items = summary_for(@source_owner).active

        issue, _ = active_items.find { |(item, _)| item == spammy_issue }
        assert_nil issue
      end

      test "does not include spammy issue comments in comment counts" do
        spammed_issue = create_issue(10.days.ago)
        create_issue_comment(spammed_issue, 3.days.ago)
        create_spammy_issue_comment(spammed_issue, 3.days.ago)

        active_items = summary_for(@source_owner).active

        _, comment_count = active_items.find { |(item, _)| item == spammed_issue }
        assert_equal comment_count, 1
      end

      test "does not include spammy pull requests" do
        spammy_pull = create_spammy_pull_request(10.days.ago)
        create_spammy_issue_comment(spammy_pull.issue, 3.days.ago)

        # Touch the pull request so it is seen as "active"
        # TODO: I believe this should not be required, is a bug and can
        #       lead to active pull requests not being part of the summary.
        Timecop.freeze(3.days.ago) { spammy_pull.touch }

        active_items = summary_for(@source_owner).active

        pull, _ = active_items.find { |(item, _)| item == spammy_pull }
        assert_nil pull
      end

      test "does not include spammy pull request review comments in comment counts" do
        spammed_pull = create_pull_request(10.days.ago)
        create_issue_comment(spammed_pull.issue, 3.days.ago)

        # Touch the pull request so it is seen as "active"
        # TODO: I believe this should not be required, is a bug and can
        #       lead to active pull requests not being part of the summary.
        Timecop.freeze(3.days.ago) { spammed_pull.touch }

        create_spammy_pull_request_review_comment(spammed_pull, 3.days.ago)

        active_items = summary_for(@source_owner).active

        _, comment_count = active_items.find { |(item, _)| item == spammed_pull }
        assert_equal comment_count, 1
      end

      context "when viewed by the spammy user" do
        test "includes spammy issues" do
          spammy_issue = create_spammy_issue(10.days.ago)
          create_spammy_issue_comment(spammy_issue, 3.days.ago)

          active_items = summary_for(@spammy_user).active

          issue, _ = active_items.find { |(item, _)| item == spammy_issue }
          assert_equal issue, spammy_issue
        end

        test "does include spammy issue comments in comment counts" do
          spammed_issue = create_issue(10.days.ago)
          create_issue_comment(spammed_issue, 3.days.ago)
          create_spammy_issue_comment(spammed_issue, 3.days.ago)

          active_items = summary_for(@spammy_user).active

          _, comment_count = active_items.find { |(item, _)| item == spammed_issue }
          assert_equal comment_count, 2
        end

        test "does include spammy pull requests" do
          spammy_pull = create_spammy_pull_request(10.days.ago)
          create_spammy_issue_comment(spammy_pull.issue, 3.days.ago)

          # Touch the pull request so it is seen as "active"
          # TODO: I believe this should not be required, is a bug and can
          #       lead to active pull requests not being part of the summary.
          Timecop.freeze(3.days.ago) { spammy_pull.touch }

          active_items = summary_for(@spammy_user).active

          pull, _ = active_items.find { |(item, _)| item == spammy_pull }
          assert_equal pull, spammy_pull
        end

        test "does include spammy pull request review comments in comment counts" do
          spammed_pull = create_pull_request(10.days.ago)
          create_issue_comment(spammed_pull.issue, 3.days.ago)

          # Touch the pull request so it is seen as "active"
          # TODO: I believe this should not be required, is a bug and can
          #       lead to active pull requests not being part of the summary.
          Timecop.freeze(3.days.ago) { spammed_pull.touch }

          create_spammy_pull_request_review_comment(spammed_pull, 3.days.ago)

          active_items = summary_for(@spammy_user).active

          _, comment_count = active_items.find { |(item, _)| item == spammed_pull }
          assert_equal comment_count, 2
        end
      end
    end
  end

  context "#new_issues" do
    if GitHub.spamminess_check_enabled?
      test "does not include spammy issues" do
        spammy_issue = create_spammy_issue(3.days.ago)

        refute_includes summary_for(@source_owner).new_issues, spammy_issue
      end

      test "does not include non-spammy issues on spammy repositories" do
        issue = create_non_spammy_issue_on_spammy_repo(3.days.ago)

        refute_includes Repository::ActivitySummary.new(issue.repository, viewer: @source_owner).new_issues, issue
      end

      context "when viewed by the spammy user" do
        test "does include spammy issues" do
          spammy_issue = create_spammy_issue(3.days.ago)

          assert_includes summary_for(@spammy_user).new_issues, spammy_issue
        end
      end
    end
  end

  context "#active_issues" do
    if GitHub.spamminess_check_enabled?
      test "does not include spammy issues" do
        spammy_issue = create_spammy_issue(10.days.ago)
        create_spammy_issue_comment(spammy_issue, 3.days.ago)

        refute_includes summary_for(@source_owner).active_issues, spammy_issue
      end

      context "when viewed by the spammy user" do
        test "does include spammy issues" do
          spammy_issue = create_spammy_issue(10.days.ago)
          create_spammy_issue_comment(spammy_issue, 3.days.ago)

          assert_includes summary_for(@spammy_user).active_issues, spammy_issue
        end
      end
    end
  end

  context "#new_pulls" do
    if GitHub.spamminess_check_enabled?
      test "does not include spammy pull requests" do
        spammy_pull = create_spammy_pull_request(3.days.ago)

        refute_includes summary_for(@source_owner).new_pulls, spammy_pull
      end

      context "when viewed by the spammy user" do
        test "does include spammy pull requests" do
          spammy_pull = create_spammy_pull_request(3.days.ago)

          assert_includes summary_for(@spammy_user).new_pulls, spammy_pull
        end
      end
    end
  end

  context "#closed_issues" do
    if GitHub.spamminess_check_enabled?
      test "does not include spammy issues" do
        spammy_issue = create_spammy_issue(3.days.ago)
        spammy_issue.close(@spammy_user)

        refute_includes summary_for(@source_owner).closed_issues, spammy_issue
      end

      context "when viewed by the spammy user" do
        test "does include spammy issues" do
          spammy_issue = create_spammy_issue(3.days.ago)
          spammy_issue.close(@spammy_user)

          assert_includes summary_for(@spammy_user).closed_issues, spammy_issue
        end
      end
    end
  end

  context "#merged_pulls" do
    test "sorts by merged_at" do
      other_fork_owner = create(:user, login: "other-fork-owner")
      other_fork = create(:fork_repository, forker: other_fork_owner, fork_repo: @source, from_example: :pull_request_fork)
      other_pull = PullRequest.create_for(@source,
        base: "master",
        head: "#{other_fork.user}:outsider-topic",
        user: other_fork_owner,
        title: "test outsider",
      )
      other_pull.save!
      another_pull = PullRequest.create_for(@source,
        base: "master",
        head: "#{other_fork.user}:ahead",
        user: other_fork_owner,
        title: "test ahead",
      )
      @pull.update!(merged_at: 3.days.ago)
      other_pull.update!(merged_at: 2.days.ago)
      another_pull.update!(merged_at: 4.days.ago)

      summary = summary_for(@source_owner)
      assert_equal [other_pull.id, @pull.id, another_pull.id], summary.merged_pulls.map(&:id)
    end
  end
end
