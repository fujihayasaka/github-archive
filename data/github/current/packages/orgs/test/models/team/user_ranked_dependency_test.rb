# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamUserRankedDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @repo = create(:repository, owner: @org, from_example: :merges)

    @employees, @pizza_penguin = create_pair(:public_team, organization: @org)
    [@employees, @pizza_penguin].each { |team| team.add_member(@user) }
  end

  context "team reviews requested" do
    test "ranks teams higher with team PR reviews requested from this user" do
      pr = create_pr(@repo, @user, branch: "add-a")

      # User requests a review from pizza-penguin
      @repo.add_team(@pizza_penguin, action: :write)
      create(:review_request, pull_request: pr, reviewer: @pizza_penguin)

      ranked_ids = Team.compute_ranked_ids(user: @user)

      assert_equal [@pizza_penguin.id, @employees.id], ranked_ids
    end

    test "doesn't count review requests older than the time window" do
      pr = create_pr(@repo, @user, branch: "add-a")

      # 2 years ago, user requested a review from employees
      @repo.add_team(@employees, action: :write)
      create(:review_request, created_at: 2.years.ago, pull_request: pr, reviewer: @employees)

      # User requests a review from pizza-penguin
      @repo.add_team(@pizza_penguin, action: :write)
      create(:review_request, pull_request: pr, reviewer: @pizza_penguin)

      ranked_ids = Team.compute_ranked_ids(user: @user)

      assert_equal [@pizza_penguin.id, @employees.id], ranked_ids
    end
  end

  context "team reviews fulfilled" do
    test "ranks teams higher with PR review requests fulfilled by this user" do
      pr_creator = create(:user)
      @pizza_penguin.add_member(pr_creator)
      pr = create_pr(@repo, pr_creator, branch: "add-a")

      # Other user requests a review from pizza-penguin
      @repo.add_team(@pizza_penguin, action: :write)
      request = create(:review_request, pull_request: pr, reviewer: @pizza_penguin)

      # User fulfills the pizza-penguin review request
      create(
        :pull_request_review,
        :commented,
        pull_request: pr, review_requests: [request], user: @user)

      ranked_ids = Team.compute_ranked_ids(user: @user)

      assert_equal [@pizza_penguin.id, @employees.id], ranked_ids
    end

    test "doesn't count fulfilled review requests older than the time window" do
      pr_creator = create(:user)
      @pizza_penguin.add_member(pr_creator)

      # Other user requested an old review from employees
      pr = create_pr(@repo, pr_creator, branch: "add-a")
      @repo.add_team(@employees, action: :write)
      employees_request = create(:review_request, created_at: 2.years.ago, pull_request: pr, reviewer: @employees)

      # User fulfilled the employees review request 2 years ago
      create(
        :pull_request_review,
        :commented,
        created_at: 2.years.ago, submitted_at: 2.years.ago, pull_request: pr, review_requests: [employees_request], user: @user)

      # Other user requests a new review from pizza-penguin
      pr = create_pr(@repo, pr_creator, branch: "add-b")
      @repo.add_team(@pizza_penguin, action: :write)
      pizza_penguin_request = create(:review_request, pull_request: pr, reviewer: @pizza_penguin)

      # User fulfills the pizza-penguin review request
      create(
        :pull_request_review,
        :commented,
        pull_request: pr, review_requests: [pizza_penguin_request], user: @user)

      ranked_ids = Team.compute_ranked_ids(user: @user)

      assert_equal [@pizza_penguin.id, @employees.id], ranked_ids
    end
  end

  context "team discussions" do
    test "ranks based on # of team discussions created by this user" do
      # User creates a pizza-penguin team discussion
      create(:discussion_post, team: @pizza_penguin, user: @user)

      ranked_ids = Team.compute_ranked_ids(user: @user)

      assert_equal [@pizza_penguin.id, @employees.id], ranked_ids
    end

    test "doesn't count team discussions created before the time window" do
      # User created an employees team discussion a long time ago
      create(:discussion_post, created_at: 2.years.ago, team: @pizza_penguin, user: @user)

      # User creates a pizza-penguin team discussion now
      create(:discussion_post, team: @pizza_penguin, user: @user)

      ranked_ids = Team.compute_ranked_ids(user: @user)

      assert_equal [@pizza_penguin.id, @employees.id], ranked_ids
    end
  end

  test "ranks teams correctly across multiple orgs" do
    create(:discussion_post, team: @pizza_penguin, user: @user)

    other_org = create(:organization)
    other_org_team = create(:public_team, organization: other_org)
    other_org_team.add_member(@user)

    # User creates two posts in other org's team, so it should be ranked highest
    create_pair(:discussion_post, team: other_org_team, user: @user)

    ranked_ids = Team.compute_ranked_ids(user: @user)

    assert_equal [other_org_team.id, @pizza_penguin.id, @employees.id], ranked_ids
  end

  test "cannot rank ancestor teams above child teams" do
    parent_team, child_team = create_pair(:public_team, organization: @org)
    child_team.parent_team = parent_team

    # User doesn't belong directly to parent team
    child_team.add_member(@user)

    # User creates two team discussions in parent team
    create_pair(:discussion_post, team: parent_team, user: @user)

    # User creates one team discussion in child team
    create(:discussion_post, team: child_team, user: @user)

    ranked_ids = Team.compute_ranked_ids(user: @user)

    assert_equal child_team.id, ranked_ids.first
  end

  def create_pr(repo, pr_creator, branch:)
    PullRequest.create_for(repo, title: "hello", user: pr_creator, base: "master", head: branch)
  end
end
