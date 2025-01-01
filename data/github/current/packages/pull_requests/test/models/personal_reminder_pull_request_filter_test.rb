# typed: true
# frozen_string_literal: true

require "test_helper"

class PersonalReminderPullRequestFilterTest < GitHub::TestCase
  include GitHub::ReminderPullRequestFilterHelper

  fixtures do
    ## Public Repos

    @pr_without_review_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)

    @pr_waiting_on_reviewer = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: @pr_waiting_on_reviewer, reviewer: @reviewer)

    @pr_waiting_on_team = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: @pr_waiting_on_team, reviewer: @team)

    @pr_approved_by_reviewer = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)
    create_review_request_with_review(@pr_approved_by_reviewer, reviewer: @reviewer, submitted: :approved)
    create(:review_request, pull_request: @pr_approved_by_reviewer, reviewer: @reviewer2)

    @pr_approved_by_reviewer2 = create(:pull_request, :disable_disk_access, repository: @repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: @pr_approved_by_reviewer2, reviewer: @reviewer)
    create_review_request_with_review(@pr_approved_by_reviewer2, reviewer: @reviewer2, submitted: :approved)

    ## Private Repos

    @private_pr_without_review_request = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @author, head_ref: random_ref)

    @private_pr_waiting_on_reviewer = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: @private_pr_waiting_on_reviewer, reviewer: @reviewer)

    @private_pr_waiting_on_team = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: @private_pr_waiting_on_team, reviewer: @team)

    @private_pr_approved_by_reviewer = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @author, head_ref: random_ref)
    create_review_request_with_review(@private_pr_approved_by_reviewer, reviewer: @reviewer, submitted: :approved)
    create(:review_request, pull_request: @private_pr_approved_by_reviewer, reviewer: @reviewer2)

    @private_pr_approved_by_reviewer2 = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: @private_pr_approved_by_reviewer2, reviewer: @reviewer)
    create_review_request_with_review(@private_pr_approved_by_reviewer2, reviewer: @reviewer2, submitted: :approved)
  end

  # Helper for GitHub::ReminderPullRequestFilterHelper
  def pull_requests_with(private_repos: true, no_review_request: false, waiting_on_reviewer: false, waiting_on_team: false, approved_by_review: false, approved_by_review_2: false)
    prs = []

    if private_repos
      prs << @private_pr_without_review_request if no_review_request
      prs << @private_pr_waiting_on_reviewer if waiting_on_reviewer
      prs << @private_pr_waiting_on_team if waiting_on_team
      prs << @private_pr_approved_by_reviewer if approved_by_review
      prs << @private_pr_approved_by_reviewer2 if approved_by_review_2
    end

    prs << @pr_without_review_request if no_review_request
    prs << @pr_waiting_on_reviewer if waiting_on_reviewer
    prs << @pr_waiting_on_team if waiting_on_team
    prs << @pr_approved_by_reviewer if approved_by_review
    prs << @pr_approved_by_reviewer2 if approved_by_review_2

    prs
  end

  # Helper for GitHub::ReminderPullRequestFilterHelper
  def pull_request_summary
    {
      @private_pr_without_review_request.id => "Private PR without review request",
      @private_pr_waiting_on_reviewer.id => "Private PR waiting on reviewer",
      @private_pr_waiting_on_team.id => "Private PR waiting on team",
      @private_pr_approved_by_reviewer.id => "Private PR approved on reviewer",
      @private_pr_approved_by_reviewer2.id => "Private PR approved on reviewer 2",
      @pr_without_review_request.id => "PR without review request",
      @pr_waiting_on_reviewer.id => "PR waiting on reviewer",
      @pr_waiting_on_team.id => "PR waiting on team",
      @pr_approved_by_reviewer.id => "PR approved on reviewer",
      @pr_approved_by_reviewer2.id => "PR approved on reviewer 2",
    }
  end

  context "filtering in batches", skip_if_feature_disabled: :scheduled_reminders_process_job_with_batches do
    test "returns all expected PRs" do
      PersonalReminderPullRequestFilter.batch_size = 1 # Force it to batch

      personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: true, include_team_review_requests: false)
      pull_requests = PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review
      expected_pull_requests = pull_requests_with(waiting_on_reviewer: true, approved_by_review_2: true)
      assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)
    ensure
      PersonalReminderPullRequestFilter.reset_batch_size
    end
  end

  context "sql indexes" do
    test "does not use FORCE INDEX", skip_if_feature_disabled: :scheduled_reminders_process_job_skip_force_index do
      personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: true, include_team_review_requests: false)
      pull_requests, queries = log_cleaned_queries { PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review }
      expected_pull_requests = pull_requests_with(waiting_on_reviewer: true, approved_by_review_2: true)

      assert queries.map(&:sql).none? { |sql| sql.include?("FORCE INDEX") }

      assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)
    end

    test "uses FORCE INDEX", skip_if_feature_enabled: :scheduled_reminders_process_job_skip_force_index do
      personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: true, include_team_review_requests: false)
      pull_requests, queries = log_cleaned_queries { PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review }
      expected_pull_requests = pull_requests_with(waiting_on_reviewer: true, approved_by_review_2: true)

      assert queries.map(&:sql).any? { |sql| sql.include?("FORCE INDEX") }

      assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)
    end
  end

  context "assigned to user" do
    test "only includes PRs with pending review from user" do
      personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: true, include_team_review_requests: false)
      pull_requests = PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review
      expected_pull_requests = pull_requests_with(waiting_on_reviewer: true, approved_by_review_2: true)
      assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)
    end

    test "only includes PRs with pending review from user, but not private repos when unsupported by org" do
      personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: true, include_team_review_requests: false)

      @org.plan = "free"
      @org.save

      pull_requests = PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review
      expected_pull_requests = pull_requests_with(private_repos: false, waiting_on_reviewer: true, approved_by_review_2: true)
      assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)
    end
  end

  context "assigned to user's team" do
    test "only includes PRs with pending review from team" do
      personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: false, include_team_review_requests: true)
      pull_requests = PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review
      expected_pull_requests = pull_requests_with(waiting_on_team: true)
      assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)
    end

    test "only includes PRs with pending review from team, but not private repos when unsupported by org" do
      personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: false, include_team_review_requests: true)

      @org.plan = "free"
      @org.save

      pull_requests = PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review
      expected_pull_requests = pull_requests_with(private_repos: false, waiting_on_team: true)
      assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)
    end
  end

  test "includes PRs waiting on user or teams" do
    personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: true, include_team_review_requests: true)
    pull_requests = PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review
    expected_pull_requests = pull_requests_with(waiting_on_reviewer: true, waiting_on_team: true, approved_by_review_2: true)
    assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)
  end

  test "includes PRs waiting on user or teams, but not private repos when unsupported by org" do
    personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: true, include_team_review_requests: true)

    @org.plan = "free"
    @org.save
    pull_requests = PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review
    expected_pull_requests = pull_requests_with(private_repos: false, waiting_on_reviewer: true, waiting_on_team: true, approved_by_review_2: true)
    assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)
  end

  test "excludes PRs waiting on user in repositories they no longer have access to" do
    personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: true)
    expected_pull_requests = pull_requests_with(waiting_on_reviewer: true, approved_by_review_2: true)
    assert_pull_requests(expected: expected_pull_requests, actual: PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review)

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) { @org.remove_member(@reviewer) }

    assert_same_elements [], PersonalReminderPullRequestFilter.run(personal_reminder.reload).prs_for_review
  end

  test "excludes PRs waiting on user in repositories they no longer have access to, but not private repos when unsupported by org" do
    personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: true)

    @org.plan = "free"
    @org.save
    expected_pull_requests = pull_requests_with(private_repos: false, waiting_on_reviewer: true, approved_by_review_2: true)
    assert_pull_requests(expected: expected_pull_requests, actual: PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review)

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) { @org.remove_member(@reviewer) }

    assert_same_elements [], PersonalReminderPullRequestFilter.run(personal_reminder.reload).prs_for_review
  end

  test "excludes PR's from non-active and unmaintained repos, also private repos when org does not support them" do
    archived_repo = create(:repository, owner: @org)
    unmaintained_repo = create(:repository, owner: @org)

    archived_repo_pr = create(:pull_request, :disable_disk_access, repository: archived_repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: archived_repo_pr, reviewer: @reviewer)
    archived_repo.update!(active: nil)

    unmaintained_repo_pr = create(:pull_request, :disable_disk_access, repository: unmaintained_repo, user: @author, head_ref: random_ref)
    create(:review_request, pull_request: unmaintained_repo_pr, reviewer: @reviewer)
    unmaintained_repo.update!(maintained: false)

    personal_reminder = create(:personal_reminder, user: @reviewer, remindable: @org, include_review_requests: true, include_team_review_requests: false)
    pull_requests = PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review

    expected_pull_requests = pull_requests_with(waiting_on_reviewer: true, approved_by_review_2: true)
    assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)

    @org.plan = "free"
    @org.save
    personal_reminder.reset_memoized_attributes

    pull_requests = PersonalReminderPullRequestFilter.run(personal_reminder).prs_for_review
    expected_pull_requests = pull_requests_with(private_repos: false, waiting_on_reviewer: true, approved_by_review_2: true)
    assert_pull_requests(expected: expected_pull_requests, actual: pull_requests)
  end
end
