# typed: true
# frozen_string_literal: true
require "test_helper"

class TeamReviewRequestDelegationLoadBalancingTest < GitHub::TestCase
  include HydroTestHelpers
  include NewsiesHelper
  include PullRequestSynchronizationTestHelpers

  setup_once { disable_monolith_rate_limiter_redis }
  teardown_once { enable_monolith_rate_limiter_redis }

  fixtures do
    Spokesd.enable_spokesd

    @org = create(:organization, plan: "bronze")
    @org_admin = create(:user, :verified, login: "skalnik")

    @org.add_admin(@org_admin)
    @org_member = create(:user, :verified, login: "mattyoho")
    @org.add_member(@org_member)
    @org_member2 = create(:user, :verified, login: "mrgilman")
    @org.add_member(@org_member2)
    @org_member3 = create(:user, :verified, login: "nakajima")
    @org.add_member(@org_member3)
    @org_member4 = create(:user, :verified, login: "mikesea")
    @org.add_member(@org_member4)
    @org_member5 = create(:user, :verified, login: "jjcaine")
    @org.add_member(@org_member5)

    @team = create(:team, organization: @org, creator: @org_member, privacy: :closed)
    @team.add_member(@org_admin)
    @team.add_member(@org_member)
    @team.add_member(@org_member2)
    @team.add_member(@org_member3)
    @team.add_member(@org_member4)
    @team.add_member(@org_member5)

    @source = create(:repository, owner: @org, name: "aquaman", from_example: :review_comment_source)
    @fork = create(:fork_repository, forker: @org_member, fork_repo: @source, from_example: :review_comment_fork)

    @source.add_member @org_member
    @source.add_member @org_member2
    @source.add_member @org_member3
    @source.add_member @org_member4
    @source.add_member @org_member5
    @team.add_repository_directly(@source)

    example_repo_snapshot

    @pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, issue: create(:issue, user: @org_member, repository: @source))

    @team.review_request_delegation_enabled = true
    @team.review_request_delegation_algorithm = :load_balance
    @team.save

    @team_with_only_child_teams = create(:team, organization: @org, privacy: :closed, review_request_delegation_enabled: true, review_request_delegation_algorithm: :load_balance)
    @team_with_only_child_teams.add_repository_directly(@source)
    @child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @team_with_only_child_teams.id)
    @child_team.add_member(@org_member2)
  end

  setup do
    example_repo_restore
  end

  test "delegates to child team members" do
    pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic", issue: create(:issue, user: @org_member, repository: @source))
    pull.request_review_from(actor: @org_member, reviewers: [@team_with_only_child_teams])
    assert_equal 1, pull.review_requests.count, "Has one review request"
    assert_equal 1, pull.review_requests.where(reviewer_type: "User", reviewer_id: @org_member2.id).count, "Has one user review request"
  end

  test "delegates to team members, multiple PRs" do
    3.times do |index|
      other_repo = create(:repository, owner: @org, name: "aquaman_#{index}")
      other_repo_fork = create(:fork_repository, forker: @org_member, fork_repo: other_repo)
      @team.add_repository_directly(other_repo)

      pull = create(:pull_request, :disable_disk_access, repository: other_repo, user: @org_member, head_ref: "#{other_repo_fork.user}:topic", issue: create(:issue, user: @org_member, repository: other_repo))
      pull.request_review_from(actor: @org_member, reviewers: [@team])
      assert_equal 1, pull.review_requests.count, "Has one review request"
    end
  end

  test "allows a non-collab actor to trigger delegation" do
    pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic", issue: create(:issue, user: @org_member, repository: @source))

    pull.expects(:review_requested_for?).with(@team_with_only_child_teams).once.returns(true)

    Team::ReviewRequestDelegation.delegate_to_members(
      actor: create(:user, login: "stranger"),
      pull_request: pull,
      team: @team_with_only_child_teams,
      strategy: :load_balance)

    assert_equal 1, pull.review_requests.count, "Has one review request"
    assert_equal 1, pull.review_requests.not_dismissed.type_users.count, "Has only one user request"
  end

  test "doesn't delegate to PR author" do
    (1..@team.members.count).each do |i|
      pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic#{i}", issue: create(:issue, user: @org_member, repository: @source))
      pull.request_review_from(actor: @org_member, reviewers: [@team])

      assert_equal 1, pull.review_requests.count, "Has one review request"
      assert_equal 1, pull.review_requests.where(reviewer_type: "User").count, "Has one user review request"
      refute_equal @org_member, pull.review_requests[0].reviewer, "Does not request review from the PR Author"
    end
  end

  test "doesn't delegate to excluded member" do
    excluded_member = @team.members.last
    refute_equal excluded_member, @org_member, "Doesn't pick PR Author for excluded member"
    ReviewRequestDelegationExcludedMember.create(team: @team, user: excluded_member)

    (1..@team.members.count).each do |i|
      ref = @fork.heads.create("t#{i}", @fork.heads.find("master").target, @fork.owner)
      metadata = { message: "blah", committer: @fork.owner }
      ref.append_commit(metadata, @fork.owner)

      issue = create(:issue, user: @org_member, repository: @source)
      pull = PullRequest.create_for(@source,
        base: "master",
        head: "#{@fork.user}:t#{i}",
        user: issue.user,
        issue: issue)
      issue.pull_request = pull
      pull.request_review_from(actor: @org_member, reviewers: [@team])

      assert_equal 1, pull.review_requests.count, "Has one review request"
      assert_equal 1, pull.review_requests.where(reviewer_type: "User").count, "Has one user review request"
      refute_equal @org_member, pull.review_requests[0].reviewer, "Does not request review from the PR Author"
      refute_equal excluded_member, pull.review_requests[0].reviewer, "Does not request review from excluded member"
    end
  end

  test "doesn't delegate to excluded child team member" do
    ReviewRequestDelegationExcludedMember.create(team: @team_with_only_child_teams, user: @org_member2)

    pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic", issue: create(:issue, user: @org_member, repository: @source))
    pull.request_review_from(actor: @org_member, reviewers: [@team_with_only_child_teams])

    assert_equal 1, pull.review_requests.count, "Has one review request"
    assert_equal 1, pull.review_requests.where(reviewer_type: "Team", reviewer_id: @team_with_only_child_teams).count, "Child team stays requested"
    assert_equal 0, pull.review_requests.where(reviewer_type: "User", reviewer_id: @org_member2.id).count, "Doesn't have request for excluded user"
  end

  test "delegates to the user with the fewest reviews outstanding" do
    # Grab delegateable team members "out of order" to avoid coupling to creation order
    members = [@org_member2, @org_member4, @org_member3, @org_member5, @org_admin]

    # Create N review requests for each member, from 0 to len(members),
    # so we can assert the delegated-to member changes as expected as more
    # review requests are made.
    #
    # Having a member with 0 current requests is an important edge case.
    members.each_with_index do |member, count|
      count.times do |_n|
        pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic#{SecureRandom.hex}", issue: create(:issue, user: @org_member, repository: @source))
        pull.request_review_from(actor: @org_member, reviewers: [member])
      end
    end

    # Now we'll assert that each member is delegated to in least-review-requests-first order
    members.each_with_index do |member, index|
      pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic#{SecureRandom.hex}", issue: create(:issue, user: @org_member, repository: @source))
      pull.request_review_from(actor: @org_member, reviewers: [@team])

      assert_equal 0, pull.review_requests.type_teams.count, "Has no team review requests"
      assert_equal 1, pull.review_requests.type_users.count, "Has one user review request"

      expected = member
      actual = pull.review_requests.reload.first.reviewer
      if expected != actual
        # This assertion has been flaky for quite a while, but we've not been able
        # to determine why.
        #
        # https://janky.githubapp.com/flaky_tests/47e63a80a780f4ebbd63c0a442f223562c246078215ef1c005e48f943acf4505
        #
        # Checking the equality before asserting allows us to do some
        # potentially slow or destructive debugging to add more context to the
        # failure message when we know the test is about to fail.
        #
        # My hope is that this debugging information will allow you to succeed
        # where I have failed and fix this flaky test once and for all.
        #
        # Godspeed.

        counts_without_reload = members.map { |u| [u.login, u.review_requests.count] }.to_h
        counts_with_reload = members.map { |u| [u.login, u.reload.review_requests.count] }.to_h
        features = GitHub.flipper.features.select(&:on?).map(&:name)
        repo_features = GitHub.flipper.features.select { |f| f.enabled?(@source) }.map(&:name)
        expected_features = GitHub.flipper.features.select { |f| f.enabled?(expected) }.map(&:name)
        actual_features = GitHub.flipper.features.select { |f| f.enabled?(actual) }.map(&:name)

        message = (
          "Has delegated to the org member with the fewest outstanding reviews\n\n"\
          "Expected #{expected.login.inspect}, but got #{actual.login.inspect}\n"\
          "The number of requests for each user is:    #{counts_without_reload.inspect}\n"\
          "After reloading the records the counts are: #{counts_with_reload.inspect}\n"\
          "The index is #{index} (this is the #{index + 1}#{(index + 1).ordinal} iteration)\n"\
          "The globally enabled Flipper features are #{features.inspect}\n"\
          "The enabled Flipper features for the repo are #{repo_features.inspect}\n"\
          "The enabled Flipper features for #{expected.login} are #{expected_features.inspect}\n"\
          "The enabled Flipper features for #{actual.login} are #{actual_features.inspect}\n"\
        )
        assert_equal expected, actual, message
      end

      # Now bump up the review requests count for this and all prior members by one so
      # that we'll select the "next least reviewed" member on the following pass without
      # worrying about ties.
      (0..index).each do |i|
        pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic#{SecureRandom.hex}", issue: create(:issue, user: @org_member, repository: @source))
        pull.request_review_from(actor: @org_member, reviewers: [members[i]])
      end
    end
  end

  test "only subscribes and notifies assigned team member" do
    GitHub.flipper[:notifyd_pull_request_notify_email_and_web].disable
    @team.update(review_request_delegation_notify_team: false)
    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, AsyncNewsiesDeliveryJob]
    perform_enqueued_jobs(only: only) do
      @pull.request_review_from(actor: @org_member, reviewers: [@team])
    end
    @pull.reload

    assert_equal 1, @pull.review_requests.count, "Has one review request"
    reviewer = @pull.review_requests.first.reviewer
    assert @pull.subscribed?(reviewer), "Reviewer should be subscribed"
    issue_event = @pull.events.where(event: "review_requested").last
    assert_delivered_email_notification(reviewer, IssueEventNotification.new(issue_event), "review_requested")

    @team.members.each do |team_member|
      next if team_member == @pull.user
      next if team_member == reviewer

      refute_delivered_any_notifications(team_member)
      refute @pull.subscribed?(team_member), "Non-reviewer shouldn't be subscribed"
    end
  end

  test "resubscribes team if delegation fails" do
    @team.update(review_request_delegation_notify_team: false)
    @team.members.each do |team_member|
      create(:user_status, user: team_member, limited_availability: true)
    end

    @pull.request_review_from(actor: @org_member, reviewers: [@team])
    @pull.reload

    assert_equal 1, @pull.review_requests.count, "Has one review request"
    assert_equal 1, @pull.review_requests.where(reviewer_type: "Team").count, "Has original Team review request"

    @team.members.each do |team_member|
      assert @pull.subscribed?(team_member), "Team member should be subscribed"
    end
  end

  test "doesn't count existing member requests if setting disabled" do
    @pull.request_review_from(actor: @org_member, reviewers: [@team.members.first])
    @pull.reload

    assert_equal 1, @pull.review_requests.count, "Has one review request"

    @team.update!(
      review_request_delegation_count_members_already_requested: false,
      review_request_delegation_member_count: 3,
    )

    @pull.request_review_from(actor: @org_member, reviewers: [@team], append: true)
    @pull.reload

    assert_equal 0, @pull.review_requests.type_teams.count, "Has no Team review requests"
    assert_equal 4, @pull.review_requests.type_users.count, "Has three assigned plus one manual member review requests"
  end

  test "resubscribes team if delegation fails due to an empty team" do
    @team.members.each do |team_member|
      @team.remove_member(team_member, force: true)
    end

    @pull.request_review_from(actor: @org_member, reviewers: [@team])
    @pull.reload

    assert_equal 1, @pull.review_requests.count, "Has one review request"
    assert_equal 1, @pull.review_requests.where(reviewer_type: "Team").count, "Has original Team review request"
  end

  test "leaves team request if setting disabled" do
    @team.update!(review_request_delegation_remove_team_request: false)

    @pull.request_review_from(actor: @org_member, reviewers: [@team])
    @pull.reload

    assert_equal 2, @pull.review_requests.count, "Has two review requests"

    team_request = @pull.review_requests.type_teams.first
    assert_equal @team, team_request.reviewer
    refute team_request.assigned_from_review_request

    user_request = @pull.review_requests.type_users.first
    assert_includes @team.member_ids, user_request.reviewer_id
    assert_equal @team, user_request.assigned_from_review_request.reviewer
  end

  test "marks the delegated review request with the assigned from request" do
    @team.update!(review_request_delegation_remove_team_request: false)
    @pull.request_review_from(actor: @org_member, reviewers: [@team])
    @pull.reload

    assert_equal 2, @pull.review_requests.count

    team_request = @pull.review_requests.type_teams.first
    assert_equal @team, team_request.reviewer
    refute team_request.assigned_from_review_request

    user_request = @pull.review_requests.type_users.first
    assert_includes @team.member_ids, user_request.reviewer_id
    assert_equal @team, user_request.assigned_from_review_request.reviewer
  end

  test "marks when a review request is removed via assignment" do
    @pull.request_review_from(actor: @org_member, reviewers: [@team])
    @pull.reload

    assert_equal 1, @pull.review_requests.count
    user_request = @pull.review_requests.type_users.first
    assert_includes @team.member_ids, user_request.reviewer_id
    assert_equal @team, user_request.assigned_from_review_request.reviewer

    team_request = @pull.unscoped_review_requests.dismissed.type_teams.first
    assert_equal @team, team_request.reviewer
    assert_predicate team_request, :dismissed_via_assignment?
  end

  test "exclude child team members if setting disabled" do
    @team_with_only_child_teams.update!(review_request_delegation_include_child_team_members: false)

    pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic", issue: create(:issue, user: @org_member, repository: @source))
    pull.request_review_from(actor: @org_member, reviewers: [@team_with_only_child_teams])
    pull.reload

    assert_equal 1, pull.review_requests.count, "Has one review request"
    assert_equal @team_with_only_child_teams, pull.review_requests.type_teams.first.reviewer, "Has original team review request"
    assert_empty pull.review_requests.type_users, "Has no child team member requests"
  end

  test "emits a hydro event when a review request is delegated", skip_enterprise: true do
    Timecop.freeze do
      count_members_already_requested = false
      delegation_member_count = 3
      remove_team_request = false

      @team.update!(
        review_request_delegation_count_members_already_requested: count_members_already_requested,
        review_request_delegation_member_count: delegation_member_count,
        review_request_delegation_remove_team_request: remove_team_request,
      )

      @pull.request_review_from(actor: @org_member, reviewers: [@team])
      @pull.reload

      team_review_request = @pull.review_requests.type_teams.first
      # Assigned review request order matters for assertion matching below
      # Same order as Team::ReviewRequestDelegation#delegate_to_members hydro param
      assigned_review_requests = \
        @pull.review_requests.pending.where(assigned_from_review_request: team_review_request).order("id ASC")

      pull_request_review_request_overrides = {
        action: ReviewRequest::REQUESTED_ACTION,
        actor: Hydro::EntitySerializer.user(@org_member)
      }

      message = {
        organization: Hydro::EntitySerializer.organization(@org),
        team: Hydro::EntitySerializer.team(@team),
        repository: Hydro::EntitySerializer.repository(@source),
        pull_request: Hydro::EntitySerializer.pull_request(@pull),
        algorithm: "LOAD_BALANCE",
        max_delegated_reviewers_count: delegation_member_count,
        count_existing_reviewers: count_members_already_requested,
        remove_team_request: remove_team_request,
        include_child_team_members: true,
        team_review_request: Hydro::EntitySerializer.pull_request_review_request(
          team_review_request,
          overrides: pull_request_review_request_overrides
        ),
        assigned_review_requests: assigned_review_requests.map do |assigned_review_request|
          Hydro::EntitySerializer.pull_request_review_request(
            assigned_review_request,
            overrides: pull_request_review_request_overrides
          )
        end
      }

      assert_hydro_messages(count: 1, schema: "github.v1.PullRequestReviewRequestDelegation")
      assert_hydro_published(message, schema: "github.v1.PullRequestReviewRequestDelegation")
    end
  end

  test "doesn't re-request former reviewers" do
    org_member = create(:user)
    @org.add_member(org_member)

    @pull.request_review_from(actor: @org_member, reviewers: [org_member])
    create(:pull_request_review, pull_request: @pull, user: org_member).approve!

    @pull.request_review_from(actor: @org_member, reviewers: [@team])
    @pull.reload

    assert_equal 2, @pull.review_requests.count
  end

  test "works with CODEOWNERS" do
    contents = <<~OWNERS
      * @#{@team}
    OWNERS

    base_ref = @source.heads.find("master")
    base_ref.append_commit({ message: "codeowners", committer: @org_member }, @org_member) do |files|
      files.add("CODEOWNERS", contents)
    end

    ref = @fork.heads.create("b-r-a-n-c-h", @fork.heads.find("master").target, @fork.owner)
    metadata = { message: "blah", committer: @fork.owner }
    ref.append_commit(metadata, @fork.owner) do |files|
      files.add("cromnch.md", "How cats say crunch")
    end

    issue = create(:issue, user: @org_member, repository: @source)
    pull = T.let(nil, T.nilable(PullRequest))
    perform_enqueued_jobs(only: RequestPullRequestReviewersJob) do
      pull = PullRequest.create_for(@source,
        base: "master",
        head: "#{@fork.user}:b-r-a-n-c-h",
        user: issue.user,
        issue: issue)
    end
    pull&.reload

    assert_equal 0, pull&.review_requests&.where(reviewer_type: "Team")&.count, "Should not have any Team review requests"
    assert_equal 1, pull&.review_requests&.where(reviewer_type: "User")&.count, "Should delegate to an individual"
  end

  test "works with CODEOWNERS and manual request" do
    other_team_member = create(:user, :verified, login: "jankoszewski")
    @org.add_member(other_team_member)
    @source.add_member(other_team_member)

    other_team = create(
      :team,
      organization: @org,
      creator: @org_member,
      privacy: :closed,
      name: "other team",
      review_request_delegation_enabled: true,
      review_request_delegation_algorithm: :load_balance
    )
    other_team.add_member(other_team_member)

    assert other_team.review_request_delegation_enabled
    assert_equal other_team_member, other_team.members.first

    other_team.add_repository_directly(@source)

    contents = <<~OWNERS
      * @#{@team}
    OWNERS

    base_ref = @source.heads.find("master")
    base_ref.append_commit({ message: "codeowners", committer: @org_member }, @org_member) do |files|
      files.add("CODEOWNERS", contents)
    end

    ref = @fork.heads.create("b-r-a-n-c-h", @fork.heads.find("master").target, @fork.owner)
    metadata = { message: "blah", committer: @fork.owner }
    ref.append_commit(metadata, @fork.owner) do |files|
      files.add("cromnch.md", "How cats say crunch")
    end

    issue = create(:issue, user: @org_member, repository: @source)
    pull = T.let(nil, T.nilable(PullRequest))
    perform_enqueued_jobs(only: RequestPullRequestReviewersJob) do
      pull = PullRequest.create_for(@source,
        base: "master",
        head: "#{@fork.user}:b-r-a-n-c-h",
        user: issue.user,
        issue: issue,
        reviewer_team_ids: [other_team.id]
      )
    end
    pull&.reload

    assert_equal 0, pull&.review_requests&.where(reviewer_type: "Team")&.count, "Should not have any Team review requests" # returns 1
    assert_equal 2, pull&.review_requests&.where(reviewer_type: "User")&.count, "Should delegate to an individual" # returns 1
  end

  test "works with CODEOWNERS in PR sync" do
    contents = <<~OWNERS
      *.md @#{@team}
    OWNERS

    base_ref = @source.heads.find("master")
    base_ref.append_commit({ message: "codeowners", committer: @org_member }, @org_member) do |files|
      files.add("CODEOWNERS", contents)
    end

    ref = @fork.heads.create("b-r-a-n-c-h", @fork.heads.find("master").target, @fork.owner)
    metadata = { message: "blah", committer: @fork.owner }
    ref.append_commit(metadata, @fork.owner) do |files|
      files.add("file.txt", "How cats say crunch")
    end

    pull = perform_enqueued_jobs(only: RequestPullRequestReviewersJob) do
      issue = create(:issue, user: @org_member, repository: @source)
      PullRequest.create_for(@source,
        base: "master",
        head: "#{@fork.user}:b-r-a-n-c-h",
        user: issue.user,
        issue: issue)
    end
    pull.reload

    assert_equal 0, pull.review_requests.where(reviewer_type: "Team").count, "Should not have any Team review requests"
    assert_equal 0, pull.review_requests.where(reviewer_type: "User").count, "Should delegate to an individual"

    with_enqueued_pr_sync_jobs do
      metadata = { message: "blah", committer: @fork.owner }
      ref.append_commit(metadata, @fork.owner) do |files|
        files.add("cromnch.md", "How cats say crunch")
      end
    end

    assert_equal 0, pull.review_requests.where(reviewer_type: "Team").count, "Should not have any Team review requests"
    assert_equal 1, pull.review_requests.where(reviewer_type: "User").count, "Should delegate to an individual"
  end
