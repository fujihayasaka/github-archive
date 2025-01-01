# typed: true
# frozen_string_literal: true
require "test_helper"

class ReminderPullRequestFilterTest < GitHub::TestCase
  include GitHub::ReminderPullRequestFilterHelper

  fixtures do
    ## Public Repo

    @draft_pr = create(:pull_request, :disable_disk_access, draft: true, repository: @repo, user: @author, head_ref: random_ref)
    @pr_no_review_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)

    @pr_with_review_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: @pr_with_review_request, reviewer: @reviewer)

    @pr_with_approval = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: @pr_with_approval, reviewer: @reviewer)
    create_review_request_with_review(@pr_with_approval, reviewer: @reviewer2, submitted: :approved)

    ## Private Repo

    @private_draft_pr = create(:pull_request, :disable_disk_access, draft: true, repository: @private_repo, user: @author, head_ref: random_ref)
    @private_pr_no_review_request = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @author, head_ref: random_ref)

    @private_pr_with_review_request = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: @private_pr_with_review_request, reviewer: @reviewer)

    @private_pr_with_approval = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: @private_pr_with_approval, reviewer: @reviewer)
    create_review_request_with_review(@private_pr_with_approval, reviewer: @reviewer2, submitted: :approved)
  end

  # Helper for GitHub::ReminderPullRequestFilterHelper
  def pull_requests_with(private_repos: true, approval: false, draft: false, no_review_request: false, review_request: false)
    prs = []

    if private_repos
      prs << @private_draft_pr if draft
      prs << @private_pr_no_review_request if no_review_request
      prs << @private_pr_with_review_request if review_request
      prs << @private_pr_with_approval if approval
    end

    prs << @draft_pr if draft
    prs << @pr_no_review_request if no_review_request
    prs << @pr_with_review_request if review_request
    prs << @pr_with_approval if approval

    prs
  end

  # Helper for GitHub::ReminderPullRequestFilterHelper
  def pull_request_summary
    {
      @private_draft_pr.id => "Private Draft PR",
      @private_pr_no_review_request.id => "Private No Review Request PR",
      @private_pr_with_review_request.id => "Private W/ Review Request PR",
      @private_pr_with_approval.id => "Private Approved PR",
      @draft_pr.id => "Draft PR",
      @pr_no_review_request.id => "No Review Request PR",
      @pr_with_review_request.id => "W/ Review Request PR",
      @pr_with_approval.id => "Approved PR",
    }
  end

  context "filtering in batches", feature_enabled: :scheduled_reminders_process_job_with_batches do
    test "returns all expected PRs" do
      ReminderPullRequestFilter.batch_size = 1 # Force it to batch

      # NOTE: This filter will use all the repos (2) and return many pull requests
      reminder = create(:reminder, remindable: @org, teams: [@team2], require_review_request: false, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(
        expected: pull_requests_with(no_review_request: true, review_request: true, approval: true),
        actual: pull_requests
      )
    ensure
      ReminderPullRequestFilter.reset_batch_size
    end
  end

  context "sql indexes" do
    test "does not use FORCE INDEX", feature_enabled: :scheduled_reminders_process_job_skip_force_index do
      reminder = create(:reminder, remindable: @org, teams: [@team2], require_review_request: false, user: @org.admin)
      pull_requests, queries = log_cleaned_queries { ReminderPullRequestFilter.run(reminder).prs_for_review }

      assert queries.map(&:sql).none? { |sql| sql.include?("FORCE INDEX") }

      assert_pull_requests(
        expected: pull_requests_with(no_review_request: true, review_request: true, approval: true),
        actual: pull_requests
      )
    end

    test "uses FORCE INDEX", feature_disabled: :scheduled_reminders_process_job_skip_force_index do
      reminder = create(:reminder, remindable: @org, teams: [@team2], require_review_request: false, user: @org.admin)
      pull_requests, queries = log_cleaned_queries { ReminderPullRequestFilter.run(reminder).prs_for_review }

      assert queries.map(&:sql).any? { |sql| sql.include?("FORCE INDEX") }

      assert_pull_requests(
        expected: pull_requests_with(no_review_request: true, review_request: true, approval: true),
        actual: pull_requests
      )
    end
  end

  context "tracked_repositories" do
    test "includes everything when repos is empty, as this implicitly means everything" do
      reminder = create(
        :reminder,
        remindable: @org,
        repositories: [],
        user: @org.admin,
      )
      results = ReminderPullRequestFilter.run(reminder)
      assert_pull_requests(expected: pull_requests_with(review_request: true, approval: true), actual: results.prs_for_review)
    end

    test "includes everything when repos is empty, but not things from private repos when that's not supported" do
      @org.plan = "free"
      @org.save

      reminder = create(
        :reminder,
        remindable: @org,
        repositories: [],
        user: @org.admin,
      )

      results = ReminderPullRequestFilter.run(reminder)
      assert_pull_requests(
        expected: pull_requests_with(private_repos: false, review_request: true, approval: true),
        actual: results.prs_for_review,
      )
    end

    test "includes something when repos is not empty" do
      reminder = create(
        :reminder,
        remindable: @org,
        repositories: [@repo],
        user: @org.admin,
      )
      results = ReminderPullRequestFilter.run(reminder)
      assert_pull_requests(expected: pull_requests_with(private_repos: false, review_request: true, approval: true), actual: results.prs_for_review)
    end

    test "filters out non-active (deleted)" do
      reminder = create(
        :reminder,
        remindable: @org,
        repositories: [@repo],
        user: @org.admin,
      )

      # Change to deleted _after_ creating the reminder.
      # If we delete _before_ creating the reminder, then no repo links will be created and this will actually target all repos.
      @repo.update(active: nil)

      results = ReminderPullRequestFilter.run(reminder)
      assert_pull_requests(expected: [], actual: results.prs_for_review)
    end

    test "filters out archived" do
      reminder = create(
        :reminder,
        remindable: @org,
        repositories: [@repo],
        user: @org.admin,
      )

      @repo.update(maintained: false) # This means archived

      results = ReminderPullRequestFilter.run(reminder)
      assert_pull_requests(expected: [], actual: results.prs_for_review)
    end

    test "includes nothing when repos matches nothing" do
      reminder = create(
        :reminder,
        remindable: @org,
        repositories: [create(:repository, owner: @org)],
        user: @org.admin,
      )
      results = ReminderPullRequestFilter.run(reminder)
      assert_pull_requests(expected: [], actual: results.prs_for_review)
    end

    test "filters out things the installation doesnt have access to" do
      @installation.destroy

      # Create a new repo and an installation that doesnt have access to the @repo repo
      repo = create(:repository, owner: @org)
      installation = make_integration_installation(
        target: @org,
        integration: @app,
        repositories: [repo],
        permissions: { "metadata" => :read, "contents" => :read },
      )

      reminder = build(
        :reminder,
        remindable: @org,
        repositories: [@repo],
        user: @org.admin,
      )
      reminder.save(validate: false)

      # If the installation had access to more than `repo`, then this would not be empty
      results = ReminderPullRequestFilter.run(reminder)
      assert_pull_requests(expected: [], actual: results.prs_for_review)
    end
  end

  context "draft PRs" do
    test "includes draft PRs when ignore_draft_prs is false" do
      reminder = create(:reminder, remindable: @org, require_review_request: false, ignore_draft_prs: false, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      pull_requests_with(draft: true).each { |pr| assert_includes pull_requests, pr }
    end

    test "excludes draft PRs when ignore_draft_prs is true" do
      reminder = create(:reminder, remindable: @org, require_review_request: false, ignore_draft_prs: true, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: pull_requests_with(no_review_request: true, review_request: true, approval: true), actual: pull_requests)
    end
  end

  context "spammy authors" do
    test "excludes PRs from spammy authors" do
      reminder = create(
        :reminder,
        remindable: @org,
        user: @org.admin,
      )

      # Mark the author for all PRs as spammy
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        @author.safer_mark_as_spammy
      end

      results = ReminderPullRequestFilter.run(reminder)
      assert_pull_requests(expected: [], actual: results.prs_for_review)
    end if GitHub.spamminess_check_enabled?
  end

  context "require review request" do
    test "only includes PRs with review requests when require_review_request is true" do
      reminder = create(:reminder, remindable: @org, require_review_request: true, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: pull_requests_with(review_request: true, approval: true), actual: pull_requests)
    end

    test "excludes pull requests with a dismissed pending review request" do
      review_request = @pr_with_review_request.review_requests.first
      review_request.dismiss
      review_request.save!

      private_review_request = @private_pr_with_review_request.review_requests.first
      private_review_request.dismiss
      private_review_request.save!

      reminder = create(:reminder, remindable: @org, require_review_request: true, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(
        expected: pull_requests_with(approval: true),
        actual: pull_requests,
      )
    end

    test "includes PRs with no review requests when require_review_request is false" do
      reminder = create(:reminder, remindable: @org, require_review_request: false, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: pull_requests_with(no_review_request: true, review_request: true, approval: true), actual: pull_requests)
    end
  end

  context "require review request with remind author after reviews without team filtering" do
    test "excludes author reminder for pull requests with a dismissed review request" do
      # PR with no active pending requests
      review_request = @pr_with_review_request.review_requests.first
      review_request.dismiss
      review_request.save!
      assert @pr_with_review_request.review_requests.pending.not_dismissed.empty?

      private_review_request = @private_pr_with_review_request.review_requests.first
      private_review_request.dismiss
      private_review_request.save!
      assert @private_pr_with_review_request.review_requests.pending.not_dismissed.empty?

      # make the approved PR have all requests fulfilled
      @pr_with_approval.review_requests.pending.first.touch(:dismissed_at)
      assert @pr_with_approval.review_requests.pending.not_dismissed.empty?

      @private_pr_with_approval.review_requests.pending.first.touch(:dismissed_at)
      assert @private_pr_with_approval.review_requests.pending.not_dismissed.empty?

      reminder = create(:reminder, remindable: @org, require_review_request: true, include_reviewed_prs: true, user: @org.admin)
      results = ReminderPullRequestFilter.run(reminder)

      assert_same_elements [], results.prs_for_review
      assert_pull_requests(expected: pull_requests_with(approval: true), actual: results.prs_for_author)
    end

    test "includes author reminder if PR is fully approved and excludes pr with pending review request" do
      reminder = create(:reminder, remindable: @org, require_review_request: true, include_reviewed_prs: true, user: @org.admin)
      @pr_with_approval.review_requests.pending.first.touch(:dismissed_at)
      assert @pr_with_approval.review_requests.pending.not_dismissed.empty?

      @private_pr_with_approval.review_requests.pending.first.touch(:dismissed_at)
      assert @private_pr_with_approval.review_requests.pending.not_dismissed.empty?

      results = ReminderPullRequestFilter.run(reminder)

      assert_pull_requests(expected: pull_requests_with(review_request: true), actual: results.prs_for_review)
      assert_pull_requests(expected: pull_requests_with(approval: true), actual: results.prs_for_author)
    end

    test "includes PR for author if PR has enough fulfilled reviews" do
      reminder = create(:reminder, remindable: @org, require_review_request: true, include_reviewed_prs: true, needed_reviews: 1, user: @org.admin)
      assert_equal 1, @pr_with_approval.review_requests.fulfilled.size

      results = ReminderPullRequestFilter.run(reminder)

      assert_pull_requests(expected: pull_requests_with(review_request: true), actual: results.prs_for_review)
      assert_pull_requests(expected: pull_requests_with(approval: true), actual: results.prs_for_author)
    end

    test "includes PR for author if PR does not have enough fulfilled reviews has no pending requests" do
      reminder = create(:reminder, remindable: @org, require_review_request: true, include_reviewed_prs: true, needed_reviews: 2, user: @org.admin)

      @pr_with_approval.review_requests.pending.first.touch(:dismissed_at)
      assert_equal 1, @pr_with_approval.review_requests.fulfilled.size
      assert @pr_with_approval.review_requests.pending.not_dismissed.empty?

      @private_pr_with_approval.review_requests.pending.first.touch(:dismissed_at)
      assert_equal 1, @private_pr_with_approval.review_requests.fulfilled.size
      assert @private_pr_with_approval.review_requests.pending.not_dismissed.empty?

      results = ReminderPullRequestFilter.run(reminder)

      assert_pull_requests(expected: pull_requests_with(review_request: true), actual: results.prs_for_review)
      assert_pull_requests(expected: pull_requests_with(approval: true), actual: results.prs_for_author)
    end
  end

  context "require review request with remind author after reviews with team filtering" do
    test "includes author reminders only for the reminder's team" do
      create(:review_request, pull_request: @pr_no_review_request, reviewer: @reviewer3)
      create(:review_request, pull_request: @private_pr_no_review_request, reviewer: @reviewer3)

      reminder = create(:reminder, remindable: @org, teams: [@team2], require_review_request: true, include_reviewed_prs: true, user: @org.admin)
      results = ReminderPullRequestFilter.run(reminder)

      assert_pull_requests(expected: [@pr_no_review_request] + pull_requests_with(no_review_request: true), actual: results.prs_for_review)
      assert_same_elements [], results.prs_for_author
    end

    test "excludes author reminder if author is on the reminder's team but PR is not fully approved " do
      reminder = create(:reminder, remindable: @org, teams: [@team], require_review_request: true, include_reviewed_prs: true, user: @org.admin)
      results = ReminderPullRequestFilter.run(reminder)

      assert_pull_requests(expected: pull_requests_with(review_request: true, approval: true), actual: results.prs_for_review)
      assert_same_elements [], results.prs_for_author
    end

    test "includes author reminder if PR fully approved and author on the reminder's team" do
      @pr_with_approval.review_requests.pending.first.touch(:dismissed_at)
      @private_pr_with_approval.review_requests.pending.first.touch(:dismissed_at)

      reminder = create(:reminder, remindable: @org, teams: [@team], require_review_request: true, include_reviewed_prs: true, user: @org.admin)
      results = ReminderPullRequestFilter.run(reminder)

      assert_pull_requests(expected: pull_requests_with(review_request: true), actual: results.prs_for_review)
      assert_pull_requests(expected: pull_requests_with(approval: true), actual: results.prs_for_author)
    end

    test "does not include author in org but not on team" do
      org_member = create(:user)
      @org.add_member(org_member, action: :write)
      pr_from_org_member = create(:pull_request, :disable_disk_access, repository: @repo, user: org_member, head_ref: random_ref)
      create_review_request_with_review(pr_from_org_member, reviewer: @reviewer2, submitted: :approved)

      reminder = create(:reminder, remindable: @org, teams: [@team], require_review_request: true, include_reviewed_prs: true, user: @org.admin)
      results = ReminderPullRequestFilter.run(reminder)

      assert_pull_requests(expected: pull_requests_with(review_request: true, approval: true), actual: results.prs_for_review)
      assert_same_elements [], results.prs_for_author
    end

    test "includes PR for author when review requests changed" do
      pr_with_requested_changes = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)
      create_review_request_with_review(pr_with_requested_changes, reviewer: @reviewer2, submitted: :changes_requested)
      assert pr_with_requested_changes.review_requests.pending.not_dismissed.empty?

      reminder = create(:reminder, remindable: @org, user: @org.admin, teams: [@team], require_review_request: true, include_reviewed_prs: true)
      results = ReminderPullRequestFilter.run(reminder)

      assert_pull_requests(expected: pull_requests_with(review_request: true, approval: true), actual: results.prs_for_review)
      assert_pull_requests(expected: [pr_with_requested_changes], actual: results.prs_for_author)
    end

    test "moves the PR back to in review with requested changes" do
      pr_with_requested_changes = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)
      create_review_request_with_review(pr_with_requested_changes, reviewer: @reviewer2, submitted: :approved)
      assert pr_with_requested_changes.review_requests.pending.not_dismissed.empty?

      reminder = create(:reminder, remindable: @org, teams: [@team], require_review_request: true, include_reviewed_prs: true, user: @org.admin)
      results = ReminderPullRequestFilter.run(reminder)

      assert_pull_requests(expected: pull_requests_with(review_request: true, approval: true), actual: results.prs_for_review)
      assert_pull_requests(expected: [pr_with_requested_changes], actual: results.prs_for_author)

      pr_with_requested_changes.request_review_from(actor: pr_with_requested_changes.user, reviewers: [@reviewer2], re_request: true)
      results = ReminderPullRequestFilter.run(reminder)

      assert_pull_requests(expected: [pr_with_requested_changes] + pull_requests_with(review_request: true, approval: true), actual: results.prs_for_review)
      assert_same_elements [], results.prs_for_author
    end
  end

  context "ignore approved pull requests" do
    test "includes approved pull requests when ignore_after_approval_count is zero" do
      reminder = create(:reminder, remindable: @org, ignore_after_approval_count: 0, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: pull_requests_with(review_request: true, approval: true), actual: pull_requests)
    end

    test "excludes approved PRs when ignore_after_approval_count is 1" do
      reminder = create(:reminder, remindable: @org, ignore_after_approval_count: 1, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: pull_requests_with(review_request: true), actual: pull_requests)
    end

    test "only excludes twice approved PRs when ignore_after_approval_count is 2" do
      pr_with_2_approvals = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)
      create(:review_request, pull_request: pr_with_2_approvals, reviewer: @reviewer)
      create_review_request_with_review(pr_with_2_approvals, reviewer: @reviewer2, submitted: :approved)
      create_review_request_with_review(pr_with_2_approvals, reviewer: @reviewer3, submitted: :approved)

      reminder = create(:reminder, remindable: @org, ignore_after_approval_count: 2, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: pull_requests_with(review_request: true, approval: true), actual: pull_requests)
    end
  end

  context "filtering by teams" do
    test "doesn't filter by teams when no team is selected" do
      reminder = create(:reminder, remindable: @org, teams: [], user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: pull_requests_with(review_request: true, approval: true), actual: pull_requests)
    end

    test "doesn't filter reviews by teams when a team is selected and require_review_request is false" do
      reminder = create(:reminder, remindable: @org, teams: [@team2], require_review_request: false, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(
        expected: pull_requests_with(no_review_request: true, review_request: true, approval: true),
        actual: pull_requests
      )
    end

    test "includes pull requests pending review from team member" do
      create(:review_request, pull_request: @pr_no_review_request, reviewer: @reviewer3)
      reminder = create(:reminder, remindable: @org, teams: [@team2], user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: [@pr_no_review_request], actual: pull_requests)
    end

    test "includes pull requests pending review from team" do
      create(:review_request, pull_request: @pr_no_review_request, reviewer: @team2)
      reminder = create(:reminder, remindable: @org, teams: [@team2], user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: [@pr_no_review_request], actual: pull_requests)
    end

    test "excludes pull requests with fulfilled review from team member" do
      create_review_request_with_review(@pr_no_review_request, reviewer_requested: @team2, reviewer: @reviewer3, submitted: :approved)
      reminder = create(:reminder, remindable: @org, teams: [@team2], user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_same_elements [], pull_requests
    end

    test "excludes pull requests with a dismissed review request from the team" do
      create(:review_request, pull_request: @pr_no_review_request, reviewer: @team2, dismissed_at: Time.zone.now)
      reminder = create(:reminder, remindable: @org, teams: [@team2], user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_same_elements [], pull_requests
    end
  end

  context "filtering by title terms" do
    test "excludes pull requests with matching terms in the title" do
      repo = create(:repository, owner: @org)
      GitHub.flipper[:scheduled_reminders_teams_parity].disable(@org.admin)

      matching_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      matching_pull_request.issue.update!(title: "yes WIP do the things")

      second_matching_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      second_matching_pull_request.issue.update!(title: "yes ignoreme do the things")

      non_matching_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      non_matching_pull_request.issue.update!(title: "do the things")

      reminder = create(:reminder, remindable: @org, repositories: [repo], require_review_request: false, ignore_draft_prs: true, ignored_terms: "WIP,   ignoreme", user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: [non_matching_pull_request], actual: pull_requests)
    end
  end

  context "filtering by ignored_labels" do
    test "excludes PR's with labels that are ignored" do
      repo = create(:repository, owner: @org)
      matching_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      matching_pull_request.issue.labels << create(:label, repository: repo, name: "WIP")

      second_matching_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      second_matching_pull_request.issue.labels << create(:label, repository: repo, name: "ignoreme 🚂")

      non_matching_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      non_matching_pull_request.issue.labels << create(:label, repository: repo, name: "allgood")

      reminder = create(:reminder, remindable: @org, repositories: [repo], require_review_request: false, ignore_draft_prs: true, ignored_labels: "WIP,ignoreme 🚂", user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: [non_matching_pull_request], actual: pull_requests)
    end
  end

  context "filtering by required_labels" do
    test "includes PRs with labels that are required" do
      repo = create(:repository, owner: @org)
      non_matching_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      non_matching_pull_request.issue.labels << create(:label, repository: repo, name: "WIP")

      second_non_matching_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      second_non_matching_pull_request.issue.labels << create(:label, repository: repo, name: "ignoreme")

      matching_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      matching_pull_request.issue.labels << create(:label, repository: repo, name: "DONE")

      second_matching_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      second_matching_pull_request.issue.labels << create(:label, repository: repo, name: "Another Filter")

      # Can filter based on one Label
      reminder = create(:reminder, remindable: @org, user: @org.admin, repositories: [repo], require_review_request: false, ignore_draft_prs: true, required_labels: "DONE")
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: [matching_pull_request], actual: pull_requests)

      # Can perform an `OR` filter based on multiple Label
      reminder = create(:reminder, remindable: @org, user: @org.admin, repositories: [repo], require_review_request: false, ignore_draft_prs: true, required_labels: "DONE,Another Filter")
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: [matching_pull_request, second_matching_pull_request], actual: pull_requests)
    end
  end

  context "filtering by min_age" do
    test "includes only PR's created before min_age hours ago" do
      repo = create(:repository, owner: @org)
      new_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref, created_at: 1.hour.ago)
      old_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref, created_at: 30.hours.ago)

      reminder = create(:reminder, remindable: @org, repositories: [repo], require_review_request: false, min_age: 10, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: [old_pull_request], actual: pull_requests)
    end
  end

  context "filtering by min_staleness" do
    test "includes only PR's updated before min_staleness hours ago" do
      repo = create(:repository, owner: @org)
      new_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref, updated_at: 1.hour.ago)
      old_pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: @author, head_ref: random_ref)
      old_pull_request.update_column(:updated_at, 30.hours.ago)

      reminder = create(:reminder, remindable: @org, repositories: [repo], require_review_request: false, min_staleness: 10, user: @org.admin)
      pull_requests = ReminderPullRequestFilter.run(reminder).prs_for_review

      assert_pull_requests(expected: [old_pull_request], actual: pull_requests)
    end
  end
end