end

class TeamReviewRequestDelegationRoundRobinTest < GitHub::TestCase
  include HydroTestHelpers
  include NewsiesHelper

  fixtures do
    @org = create(:organization, plan: "bronze")
    @org_admin = create(:user, :verified, login: "skalnik")

    @org.add_admin(@org_admin)
    @org_member = create(:user, :verified, login: "mattyoho")
    @org.add_member(@org_member)
    @org_member2 = create(:user, :verified, login: "mrgilman")
    @org.add_member(@org_member2)
    @org_member3 = create(:user, :verified, login: "nakajima")
    @org.add_member(@org_member3)
    @org_member4 = create(:user, :verified, login: "mikesea")
    @org.add_member(@org_member4)
    @org_member5 = create(:user, :verified, login: "jjcaine")
    @org.add_member(@org_member5)

    @team = create(:team, organization: @org, creator: @org_member, privacy: :closed)
    @team.add_member(@org_admin)
    @team.add_member(@org_member)
    @team.add_member(@org_member2)
    @team.add_member(@org_member3)
    @team.add_member(@org_member4)
    @team.add_member(@org_member5)

    @source = create(:repository, owner: @org, name: "aquaman", from_example: :review_comment_source)
    @fork = create(:fork_repository, forker: @org_member, fork_repo: @source, from_example: :review_comment_fork)

    @source.add_member @org_member
    @source.add_member @org_member2
    @source.add_member @org_member3
    @source.add_member @org_member4
    @source.add_member @org_member5
    @team.add_repository_directly(@source)

    example_repo_snapshot

    @pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, issue: create(:issue, user: @org_member, repository: @source))

    @team.review_request_delegation_enabled = true
    @team.review_request_delegation_algorithm = :round_robin
    @team.save

    @team_with_only_child_teams = create(:team, organization: @org, privacy: :closed, review_request_delegation_enabled: true, review_request_delegation_algorithm: :load_balance)
    @team_with_only_child_teams.add_repository_directly(@source)
    @child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @team_with_only_child_teams.id)
    @child_team.add_member(@org_member2)
  end

  setup do
    example_repo_restore
  end

  test "doesn't delegate to PR author" do
    (1..(@team.members.count - 1)).each do |i|
      pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic#{i}", issue: create(:issue, user: @org_member, repository: @source))
      pull.request_review_from(actor: @org_member, reviewers: [@team])

      assert_equal 1, pull.review_requests.count
      assert_equal 1, pull.review_requests.where(reviewer_type: "User").count, "Has only one user request"
      refute_equal @org_member, pull.review_requests[0].reviewer
    end
  end

  test "delegates to each team member in turn" do
    (1..(@team.members.count - 1)).each do |i|
      pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic#{i}", issue: create(:issue, user: @org_member, repository: @source))
      pull.request_review_from(actor: @org_member, reviewers: [@team])

      assert_equal 1, pull.review_requests.count
      assert_equal 1, pull.review_requests.not_dismissed.type_users.count, "Has only one user request"
      reviewer = pull.review_requests.not_dismissed.type_users.first.reviewer
      assert @team.member?(reviewer)
      refute_equal @org_member, reviewer
    end
  end

  test "delegates to each team member with delegated review requests in turn" do
    @team.members.each do |member|
      TeamMemberDelegatedReviewRequest.upsert(
        team_id: @team.id,
        member_id: member.id,
        delegated_at: Time.current,
      )
    end

    (1..(@team.members.count - 1)).each do |i|
      pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic#{i}", issue: create(:issue, user: @org_member, repository: @source))
      pull.request_review_from(actor: @org_member, reviewers: [@team])

      assert_equal 1, pull.review_requests.count
      assert_equal 1, pull.review_requests.not_dismissed.type_users.count, "Has only one user request"
      reviewer = pull.review_requests.not_dismissed.type_users.first.reviewer
      assert @team.member?(reviewer)
      refute_equal @org_member, reviewer
    end
  end

  test "allows delegation from a non-collab" do
    pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic", issue: create(:issue, user: @org_member, repository: @source))

    pull.expects(:review_requested_for?).with(@team).once.returns(true)

    Team::ReviewRequestDelegation.delegate_to_members(
      actor: create(:user, login: "stranger"),
      pull_request: pull,
      team: @team,
      strategy: :round_robin)

    assert_equal 1, pull.review_requests.count
    assert_equal 1, pull.review_requests.not_dismissed.type_users.count, "Has only one user request"
  end

  test "can exclude members" do
    excluded_member = @team.members.last
    refute_equal excluded_member, @org_member, "Doesn't pick PR Author for excluded member"
    ReviewRequestDelegationExcludedMember.create(team: @team, user: excluded_member)

    (1..(@team.members.count - 1)).each do |i|
      ref = @fork.heads.create("rr#{i}", @fork.heads.find("master").target, @fork.owner)
      metadata = { message: "blah", committer: @fork.owner }
      ref.append_commit(metadata, @fork.owner)

      issue = create(:issue, user: @org_member, repository: @source)
      pull = PullRequest.create_for(@source,
        base: "master",
        head: "#{@fork.user}:rr#{i}",
        user: issue.user,
        issue: issue)
      issue.pull_request = pull
      pull.request_review_from(actor: @org_member, reviewers: [@team])

      assert_equal 1, pull.review_requests.count
      assert_equal 1, pull.review_requests.where(reviewer_type: "User").count, "Has only one user request"
      refute_equal @org_member, pull.review_requests[0].reviewer
    end

    review_counts = ReviewRequest.where(reviewer_type: "User").
                      pluck(:reviewer_id).
                      inject(Hash.new(0)) { |h, id| h[id] += 1; h }

    assert_equal review_counts[excluded_member.id], 0, "Excluded user should only 0 review requests"
  end

  test "only subscribes and notifies assigned team member" do
    GitHub.flipper[:notifyd_pull_request_notify_email_and_web].disable
    @team.update(review_request_delegation_notify_team: false)
    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, AsyncNewsiesDeliveryJob]
    perform_enqueued_jobs(only: only) do
      @pull.request_review_from(actor: @org_member, reviewers: [@team])
    end
    @pull.reload

    assert_equal 1, @pull.review_requests.count, "Has one review request"
    reviewer = @pull.review_requests.first.reviewer
    reviewer.emails.first.verify!
    assert @pull.subscribed?(reviewer), "Reviewer should be subscribed"
    issue_event = @pull.events.where(event: "review_requested").last
    assert_delivered_email_notification(reviewer, IssueEventNotification.new(issue_event), "review_requested")

    @team.members.each do |team_member|
      next if team_member == @pull.user
      next if team_member == reviewer

      refute_delivered_any_notifications(team_member)
      refute @pull.subscribed?(team_member), "Non-reviewer shouldn't be subscribed"
    end
  end

  test "resubscribes team if delegation fails" do
    @team.update(review_request_delegation_notify_team: false)
    @team.members.each do |team_member|
      create(:user_status, user: team_member, limited_availability: true)
    end

    @pull.request_review_from(actor: @org_member, reviewers: [@team])
    @pull.reload

    assert_equal 1, @pull.review_requests.count, "Has one review request"
    assert_equal 1, @pull.review_requests.where(reviewer_type: "Team").count, "Has original Team review request"

    @team.members.each do |team_member|
      assert @pull.subscribed?(team_member), "Team member should be subscribed"
    end
  end

  test "doesn't count existing member requests if setting disabled" do
    @pull.request_review_from(actor: @org_member, reviewers: [@team.members.first])
    @pull.reload

    assert_equal 1, @pull.review_requests.count, "Has one review request"

    @team.update!(
      review_request_delegation_count_members_already_requested: false,
      review_request_delegation_member_count: 3,
    )

    @pull.request_review_from(actor: @org_member, reviewers: [@team], append: true)
    @pull.reload

    assert_equal 0, @pull.review_requests.type_teams.count, "Has no Team review requests"
    assert_equal 4, @pull.review_requests.type_users.count, "Has three assigned plus one manual member review requests"
  end

  test "leaves team request if setting disabled" do
    @team.update!(review_request_delegation_remove_team_request: false)
    @pull.request_review_from(actor: @org_member, reviewers: [@team])
    @pull.reload

    assert_equal 2, @pull.review_requests.count

    team_request = @pull.review_requests.type_teams.first
    assert_equal @team, team_request.reviewer
    refute team_request.assigned_from_review_request

    user_request = @pull.review_requests.type_users.first
    assert_includes @team.member_ids, user_request.reviewer_id
    assert_equal @team, user_request.assigned_from_review_request.reviewer
  end

  test "exclude child team members if setting disabled" do
    @team_with_only_child_teams.update!(review_request_delegation_include_child_team_members: false)

    pull = create(:pull_request, :disable_disk_access, repository: @source, user: @org_member, head_ref: "#{@fork.user}:topic", issue: create(:issue, user: @org_member, repository: @source))
    pull.request_review_from(actor: @org_member, reviewers: [@team_with_only_child_teams])
    pull.reload

    assert_equal 1, pull.review_requests.count, "Has one review request"
    assert_equal @team_with_only_child_teams, pull.review_requests.type_teams.first.reviewer, "Has original team review request"
    assert_empty pull.review_requests.type_users, "Has no child team member requests"
  end

  test "emits a hydro event when a review request is delegated", skip_enterprise: true do
    Timecop.freeze(10.seconds.ago) do
      remove_team_request = false
      @team.update!(review_request_delegation_remove_team_request: remove_team_request)

      @pull.request_review_from(actor: @org_member, reviewers: [@team])
      @pull.reload

      team_review_request = @pull.review_requests.type_teams.first
      # Assigned review request order matters for assertion matching below
      # Same order as Team::ReviewRequestDelegation#delegate_to_members hydro param
      assigned_review_requests = \
        @pull.review_requests.pending.where(assigned_from_review_request: team_review_request).order("id ASC")

      pull_request_review_request_overrides = {
        action: ReviewRequest::REQUESTED_ACTION,
        actor: Hydro::EntitySerializer.user(@org_member)
      }

      message = {
        organization: Hydro::EntitySerializer.organization(@org),
        team: Hydro::EntitySerializer.team(@team),
        repository: Hydro::EntitySerializer.repository(@source),
        pull_request: Hydro::EntitySerializer.pull_request(@pull),
        algorithm: "ROUND_ROBIN",
        max_delegated_reviewers_count: 1,
        count_existing_reviewers: true,
        remove_team_request: remove_team_request,
        include_child_team_members: true,
        team_review_request: Hydro::EntitySerializer.pull_request_review_request(
          team_review_request,
          overrides: pull_request_review_request_overrides
        ),
        assigned_review_requests: assigned_review_requests.map do |assigned_review_request|
          Hydro::EntitySerializer.pull_request_review_request(
            assigned_review_request,
            overrides: pull_request_review_request_overrides
          )
        end
      }

      assert_hydro_messages(count: 1, schema: "github.v1.PullRequestReviewRequestDelegation")
      assert_hydro_published(message, schema: "github.v1.PullRequestReviewRequestDelegation")
    end
  end

  test "doesn't re-request former reviewers" do
    org_member = create(:user)
    @org.add_member(org_member)

    @pull.request_review_from(actor: @org_member, reviewers: [org_member])
    create(:pull_request_review, pull_request: @pull, user: org_member).approve!

    @pull.request_review_from(actor: @org_member, reviewers: [@team])
    @pull.reload

    assert_equal 2, @pull.review_requests.count
  end

  context "find_candidate_delegates_using_sort" do
    test "respects plan limit for repos without reviewers" do
      @pull.stubs(:manual_review_requests_limit).returns 1

      @team.update!(
        review_request_delegation_count_members_already_requested: false,
        review_request_delegation_member_count: 4,
      )

      @pull.expects(:review_requested_for?).with(@team).once.returns(true)

      Team::ReviewRequestDelegation.delegate_to_members(
        actor: @pull.issue.modifying_user,
        pull_request: @pull,
        team: @team,
        strategy: :round_robin,
        max_auto_assigned_reviewers_count: @team.review_request_delegation_member_count
      )

      assert_equal 1, @pull.review_requests.count, "Has one review request"
      assert_equal 1, @pull.review_requests.not_dismissed.type_users.count, "Has one user request"
    end

    test "respects plan limit for repos with reviewers" do
      member_outside_of_team = create(:user, login: "john")
      @org.add_member(member_outside_of_team)
      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, AsyncNewsiesDeliveryJob]
      perform_enqueued_jobs(only: only) do
        @pull.request_review_from(actor: @org_member, reviewers: [member_outside_of_team])
      end
      @pull.reload

      @pull.stubs(:manual_review_requests_limit).returns 1

      @team.update!(
        review_request_delegation_count_members_already_requested: false,
        review_request_delegation_member_count: 4,
      )

      @pull.expects(:review_requested_for?).with(@team).once.returns(true)

      Team::ReviewRequestDelegation.delegate_to_members(
        actor: @pull.issue.modifying_user,
        pull_request: @pull,
        team: @team,
        strategy: :round_robin,
        max_auto_assigned_reviewers_count: @team.review_request_delegation_member_count
      )

      assert_equal 1, @pull.review_requests.count, "Has one review request"
      assert_equal 1, @pull.review_requests.not_dismissed.type_users.count, "Has one user request"
      assert_equal member_outside_of_team, @pull.review_requests.first.reviewer
    end

    test "respects plan limit for repos with reviewers when spaces are left" do
      member_outside_of_team = create(:user, login: "john")
      @org.add_member(member_outside_of_team)
      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob, AsyncNewsiesDeliveryJob]
      perform_enqueued_jobs(only: only) do
        @pull.request_review_from(actor: @org_member, reviewers: [member_outside_of_team])
      end
      @pull.reload

      @pull.stubs(:manual_review_requests_limit).returns 4

      @team.update!(
        review_request_delegation_count_members_already_requested: false,
        review_request_delegation_member_count: 4,
      )

      @pull.expects(:review_requested_for?).with(@team).once.returns(true)

      Team::ReviewRequestDelegation.delegate_to_members(
        actor: @pull.issue.modifying_user,
        pull_request: @pull,
        team: @team,
        strategy: :round_robin,
        max_auto_assigned_reviewers_count: @team.review_request_delegation_member_count
      )

      assert_equal 4, @pull.review_requests.count, "Has one review request"
      assert_equal 4, @pull.review_requests.not_dismissed.type_users.count, "Has one user request"
      assert_includes @pull.review_requests.pluck(:reviewer_id), member_outside_of_team.id
    end

    test "respects plan limit for repos with reviewers after reviews have already been left and then dismissed" do
      @org_member6 = create(:user, :verified)
      @org.add_member(@org_member6)

      @pull.stubs(:manual_review_requests_limit).returns 2

      @pull.request_review_from(actor: @org_member, reviewers: [@org_member6])
      review = create(:pull_request_review, pull_request: @pull, user: @org_member6)
      review.approve!
      review.dismiss!(@org_member)

      @pull.request_review_from(actor: @org_member, reviewers: [@org_member6], re_request: true, append: true)
      review = create(:pull_request_review, pull_request: @pull, user: @org_member6)
      review.approve!
      review.dismiss!(@org_member)

      # these two review requests shouldn't count towards the limit since they have been fulfilled by the now dismissed reviews
      assert_equal 2, @pull.reload.review_requests.type_users.count

      @pull.request_review_from(actor: @org_member, reviewers: [@team])

      assert_equal 3, @pull.reload.review_requests.type_users.count
      assert_equal 0, @pull.reload.review_requests.type_teams.count
    end
  end
end
