# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewRequestsDependencyTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @owner = create :user, login: "owner", plan: "large"
    @user = create(:user)
    @reviewer = create(:user, login: "reviewer")
    @org = create :organization, login: "acme", admin: @user, plan: "business", seats: 10
    @collab_1     = create :user, login: "collab-1"
    @collab_2     = create :user, login: "collab-2"
    @collab_3     = create :user, login: "collab-3"
    @team = create(:team, organization: @org, name: "Employee", privacy: :closed)
    @secret_team = create(:team, organization: @org, name: "Secret")
    @stranger = create(:user, login: "stranger")

    @repo = create :repository, owner: @org, from_example: :rebase_pull_request
    @repo.add_member @user
    @repo.add_member @collab_1
    @repo.add_member @collab_2
    @repo.add_member @collab_3, action: :read
    @repo.add_member @owner
    @team.add_member @collab_1
    @team.add_repository(@repo, :push)

    @issue = create(:issue, repository: @repo, user: @owner)

    @protected_branch = create(:protected_branch, repository: @repo, creator: @owner)

    @pull = create :pull_request,
      repository:       @repo,
      base_repository:  @repo,
      base_user:        @repo.owner,
      base_ref:         "master",
      head_repository:  @repo,
      head_user:        @repo.owner,
      head_ref:         "contrib",
      issue:            @issue,
      draft:            false

    make_trusted_oauth_apps_owner
    integration = Apps::Privileged::CopilotPullRequestReviewer.seed_database!
    PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :copilot_pull_request_reviewer, app: integration)
    @bot = ::Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
    disable_feature_flag(:copilot_reviews_automatic_pull_request_review_disabled, @user)
  end

  setup do
    reset_repo_root
    example_repo :rebase_pull_request, @repo
  end

  def commit_codeowners_file(contents, ref: "master")
    with_enqueued_pr_sync_jobs do
      @repo.refs.find(ref).append_commit({ message: "Add CODEOWNERS file", committer: @user }, @user) do |files|
        files.add("CODEOWNERS", contents)
      end
    end
  end

  def commit_readme_changes(pull, base_or_head)
    repo = pull.send(:"#{base_or_head}_repository")
    ref_name = pull.send(:"#{base_or_head}_ref")

    with_enqueued_pr_sync_jobs do
      repo.refs.find(ref_name).append_commit({ message: "Update README", committer: @user }, @user) do |files|
        files.add("README", "New content #{Time.now.to_i}")
      end
    end
  end

  context "#review_decision" do
    test "returns :approved when pull request has an approving review" do
      RuleEngine::PullRequestReviewRule::Decision.any_instance.stubs(:changes_requested?).returns(false)
      RuleEngine::PullRequestReviewRule::Decision.any_instance.stubs(:approved?).returns(true)

      assert_equal :approved, @pull.review_decision(viewer: @collab_1)
    end

    test "returns :changes_requested when pull request has had changes requested" do
      RuleEngine::PullRequestReviewRule::Decision.any_instance.stubs(:changes_requested?).returns(true)

      assert_equal :changes_requested, @pull.review_decision(viewer: @collab_1)
    end

    test "returns :review_required when pull request does not have reviews" do
      RuleEngine::PullRequestReviewRule::Decision.any_instance.stubs(:changes_requested?).returns(false)
      RuleEngine::PullRequestReviewRule::Decision.any_instance.stubs(:approved?).returns(false)
      RuleEngine::PullRequestReviewRule::Decision.any_instance.stubs(:more_reviews_required?).returns(true)
      @protected_branch.update!(pull_request_reviews_enforcement_level: :everyone)

      assert_equal :review_required, @pull.review_decision(viewer: @collab_1)
    end

    test "returns nil when pull request does not require a review" do
      RuleEngine::PullRequestReviewRule::Decision.any_instance.stubs(:changes_requested?).returns(false)
      RuleEngine::PullRequestReviewRule::Decision.any_instance.stubs(:approved?).returns(false)
      RuleEngine::PullRequestReviewRule::Decision.any_instance.stubs(:more_reviews_required?).returns(false)

      assert_nil @pull.review_decision(viewer: @collab_1)
    end
  end

  context "direct_review_request_for" do
    test "returns review request for user" do
      request = @pull.review_requests.create(reviewer: @user)
      assert_equal request, @pull.direct_review_request_for(@user)
      assert @pull.review_requested_for?(@user)
    end

    test "returns review request for user even on new pulls" do
      pull = PullRequest.new(
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: @repo,
        head_user: @repo.owner,
        head_ref: "contrib",
        issue: @issue,
        user: @repo.owner,
      )

      request = pull.review_requests.build(reviewer: @user)
      request2 = pull.review_requests.build(reviewer: @team)

      assert_equal request, pull.direct_review_request_for(@user)
      assert pull.review_requested_for?(@user), "review should be requested for user #{@user}"
      assert_equal request2, pull.direct_review_request_for(@team)
      assert pull.review_requested_for?(@team), "review should be requested for team #{@team}"
    end

    test "returns review request for team" do
      request = @pull.review_requests.create(reviewer: @team)
      assert_equal request, @pull.direct_review_request_for(@team)
      assert @pull.review_requested_for?(@team)
    end

    test "returns nil if no for team" do
      assert_nil @pull.direct_review_request_for(@team)
      refute @pull.review_requested_for?(@team)
    end

    test "returns nil if no for user" do
      assert_nil @pull.direct_review_request_for(@reviewer)
      refute @pull.review_requested_for?(@reviewer)
    end
  end

  context "deferred_copilot_review_requests" do
    test "auto-review enabled" do
      PullRequests::Copilot::CodeReviewAccess.any_instance.expects(:auto_reviewable?).returns(true)
      @pull.draft = true
      requests = @pull.deferred_copilot_review_requests([])
      assert_equal 1, requests.length
      assert_equal requests[0].reviewer, @bot
    end

    test "auto-review enabled and there's already a fulfilled request" do
      PullRequests::Copilot::CodeReviewAccess.any_instance.expects(:auto_reviewable?).returns(true)
      @pull.draft = true
      @pull.request_review_from(reviewers: [@bot], actor: @collab_1)
      @pull.reviews.create!(
        user: @bot,
        head_sha: @pull.head_sha,
        body: "review",
        state: PullRequestReview.state_value(:commented),
      )
      requests = @pull.deferred_copilot_review_requests([])
      assert_equal 0, requests.length
    end

    test "auto-review disabled" do
      @pull.draft = true
      PullRequests::Copilot::CodeReviewAccess.any_instance.expects(:auto_reviewable?).returns(false)
      assert_equal [], @pull.deferred_copilot_review_requests([])
    end
  end

  context "review_requests_for" do
    test "returns review requests for collab include teams collab is part of" do
      request = @pull.review_requests.create(reviewer: @collab_1)
      request2 = @pull.review_requests.create(reviewer: @team)

      assert_same_elements [request, request2], @pull.review_requests_for(@collab_1)
      assert @pull.review_requested_for?(@collab_1)
    end

    test "returns review request for team if user part of team" do
      request = @pull.review_requests.create(reviewer: @team)
      assert_equal [request], @pull.review_requests_for(@collab_1)
      assert @pull.review_requested_for?(@collab_1)
    end

    test "returns review request for team if user part of sub-team" do
      sub_team = create(:team, organization: @org, parent_team_id: @team.id, privacy: :closed)
      sub_team_member = create(:user)
      sub_team.add_member(sub_team_member)

      request = @pull.review_requests.create(reviewer: @team)
      assert_equal [request], @pull.review_requests_for(sub_team_member)
      assert @pull.review_requested_for?(sub_team_member)
    end

    test "returns only the pending review request for team if user part of team" do
      review = @pull.reviews.create(
        user: @collab_1,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )

      request1 = @pull.review_requests.create(reviewer: @team)
      request1.pull_request_reviews = [review]
      request1.save

      request = @pull.review_requests.create(reviewer: @team)
      request2 = @pull.review_requests.create(reviewer: @collab_1)

      assert_same_elements [request, request2], @pull.review_requests_for(@collab_1)
      assert @pull.review_requested_for?(@collab_1)
    end

    test "returns empty array if team member is PR author" do
      @team.add_member @pull.user, adder: @user

      request = @pull.review_requests.create(reviewer: @team)
      assert_equal [], @pull.review_requests_for(@pull.user)
      refute @pull.review_requested_for?(@pull.user)
    end

    test "returns review request for team" do
      request = @pull.review_requests.create(reviewer: @team)
      assert_equal [request], @pull.review_requests_for(@team)
      assert @pull.review_requested_for?(@team)
    end

    test "returns nil if no for user or team" do
      assert_empty @pull.review_requests_for(@reviewer)
      refute @pull.review_requested_for?(@reviewer)
    end
  end

  context "team_requests_on_behalf_of" do
    test "returns fulfilled review requests on this pull request for teams which this user is a member of" do
      review = @pull.reviews.create(
        user: @collab_1,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )

      review2 = @pull.reviews.create(
        user: @collab_1,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )

      request1 = @pull.review_requests.create(reviewer: @team)
      request1.pull_request_reviews = [review]
      request1.save

      request = @pull.review_requests.create(reviewer: @team)
      request.pull_request_reviews = [review2]
      request.save

      assert_same_elements [request], @pull.team_requests_on_behalf_of(@collab_1)
    end

    test "also considers membership in sub-teams" do
      sub_team = create(:team, organization: @org, parent_team_id: @team.id, privacy: :closed)
      sub_team_member = create(:user)
      sub_team.add_member(sub_team_member)

      review = @pull.reviews.create(
        user: sub_team_member,
        head_sha: @pull.head_sha,
      ).tap(&:approve!)

      request = @pull.review_requests.create(reviewer: @team, pull_request_reviews: [review])

      assert_same_elements [request], @pull.team_requests_on_behalf_of(sub_team_member)
    end
  end

  context "can_fulfill_a_pending_team_review_request?" do
    test "returns a boolean indicating if this user is part of a team which has a pending review request for this pull request" do
      request = @pull.review_requests.create(reviewer: @team)
      request1 = @pull.review_requests.create(reviewer: @team)

      assert @pull.can_fulfill_a_pending_team_review_request?(@collab_1)
    end

    test "also considers membership in sub-teams" do
      sub_team = create(:team, organization: @org, parent_team_id: @team.id, privacy: :closed)
      sub_team_member = create(:user)
      sub_team.add_member(sub_team_member)

      request = @pull.review_requests.create(reviewer: @team)

      assert @pull.can_fulfill_a_pending_team_review_request?(sub_team_member)
    end
  end

  context "request_review_from" do
    test "sets reviewers" do
      assert_empty @pull.review_requests.pending
      @pull.request_review_from(reviewers: [@user], actor: @owner)
      assert_equal [@user], @pull.review_requests.pending.reviewers
    end

    test "sets reviewers even if they already have a request" do
      review = @pull.reviews.create(
        user: @user,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )
      request = @pull.review_requests.create(reviewer: @user)
      request.pull_request_reviews = [review]
      request.save

      refute_empty @pull.review_requests.fulfilled
      assert_empty @pull.review_requests.pending

      @pull.request_review_from(reviewers: [@user], actor: @owner)
      assert_equal [@user], @pull.review_requests.pending.reviewers
    end

    test "sets reviewer if it is a team" do
      assert_empty @pull.review_requests.pending
      @pull.request_review_from(reviewers: [@user, @team], actor: @collab_1)
      assert_same_elements [@team, @user], @pull.review_requests.pending.reviewers
    end

    test "does not set team reviewer if plan doesn't allow it" do
      @pull.repository.expects(:plan_supports?).with(:team_review_requests).returns(false)
      assert_empty @pull.review_requests.pending
      @pull.request_review_from(reviewers: [@user, @team], actor: @collab_1)
      assert_same_elements [@user], @pull.review_requests.pending.reviewers
    end

    test "sets reviewer if it is a nestsed team" do
      child_team = create(:team, organization: @org, name: "child-team", privacy: :closed, parent_team_id: @team.id)
      child_child_team = create(:team, organization: @org, name: "child-child-team", privacy: :closed, parent_team_id: child_team.id)

      assert_empty @pull.review_requests.pending
      @pull.request_review_from(reviewers: [@user, @team, child_team, child_child_team], actor: @collab_1)
      assert_same_elements [@team, @user, child_team, child_child_team], @pull.review_requests.pending.reviewers
    end

    test "can not request from secret team" do
      assert_empty @pull.review_requests.pending
      @pull.request_review_from(reviewers: [@user, @secret_team], actor: @collab_1)
      assert_same_elements [@user], @pull.review_requests.pending.reviewers
    end

    test "sets reviewer but not team if can't request from team" do
      assert_empty @pull.review_requests.pending
      @pull.request_review_from(reviewers: [@user, @team], actor: @collab_2)
      assert_same_elements [@user], @pull.review_requests.pending.reviewers
    end

    test "does not remove existing team requests if reviewer does not have access to review" do
      @pull.request_review_from(reviewers: [@team], actor: @collab_1)

      team_reviewers = @pull.review_requests.pending.teams + [@collab_2]
      user_reviewers = @pull.review_requests.pending.users
      reviewers = user_reviewers + team_reviewers

      @pull.stubs(:can_request_team_review?).with(@collab_2).returns(false)
      @pull.request_review_from(reviewers: reviewers, actor: @collab_2)
      assert_same_elements [@collab_2, @team], @pull.review_requests.pending.reviewers
    end

    test "does not add new team requests if reviewer does not have access to review" do
      @pull.request_review_from(reviewers: [@team], actor: @collab_1)

      team_reviewers = @pull.review_requests.pending.teams + [@secret_team]
      user_reviewers = @pull.review_requests.pending.users
      reviewers = user_reviewers + team_reviewers

      @pull.stubs(:can_request_team_review?).with(@collab_2).returns(false)
      @pull.request_review_from(reviewers: reviewers, actor: @collab_2)
      assert_same_elements [@team], @pull.review_requests.pending.reviewers
    end

    test "clears review_requests (when empty)" do
      assert_empty @pull.review_requests.pending
      @pull.request_review_from(reviewers: [@user, @team], actor: @collab_1)
      refute_empty @pull.review_requests.pending
      @pull.request_review_from(reviewers: [], actor: @collab_1)
      @pull.reload
      assert_empty @pull.review_requests.pending
    end

    test "removes non-collab reviewers" do
      @pull.request_review_from(reviewers: [@user, @stranger, @team], actor: @user)
      assert_same_elements [@user, @team], @pull.review_requests.pending.reviewers
    end

    test "allows read access members to be requested" do
      @pull.request_review_from(reviewers: [@collab_3, @user], actor: @owner)
      assert_same_elements [@collab_3, @user], @pull.review_requests.pending.reviewers
    end

    test "does not allow read access members to request review if reviewer hasn't already reviewed PR" do
      repo_fork = create(:fork_repository, forker: @collab_3, fork_repo: @repo, from_example: :rebase_pull_request)
      pull = create(
        :pull_request,
        repository: @repo,
        base_repository: @repo,
        base_ref: "master",
        head_repository: repo_fork,
        head_ref: "contrib",
        user: repo_fork.owner,
      )

      pull.request_review_from(reviewers: [@user], actor: @collab_3, re_request: true)
      assert_empty pull.review_requests.pending.reviewers
    end

    test "allows read access members to re-request review" do
      repo_fork = create(:fork_repository, forker: @collab_3, fork_repo: @repo, from_example: :rebase_pull_request)
      pull = create(
        :pull_request,
        repository: @repo,
        base_repository: @repo,
        base_ref: "master",
        head_repository: repo_fork,
        head_ref: "contrib",
        user: repo_fork.owner,
      )
      review = pull.reviews.create(user: @user, head_sha: pull.head_sha, body: "review")
      review.comment!

      pull.request_review_from(reviewers: [@user], actor: @collab_3, re_request: true)
      assert_same_elements [@user], pull.review_requests.pending.reviewers
    end

    test "allows stranger to be requested as a reviewer on public repos if they have already left a review" do
      assert @pull.repository.public?

      review = @pull.reviews.create(
        user: @stranger,
        head_sha: @pull.head_sha,
        body: "review",
      )
      review.comment!

      @pull.request_review_from(reviewers: [@stranger], actor: @owner)
      assert_same_elements [@stranger], @pull.review_requests.pending.reviewers
    end

    test "does not allow stranger to be requested as a reviewer if they have not already left a review" do
      @pull.request_review_from(reviewers: [@stranger], actor: @owner)
      assert_empty @pull.review_requests.pending.reviewers
    end

    test "ignores requests from strangers" do
      @pull.request_review_from(reviewers: [@user, @team], actor: @stranger)
      assert_empty @pull.review_requests.pending.reviewers
    end

    test "allows requests from strangers if it's been delegated" do
      @pull.request_review_from(reviewers: [@user, @team], actor: @stranger, via_delegation: true)
      assert_same_elements [@user, @team], @pull.review_requests.pending.reviewers
    end

    test "allows requests from strangers if it's a re-request and the stranger is the PR author" do
      repo_fork = create(:fork_repository, forker: @stranger, fork_repo: @repo, from_example: :rebase_pull_request)
      pull = create(
        :pull_request,
        repository: @repo,
        base_repository: @repo,
        base_ref: "master",
        head_repository: repo_fork,
        head_ref: "contrib",
        user: repo_fork.owner,
      )
      review = pull.reviews.create(user: @user, head_sha: pull.head_sha, body: "review")
      review.comment!

      pull.request_review_from(reviewers: [@user], actor: @stranger, re_request: true)
      assert_same_elements [@user], pull.review_requests.pending.reviewers
    end

    test "ignores requests from strangers with no re-request flag" do
      repo_fork = create(:fork_repository, forker: @stranger, fork_repo: @repo, from_example: :rebase_pull_request)
      pull = create(
        :pull_request,
        repository: @repo,
        base_repository: @repo,
        base_ref: "master",
        head_repository: repo_fork,
        head_ref: "contrib",
        user: repo_fork.owner,
      )

      pull.request_review_from(reviewers: [@user], actor: @stranger)
      assert_empty pull.review_requests.pending.reviewers
    end

    test "do not allow request from blocked user" do
      # set up a user that has blocked the owner
      userthathasblockedowner = create :user, login: "userthathasblockedowner"
      userthathasblockedowner.block(@owner)
      @repo.add_member userthathasblockedowner

      @pull.request_review_from(reviewers: [@collab_2, userthathasblockedowner], actor: @owner)
      assert_same_elements [@collab_2], @pull.review_requests.pending.reviewers
    end

    test "sets reviewers if PR author is deleted" do
      @pull.user.destroy
      @pull.reload
      @pull.request_review_from(reviewers: [@user], actor: @owner)
      assert_equal [@user], @pull.review_requests.pending.reviewers
    end

    test "private repos in free orgs limit review requests to single reviewer" do
      org = create :organization, admin: @owner, plan: "free"
      private_repo = create :private_repository, owner: org, from_example: :rebase_pull_request

      private_repo.add_member @user
      private_repo.add_member @collab_1

      private_pull = create :pull_request,
        repository:       private_repo,
        base_repository:  private_repo,
        base_user:        private_repo.owner,
        base_ref:         "master",
        head_repository:  private_repo,
        head_user:        private_repo.owner,
        head_ref:         "contrib",
        issue:            create(:issue, repository: private_repo, user: @owner)

      assert_equal 1, private_pull.manual_review_requests_limit

      private_pull.request_review_from(reviewers: [@user, @collab_1], actor: @owner)
      assert_equal [@user], private_pull.review_requests.pending.reviewers
    end

    test "public repos in business plus plans allow 100 review requests" do
      enterprise_org = create :organization, admin: @owner, plan: "business_plus"
      public_repo = create :repository, owner: enterprise_org, from_example: :rebase_pull_request

      public_repo.add_member @user
      public_repo.add_member @collab_1

      public_pull = create :pull_request,
        repository:       public_repo,
        base_repository:  public_repo,
        base_user:        public_repo.owner,
        base_ref:         "master",
        head_repository:  public_repo,
        head_user:        public_repo.owner,
        head_ref:         "contrib",
        issue:            create(:issue, repository: public_repo, user: @owner)

      assert_equal 100, public_pull.manual_review_requests_limit
    end

    test "private repos in business plus plans allow 100 review requests" do
      enterprise_org = create :organization, admin: @owner, plan: "business_plus"
      private_repo = create :private_repository, owner: enterprise_org, from_example: :rebase_pull_request

      private_repo.add_member @user
      private_repo.add_member @collab_1

      private_pull = create :pull_request,
        repository:       private_repo,
        base_repository:  private_repo,
        base_user:        private_repo.owner,
        base_ref:         "master",
        head_repository:  private_repo,
        head_user:        private_repo.owner,
        head_ref:         "contrib",
        issue:            create(:issue, repository: private_repo, user: @owner)

      assert_equal 100, private_pull.manual_review_requests_limit
    end

    test "public repos in GHES allow 100 review requests", enterprise_only: true do
      enterprise_org = create :enterprise_linked_organization, admin: @owner, plan: "enterprise"
      public_repo = create :repository, owner: enterprise_org, from_example: :rebase_pull_request

      public_repo.add_member @user
      public_repo.add_member @collab_1

      public_pull = create :pull_request,
        repository:       public_repo,
        base_repository:  public_repo,
        base_user:        public_repo.owner,
        base_ref:         public_repo.default_branch,
        head_repository:  public_repo,
        head_user:        public_repo.owner,
        head_ref:         "contrib",
        issue:            create(:issue, repository: public_repo, user: @owner)

      assert_equal 100, public_pull.manual_review_requests_limit
    end

    test "private repos in GHES allow 100 review requests", enterprise_only: true do
      enterprise_org = create :enterprise_linked_organization, admin: @owner, plan: "enterprise"
      private_repo = create :private_repository, owner: enterprise_org, from_example: :rebase_pull_request

      private_repo.add_member @user
      private_repo.add_member @collab_1

      private_pull = create :pull_request,
        repository:       private_repo,
        base_repository:  private_repo,
        base_user:        private_repo.owner,
        base_ref:         private_repo.default_branch,
        head_repository:  private_repo,
        head_user:        private_repo.owner,
        head_ref:         "contrib",
        issue:            create(:issue, repository: private_repo, user: @owner)

      assert_equal 100, private_pull.manual_review_requests_limit
    end
  end

  context ".latest_fulfilled_reviews_count_for" do
    test "return nothing when PR has no reviews" do
      results = PullRequest.latest_fulfilled_reviews_count_for(pull_request_ids: [@pull.id])
      assert_equal({}, results)
    end

    test "returns count of 1 when there is just a review with no review request" do
      @pull.reviews.create!(
        user: @user,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )

      results = PullRequest.latest_fulfilled_reviews_count_for(pull_request_ids: [@pull.id])
      assert_equal({ @pull.id => 1 }, results)
    end

    test "returns count of 1 when there is a review with a related review request" do
      @pull.request_review_from(reviewers: [@user], actor: @collab_1)
      review = @pull.reviews.create!(
        user: @user,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )
      request = @pull.review_requests.where(reviewer_id: @user.id).first!
      request.pull_request_reviews = [review]
      request.save!

      results = PullRequest.latest_fulfilled_reviews_count_for(pull_request_ids: [@pull.id])
      assert_equal({ @pull.id => 1 }, results)
    end

    test "returns count of 1 when there is a review with a related review request for the reviewer's team" do
      @pull.request_review_from(reviewers: [@team], actor: @collab_1)
      @pull.reviews.create!(
        user: @user,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )

      results = PullRequest.latest_fulfilled_reviews_count_for(pull_request_ids: [@pull.id])
      assert_equal({ @pull.id => 1 }, results)
    end

    test "returns nothing when there is a pending review request" do
      @pull.request_review_from(reviewers: [@user], actor: @collab_1)
      results = PullRequest.latest_fulfilled_reviews_count_for(pull_request_ids: [@pull.id])
      assert_equal({}, results)
    end

    test "returns nothing when there is a fulfilled request that got re-requested" do
      @pull.request_review_from(reviewers: [@user], actor: @collab_1)
      @pull.reviews.create!(
        user: @user,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )
      @pull.request_review_from(reviewers: [@user], actor: @collab_1, re_request: true)

      results = PullRequest.latest_fulfilled_reviews_count_for(pull_request_ids: [@pull.id])
      assert_equal({}, results)
    end

    test "returns the fulfilled review count when the related review request is dismissed" do
      @pull.request_review_from(reviewers: [@user], actor: @collab_1)
      @pull.reviews.create!(
        user: @user,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )
      @pull.request_review_from(reviewers: [@user], actor: @collab_1, re_request: true)
      review_request = @pull.review_requests.where(reviewer_id: @user.id).first!
      review_request.dismiss
      review_request.save!

      results = PullRequest.latest_fulfilled_reviews_count_for(pull_request_ids: [@pull.id])
      assert_equal({ @pull.id => 1 }, results)
    end

    test "returns fulfilled reviews for multiple PR's" do
      other_issue = create(:issue, repository: @repo, user: @owner)
      other_pull = create :pull_request,
        repository:       @repo,
        base_repository:  @repo,
        base_user:        @repo.owner,
        base_ref:         "master",
        head_repository:  @repo,
        head_user:        @repo.owner,
        head_ref:         "wacky",
        issue:            other_issue,
        draft:            false

      other_pr_review = other_pull.reviews.create!(
        user: @reviewer,
        head_sha: other_pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )

      @pull.reviews.create!(
        user: @reviewer,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )

      @pull.reviews.create!(
        user: @user,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )
      @pull.review_requests.create(reviewer: @user)

      # includes one fulfilled review per PR
      results = PullRequest.latest_fulfilled_reviews_count_for(pull_request_ids: [@pull.id, other_pull.id])
      assert_equal({ @pull.id => 1, other_pull.id => 1 }, results)
    end
  end

  context "latest_reviews_not_requested" do
    test "returns a list of reviews that do not also have requests" do
      review1 = @pull.reviews.create!(
        user: @reviewer,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )
      review2 = @pull.reviews.create!(
        user: @user,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )

      review3 = @pull.reviews.create!(
        user: @user,
        head_sha: @pull.head_sha,
      )

      @pull.review_requests.create(reviewer: @user)

      @pull.reload
      assert_equal [review1], @pull.latest_reviews_not_requested
    end

    test "returns a list of reviews even if request exist but has review id" do
      review1 = @pull.reviews.create!(
        user: @reviewer,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )
      review2 = @pull.reviews.create!(
        user: @user,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )

      review3 = @pull.reviews.create!(
        user: @user,
        head_sha: @pull.head_sha,
      )

      request = @pull.review_requests.create(reviewer: @user)
      request.pull_request_reviews = [review2]
      request.save

      assert_same_elements @pull.latest_reviews_not_requested, [review1, review2]
    end

    test "returns a empty array if user does not exist" do
      review = @pull.reviews.create!(
        user: @reviewer,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved),
      )
      @owner.destroy
      @pull.reload

      assert_equal [], @pull.latest_reviews_not_requested
    end

    test "does not return reply reviews" do
      review1 = @pull.pending_review_for(user: @reviewer)
      thread, comment = review1.build_thread_with_comment(
        body: "insightful!",
        position: 1,
        path: "README",
        user: @reviewer,
      )
      comment.save!
      review1.approve!

      review2 = create(:pull_request_review, pull_request: @pull,
        user: @user,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved)
      )

      reply_review = create(:pull_request_review, pull_request: @pull,
        head_sha: @pull.head_sha,
        user: @user
      )

      comment.pull_request_review_thread.build_reply(
        pull_request_review: reply_review,
        body: "hola",
      )
      comment.save!
      reply_review.comment!

      @pull.review_requests.create(reviewer: @user)

      @pull.reload
      assert_equal [review1], @pull.latest_reviews_not_requested
    end

    test "returns a list of reviews even after dismissal" do
      @pull.request_review_from(reviewers: [@user], actor: @collab_1)
      @pull.request_review_from(reviewers: [], actor: @collab_1)
      review = @pull.reviews.create!(
          user: @user,
          head_sha: @pull.head_sha,
          state: PullRequestReview.state_value(:approved),
      )
      @pull.reload
      assert_equal [review], @pull.latest_reviews_not_requested
    end
  end

  context "sorted_reviewers" do
    test "floats requests towards top even on new" do
      pull = PullRequest.new(
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: @repo,
        head_user: @repo.owner,
        head_ref: "contrib",
        issue: @issue,
        user: @repo.owner,
      )

      request = pull.review_requests.build(reviewer: @user)
      request2 = pull.review_requests.build(reviewer: @team)

      assert_equal [@collab_1, @user, @team, @collab_2, @collab_3, @owner],
        pull.sorted_reviewers(@collab_1)
    end

    test "includes nested teams" do
      p_team = create(:team, organization: @org, name: "parent-team", privacy: :closed)
      p_team.add_repository(@repo, :push)
      child_team = create(:team, organization: @org, name: "child-team", privacy: :closed, parent_team_id: @team.id)
      child_child_team = create(:team, organization: @org, name: "child-child-team", privacy: :closed, parent_team_id: child_team.id)
      p_team_child = create(:team, organization: @org, name: "p-team-child", privacy: :closed, parent_team_id: p_team.id)

      assert_equal [@collab_1, @collab_2, @collab_3, @user, child_child_team, child_team, @team, p_team_child, p_team], @pull.sorted_reviewers(@collab_1)
    end

    test "includes current user at the top" do
      assert_equal [@collab_1, @collab_2, @collab_3, @user, @team], @pull.sorted_reviewers(@collab_1)
    end

    test "does not error if no teams" do
      @team.destroy

      assert_equal [@collab_1, @collab_2, @collab_3, @user], @pull.sorted_reviewers(@collab_1)
    end

    test "does not include team if user can request teams" do
      assert_equal [@collab_2, @collab_1, @collab_3, @user], @pull.sorted_reviewers(@collab_2)
    end

    test "includes requested user at the top (when logged out)" do
      @pull.request_review_from(reviewers: [@collab_3], actor: @owner)

      assert_equal [@collab_3, @collab_1, @collab_2, @user], @pull.sorted_reviewers(nil)
    end

    test "includes current user then requested user at the top (when logged in)" do
      @pull.request_review_from(reviewers: [@collab_2], actor: @owner)

      assert_equal [@user, @collab_2, @collab_1, @collab_3, @team], @pull.sorted_reviewers(@user)
    end

    test "includes requested first (after current user)" do
      @pull.request_review_from(reviewers: [@collab_2, @collab_3], actor: @owner)

      assert_equal [@user, @collab_2, @collab_3, @collab_1, @team], @pull.sorted_reviewers(@user)
    end

    test "doesn't include suspended users" do
      @collab_2.suspend "for reasons"
      assert_equal [@collab_1, @collab_3, @user, @team], @pull.sorted_reviewers(@collab_1)
    end
  end

  context "sorted_reviewers_with_search_query" do
    test "filters correctly to search query for users" do
      pull = PullRequest.new(
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: @repo,
        head_user: @repo.owner,
        head_ref: "contrib",
        issue: @issue,
        user: @repo.owner,
      )

      assert_equal [@collab_1, @collab_2, @collab_3], pull.sorted_reviewers(@collab_1, search_query: "collab")
    end

    test "filters correctly to search query for teams" do
      pull = PullRequest.new(
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: @repo,
        head_user: @repo.owner,
        head_ref: "contrib",
        issue: @issue,
        user: @repo.owner,
      )

      assert_equal [@team], pull.sorted_reviewers(@collab_1, search_query: "Employee")
      assert_equal [@team], pull.sorted_reviewers(@collab_1, search_query: "employEE")
      assert_equal [], pull.sorted_reviewers(@collab_1, search_query: "Employeeeeee")
    end

    test "includes nested teams with search query" do
      p_team = create(:team, organization: @org, name: "parent-team", privacy: :closed)
      p_team.add_repository(@repo, :push)
      child_team = create(:team, organization: @org, name: "child-team", privacy: :closed, parent_team_id: @team.id)
      child_child_team = create(:team, organization: @org, name: "child-child-team", privacy: :closed, parent_team_id: child_team.id)
      p_team_child = create(:team, organization: @org, name: "p-team-child", privacy: :closed, parent_team_id: p_team.id)

      assert_equal [child_child_team, child_team, p_team_child, p_team], @pull.sorted_reviewers(@collab_1, search_query: "team")
    end
  end

  context "visible_sidebar_reviews" do
    if GitHub.spamminess_check_enabled?
      test "does not return spammy reviews" do
        @reviewer.mark_as_spammy

        review1 = create(:pull_request_review, pull_request: @pull,
          user: @reviewer,
          head_sha: @pull.head_sha,
          state: PullRequestReview.state_value(:approved)
        )
        review2 = create(:pull_request_review, pull_request: @pull,
          user: @user,
          head_sha: @pull.head_sha,
          state: PullRequestReview.state_value(:approved)
        )

        @pull.reload
        assert_equal [review2], @pull.visible_sidebar_reviews(@user)
      end
    end
  end

  context "visible_sidebar_requests" do
    if GitHub.spamminess_check_enabled?
      test "does not return team requests if user can not view" do
        request = @pull.review_requests.build(reviewer: @team)
        request1 = @pull.review_requests.build(reviewer: @collab_1)
        request.save!
        request1.save!
        requests = [request, request1]

        assert_equal [request1], @pull.visible_sidebar_requests(@stranger, requests)
      end

      test "does not return team requests if user is nil" do
        request = @pull.review_requests.build(reviewer: @team)
        request1 = @pull.review_requests.build(reviewer: @collab_1)
        request.save!
        request1.save!
        requests = [request, request1]

        assert_equal [request1], @pull.visible_sidebar_requests(nil, requests)
      end

      test "returns team requests if user can view" do
        request = @pull.review_requests.build(reviewer: @team)
        request.save!
        requests = [request]

        assert_equal [request], @pull.visible_sidebar_requests(@user, requests)
      end

      test "does not return spammy requests" do
        request = @pull.review_requests.build(reviewer: @collab_3)
        @collab_3.mark_as_spammy
        requests = [request]

        assert_empty @pull.visible_sidebar_requests(@user, requests)
      end

      test "does not return requests if reviewer is nil" do
        request = @pull.review_requests.build(reviewer: nil)
        requests = [request]

        assert_empty @pull.visible_sidebar_requests(@user, requests)

      end
    end
  end

  context "can_request_review?" do
    test "triage role allows request of pr review" do
      @pull.request_review_from(reviewers: [@user], actor: @collab_3)

      assert_empty @pull.review_requests
      refute_equal [@user], @pull.review_requests.pending.reviewers

      @repo.remove_member @collab_3
      @repo.add_member @collab_3, action: :triage

      @pull.request_review_from(reviewers: [@user], actor: @collab_3)

      refute_empty @pull.review_requests
      assert_equal [@user], @pull.review_requests.pending.reviewers
    end
    test "returns false when no user is provided" do
      Platform::Loaders::Permissions::BatchAuthorize.expects(:load).never
      refute @pull.can_request_review?(nil)
    end
  end

  context "can_re_request_review?" do
    test "PR author with read permission can re-request review" do
      repo_fork = create(:fork_repository, forker: @collab_3, fork_repo: @repo, from_example: :rebase_pull_request)
      pull = create(
        :pull_request,
        repository: @repo,
        base_repository: @repo,
        base_ref: "master",
        head_repository: repo_fork,
        head_ref: "contrib",
        user: repo_fork.owner,
      )

      refute pull.can_request_review?(@collab_3)
      assert pull.can_re_request_review?(@collab_3)
    end
  end

  context "pending_review_requests" do
    test "does not include deleted teams" do
      team_to_be_deleted = create(:team, organization: @org, name: "Delete Me!", privacy: :closed)
      team_to_be_deleted.add_member @user
      team_to_be_deleted.add_repository(@repo, :push)

      request = @pull.review_requests.build(reviewer: team_to_be_deleted)
      request.save!

      perform_enqueued_jobs(only: [DestroyTeamDependantsJob]) { team_to_be_deleted.destroy }
      assert_empty @pull.pending_review_requests
    end

    # https://github.com/github/pe-pull-requests/issues/434
    test "filters out erroneous duplicate review requests" do
      first = @pull.review_requests.build(reviewer: @reviewer, repository_id: @pull.repository.id)
      first.save(validate: false)
      second = @pull.review_requests.build(reviewer: @reviewer, repository_id: @pull.repository.id)
      second.save(validate: false)

      assert_same_elements [first, second], @pull.review_requests
      assert_same_elements [first], @pull.pending_review_requests.to_a
    end
  end

  context "user_requesting" do
    test "returns the latest request" do
      @pull.events.create!(
        event: "review_requested",
        actor_id: @collab_1.id,
        subject: @collab_2)
      assert_equal @collab_1, @pull.user_requesting(@collab_2)
    end
  end

  context "codeowners" do
    test "requests review from codeowners with reasons" do
      commit_codeowners_file(<<~CODEOWNERS)
        * @collab-1 @#{@team}

        *.js @collab-2
        README @#{@team}
      CODEOWNERS
      commit_readme_changes @pull, :head

      assert request = @pull.direct_review_request_for(@collab_1)
      assert_equal 1, request.reasons.count
      assert reason = request.reasons.first
      assert_equal @repo.default_oid, reason.codeowners_tree_oid
      assert_equal "CODEOWNERS", reason.codeowners_path
      assert_equal 1, reason.codeowners_line
      assert_equal "*", reason.codeowners_pattern

      assert request = @pull.direct_review_request_for(@team)
      assert_equal 2, request.reasons.count
      assert_same_elements [1, 4], request.reasons.map(&:codeowners_line)
      assert_same_elements ["*", "README"], request.reasons.map(&:codeowners_pattern)
    end

    test "request review from owners file" do
      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1 @#{@team}

        *.js @collab-2
      CODEOWNERS

      refute @pull.direct_review_request_for(@collab_1)
      refute @pull.direct_review_request_for(@team)

      commit_readme_changes @pull, :head

      @pull.reload
      assert_same_elements [@collab_1, @team], @pull.codeowners.to_a

      assert @pull.direct_review_request_for(@collab_1)
      assert @pull.direct_review_request_for(@team)
    end

    test "raises error when checking codeowners does" do
      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1 @#{@team}

        *.js @collab-2
      CODEOWNERS

      @pull.expects(:codeowners!).once.raises(PullRequest::DetermineCodeownersError.new(nil))

      assert_raises(PullRequest::DetermineCodeownersError) do
        @pull.request_review_from_codeowners(@pull.user)
      end
    end

    test "doesn't duplicate review request reasons" do
      commit_codeowners_file(<<~CODEOWNERS)
        *  @#{@team}
      CODEOWNERS
      commit_readme_changes @pull, :head

      assert request = @pull.direct_review_request_for(@team)
      assert_equal 1, request.reasons.count
      assert reason = request.reasons.first
      assert_equal @repo.default_oid, reason.codeowners_tree_oid
      assert_equal "CODEOWNERS", reason.codeowners_path
      assert_equal 1, reason.codeowners_line
      assert_equal "*", reason.codeowners_pattern
    end

    test "doesn't request review if WIP" do
      @pull.update_attribute(:draft, true)
      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1 @#{@team}

        *.js @collab-2
      CODEOWNERS
      commit_readme_changes @pull, :head

      assert_equal 0, @pull.review_requests.size

      perform_enqueued_jobs(only: [RequestPullRequestReviewersJob]) do
        @pull.ready_for_review!(user: @pull.user)
      end

      @pull.reload
      assert_same_elements [@collab_1, @team], @pull.codeowners.to_a

      assert @pull.direct_review_request_for(@collab_1)
      assert @pull.direct_review_request_for(@team)
    end

    test "requests review from multiple team owners" do
      @team2 = create(:team, organization: @org, privacy: :closed)
      @team2.add_repository(@repo, :push)

      commit_codeowners_file(<<~CODEOWNERS)
        *  @#{@team} @#{@team2}
      CODEOWNERS

      refute @pull.direct_review_request_for(@team)
      refute @pull.direct_review_request_for(@team2)

      commit_readme_changes @pull, :head

      @pull.reload
      assert_same_elements [@team, @team2], @pull.codeowners.to_a

      assert @pull.direct_review_request_for(@team)
      assert @pull.direct_review_request_for(@team2)
    end

    test "request review from owners file but does not replace already set requests" do
      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1

        *.js @collab-2
      CODEOWNERS

      @pull.review_requests.create(reviewer: @user)

      assert @pull.direct_review_request_for(@user)
      refute @pull.direct_review_request_for(@collab_1)

      commit_readme_changes @pull, :head

      @pull.reload
      assert_same_elements [@collab_1], @pull.codeowners.to_a

      assert @pull.direct_review_request_for(@collab_1)
      assert @pull.direct_review_request_for(@user)
    end

    test "request review from owners file that already exists does not double request" do
      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1 @collab-2
      CODEOWNERS

      @pull.review_requests.create(reviewer: @collab_1)

      assert @pull.direct_review_request_for(@collab_1)
      refute @pull.direct_review_request_for(@collab_2)

      commit_readme_changes @pull, :head

      @pull.reload
      assert_same_elements [@collab_1, @collab_2], @pull.codeowners.to_a

      assert @pull.direct_review_request_for(@collab_1)
      assert_equal 1, (@pull.review_requests.pending.select { |request| request.reviewer == @collab_1 }).size
    end

    test "does not request review from owner if can't be requested" do
      commit_codeowners_file(<<~CODEOWNERS)
        *  @reviewer @collab-1

        *.js @collab-2
      CODEOWNERS

      refute @pull.direct_review_request_for(@reviewer)
      refute @pull.direct_review_request_for(@collab_1)

      commit_readme_changes @pull, :head

      @pull.reload
      assert_same_elements [@collab_1], @pull.codeowners.to_a

      refute @pull.direct_review_request_for(@reviewer)
      assert @pull.direct_review_request_for(@collab_1)
    end

    test "does not request review from owner if they've already reviewed" do
      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1 @collab-2
      CODEOWNERS

      refute @pull.direct_review_request_for(@collab_1)
      refute @pull.direct_review_request_for(@collab_2)

      review = create(:pull_request_review, pull_request: @pull,
        user: @collab_1,
        head_sha: @pull.head_sha,
        state: PullRequestReview.state_value(:approved)
      )
      @pull.reload
      assert @pull.latest_non_pending_review_for(@collab_1)

      commit_readme_changes @pull, :head

      @pull.reload
      assert_same_elements [@collab_1, @collab_2], @pull.codeowners.to_a

      refute @pull.direct_review_request_for(@collab_1)
      assert @pull.direct_review_request_for(@collab_2)
    end

    test "does NOT request review from team owner if a previous request was fulfilled" do
      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-2 @#{@team}
      CODEOWNERS

      request = @pull.review_requests.create! reviewer: @team
      review = create(:pull_request_review, pull_request: @pull,
        user: @collab_1,
        head_sha: @pull.head_sha
      )
      review.approve!

      assert_includes request.pull_request_reviews.reload, review
      @pull.reload

      refute @pull.direct_review_request_for(@collab_2)
      refute @pull.direct_review_request_for(@team)

      commit_readme_changes @pull, :head

      @pull.reload
      assert_same_elements [@collab_2, @team], @pull.codeowners.to_a

      assert @pull.direct_review_request_for(@collab_2)
      refute @pull.direct_review_request_for(@team)
    end

    test "requests review from owner even if a previous manual request was dismissed" do
      dismissed_request = @pull.review_requests.create!(reviewer: @collab_1)
      dismissed_request.dismiss
      dismissed_request.save!

      commit_codeowners_file(<<~CODEOWNERS)
        * @collab-1 @#{@team}

        *.js @collab-2
      CODEOWNERS

      refute @pull.direct_review_request_for(@collab_1)
      refute @pull.direct_review_request_for(@team)

      commit_readme_changes @pull, :head

      @pull.reload
      assert_same_elements [@collab_1, @team], @pull.codeowners.to_a

      assert @pull.direct_review_request_for(@collab_1)
      assert @pull.direct_review_request_for(@team)
    end

    test "does NOT request review from owner if a previous automated request was dismissed" do
      commit_codeowners_file(<<~CODEOWNERS)
        * @collab-1 @#{@team}

        *.js @collab-2
      CODEOWNERS

      dismissed_request = @pull.review_requests.create! \
        reviewer: @collab_1,
        reasons_by_type: { codeowners: [
          { tree_oid: @pull.head_sha, path: "CODEOWNERS", line: 42, pattern: "*" },
        ] }
      dismissed_request.dismiss
      dismissed_request.save!

      refute @pull.direct_review_request_for(@collab_1)
      refute @pull.direct_review_request_for(@team)

      commit_readme_changes @pull, :head

      @pull.reload
      assert_same_elements [@collab_1, @team], @pull.codeowners.to_a

      refute @pull.direct_review_request_for(@collab_1)
      assert @pull.direct_review_request_for(@team)
    end

    test "does not request review from owners file when base ref is updated, only head ref" do
      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1
      CODEOWNERS

      commit_readme_changes @pull, :base

      @pull.reload
      refute @pull.review_requested_for?(@collab_1)

      commit_readme_changes @pull, :head

      @pull.reload
      assert @pull.review_requested_for?(@collab_1)
    end

    test "requests review from owners file when changing base" do
      commit_codeowners_file(<<~CODEOWNERS)
        *.md  @collab-1
      CODEOWNERS

      base_branch = @repo.heads.find("master")
      topic_branch = @repo.heads.create("topic-branch", base_branch.commit.oid, @user)
      commit = topic_branch.append_commit({ message: "Update owned file", committer: @user }, @user) do |files|
        files.add("code-owned.md", "add code owned file")
      end
      topic_branch_forward = @repo.heads.create("topic-branch-forward", commit.oid, @user)
      topic_branch_forward.append_commit({ message: "Update not owned file", committer: @user }, @user) do |files|
        files.add("not-code-owned", "add unowned file")
      end

      issue = create(:issue, user: @user, repository: @repo)
      pull = PullRequest.create_for!(
        @repo,
        base: "topic-branch",
        head: "topic-branch-forward",
        user: issue.user,
        issue: issue
      )

      refute pull.reload.review_requested_for?(@collab_1)

      # reset memoized attributes on the pull request
      PullRequest.find(pull.id).change_base_branch(@user, "master")

      assert pull.reload.review_requested_for?(@collab_1)
    end

    test "does not request review from owners file when base ref is updated and the sync job is delayed" do
      commit_codeowners_file(<<~CODEOWNERS)
        *.md  @collab-1
      CODEOWNERS

      # Intentionally don't run the PullRequestSynchronizationJob job so we can simulate them being excuted out of order.
      @pull.base_repository.refs.find(@pull.base_ref).append_commit({ message: "Update not-owned file", committer: @user }, @user) do |files|
        files.add("not-owned", "New content #{Time.now.to_i}")
      end
      refute @pull.reload.review_requested_for?(@collab_1)

      @pull.head_repository.refs.find(@pull.head_ref).append_commit({ message: "Update owned file", committer: @user }, @user) do |files|
        files.add("owned.md", "New content #{Time.now.to_i}")
      end
      refute @pull.reload.review_requested_for?(@collab_1)

      perform_enqueued_jobs(only: [SynchronizePullRequestJob]) do
        PullRequestSynchronizationJob.new.perform(@pull.base_repository, "refs/heads/#{@pull.base_ref}", @user)
        refute @pull.review_requested_for?(@collab_1)

        PullRequestSynchronizationJob.new.perform(@pull.head_repository, "refs/heads/#{@pull.head_ref}", @user, forced: true)
        assert @pull.reload.review_requested_for?(@collab_1)
      end
    end

    test "instruments a pull_request.synchronize event when the head ref moves" do
      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1
      CODEOWNERS
      commit_readme_changes @pull, :head
      @pull.reload
      assert @pull.direct_review_request_for(@collab_1)

      events = subscribe "pull_request.synchronize"
      # Keep track of the current head SHA, as that will be our "before" after
      # head moves.
      previous_head_sha = @pull.head_sha

      commit_readme_changes @pull, :head

      @pull.reload
      expected_payload = {
        pull_request_id: @pull.id,
        pull_request_url: @pull.permalink,
        pull_request_title: @pull.title,
        issue_id: @issue.id,
        actor: @user.login,
        actor_id: @user.id,
        before: previous_head_sha,
        after: @pull.head_sha,
        spammy: false,
        allowed: true,
        approved_before: nil,
        approved_after: nil,
        org: @org.name,
        org_id: @org.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @owner.login,
        user_id: @owner.id,
      }

      assert event = events.pop, "expected an instrumentation event"
      assert_subset_hash expected_payload, event.payload
    end

    test "requests review async from owners when the PR is created" do
      enable_feature_flag(:copilot_reviews_automatic_pull_request_review_disabled, @user)
      disable_feature_flag(:notifyd_pull_request_notify)

      commit_codeowners_file(<<~CODEOWNERS)
        README  @collab-1
        *.js    @collab-2
      CODEOWNERS

      pull = T.let(nil, T.nilable(PullRequest))
      assert_performed_with(job: RequestPullRequestReviewersJob) do
        pull = PullRequest.create_for! @repo,
          base: "acme:master",
          head: "acme:readme-title",
          user: @user,
          title: "Update README title"
      end

      pull&.reload

      assert_equal [@collab_1], T.unsafe(pull&.review_requests).pending.reviewers
    end

    test "requests review from owners when the PR is created in addition to ones manually requested" do
      enable_feature_flag(:copilot_reviews_automatic_pull_request_review_disabled, @user)
      commit_codeowners_file(<<~CODEOWNERS)
        README  @collab-1
        *.js    @collab-2
      CODEOWNERS

      pull = T.let(nil, T.nilable(PullRequest))
      perform_enqueued_jobs(only: RequestPullRequestReviewersJob) do
        pull = PullRequest.create_for! @repo,
          base: "acme:master",
          head: "acme:readme-title",
          user: @user,
          title: "Update README title",
          reviewer_user_ids: [@owner.id]
      end

      pull&.reload

      assert_same_elements [@collab_1, @owner], T.unsafe(pull&.review_requests).pending.reviewers
    end

    test "does not enforce the regular manual request limit" do
      assert_equal 15, @pull.manual_review_requests_limit
      stubbed_max = 5

      lots_of_owners = (stubbed_max + 1).times.map do
        owner = create(:user)
        @repo.add_member owner
        owner
      end

      commit_codeowners_file(<<~CODEOWNERS)
        *  #{ lots_of_owners.map { |o| "@#{o.login}" }.join(" ") }
      CODEOWNERS

      PullRequest.any_instance.stubs(:manual_review_requests_limit).returns(stubbed_max)
      commit_readme_changes @pull, :head
      @pull.reload
      assert_same_elements lots_of_owners, @pull.review_requests.map(&:reviewer)
    end

    test "enforces a very high limit when requesting code owners" do
      assert_equal 100, PullRequest::ReviewRequestsDependency::MAX_REVIEW_REQUESTS_FROM_CODE_OWNERS
      stubbed_max = 5

      too_many_owners = (stubbed_max + 1).times.map do
        owner = create(:user)
        @repo.add_member owner
        owner
      end

      commit_codeowners_file(<<~CODEOWNERS)
        *  #{ too_many_owners.map { |o| "@#{o.login}" }.join(" ") }
      CODEOWNERS

      PullRequest::ReviewRequestsDependency.stub_const(:MAX_REVIEW_REQUESTS_FROM_CODE_OWNERS, stubbed_max) do
        commit_readme_changes @pull, :head
      end

      @pull.reload
      assert @pull.codeowners.count > stubbed_max
      assert_equal stubbed_max, @pull.review_requests.count
    end

    test "reads the codeowners file from the base branch" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        * @collab-1
      CODEOWNERS

      commit_codeowners_file(<<~CODEOWNERS, ref: "contrib")
        * @collab-2
      CODEOWNERS

      pull = create :pull_request,
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "contrib",
        head_repository: @repo,
        head_user: @repo.owner,
        head_ref: "readme-title",
        issue: create(:issue, repository: @repo, user: @owner)

      assert_equal [@collab_2], pull.codeowners.to_a
    end
  end

  context "#add_pending_reviewer" do
    test "adds a pending reviewer" do
      @pull.add_pending_reviewer(@collab_1)
      assert_equal [@collab_1], @pull.review_requests.pending_reviewers.to_a
    end
  end

  context "#review_request_removable?" do
    test "is true if code owner reviews are not required" do
      @protected_branch.enable_required_pull_request_reviews(require_code_owner_reviews: false)
      @protected_branch.save

      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1
      CODEOWNERS
      commit_readme_changes @pull, :head

      request = @pull.review_requests.create!(reviewer: @collab_2)
      assert @pull.review_request_removable?(request), "expected request to be removable but wasn't"

      assert owner_request = @pull.direct_review_request_for(@collab_1)
      assert @pull.review_request_removable?(owner_request), "expected request to be removable but wasn't"
    end

    test "is true if code owner reviews are required but request is not for a code owner" do
      @protected_branch.enable_required_pull_request_reviews(require_code_owner_reviews: true)
      @protected_branch.save

      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1
      CODEOWNERS
      commit_readme_changes @pull, :head

      request = @pull.review_requests.create!(reviewer: @collab_2)
      assert @pull.review_request_removable?(request), "expected request to be removable but wasn't"
    end

    test "is true if code owner reviews are required but request was manual for a code owner" do
      @protected_branch.enable_required_pull_request_reviews(require_code_owner_reviews: true)
      @protected_branch.save

      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1
      CODEOWNERS

      assert_includes @pull.codeowners, @collab_1
      request = @pull.review_requests.create!(reviewer: @collab_1)
      assert @pull.review_request_removable?(request), "expected request to be removable but wasn't"
    end

    test "is false if code owner reviews are required and the request was for a code owner" do
      @protected_branch.enable_required_pull_request_reviews(require_code_owner_reviews: true)
      @protected_branch.save

      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1
      CODEOWNERS
      commit_readme_changes @pull, :head

      assert owner_request = @pull.direct_review_request_for(@collab_1)
      refute @pull.review_request_removable?(owner_request), "expected owner request to NOT be removable but was"
    end

    test "is false if code owner information can't be loaded" do
      @protected_branch.enable_required_pull_request_reviews(require_code_owner_reviews: true)
      @protected_branch.save

      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1
      CODEOWNERS
      commit_readme_changes @pull, :head

      assert owner_request = @pull.direct_review_request_for(@collab_1)

      @pull = PullRequest.find(@pull.id) # Lazy way to reset the codeowners object
      @pull.historical_comparison.init_diffs.stubs(:deltas).raises(GitRPC::ObjectMissing)
      # stub for asynchronous version
      GitHub::Diff.any_instance.stubs(:deltas).raises(GitRPC::ObjectMissing)
      refute @pull.review_request_removable?(owner_request), "expected owner request to NOT be removable but was"
    end

    test "is true if code owner reviews are required and the request was for a code owner, but then not a code owner later" do
      @protected_branch.enable_required_pull_request_reviews(require_code_owner_reviews: true)
      @protected_branch.save

      commit_codeowners_file(<<~CODEOWNERS)
        *  @collab-1
      CODEOWNERS
      commit = commit_readme_changes @pull, :head

      assert owner_request = @pull.direct_review_request_for(@collab_1)
      refute @pull.review_request_removable?(owner_request), "expected owner request to NOT be removable but was"

      @repo.refs.find("master").append_commit({ message: "remove CODEOWNERS file", committer: @user }, @user) do |files|
        files.remove("CODEOWNERS")
      end

      # Grab a new PullRequest object to ensure we've reloaded all codeowners
      last_pull = PullRequest.last!
      assert_equal @pull, last_pull

      assert last_pull.review_request_removable?(owner_request), "expected owner request to be removable but was NOT"
    end
  end

  context "audit log" do
    test "generates an audit log entry when a review request is created for a user" do
      events = subscribe("pull_request.create_review_request")
      @pull.review_requests.create(reviewer: @user)

      expected_payload = {
        pull_request_id: @pull.id,
        pull_request_url: @pull.permalink,
        pull_request_title: @pull.title,
        org: @org.name,
        org_id: @org.id,
        reviewer_type: "User",
        actor: @pull.issue.modifying_user.login,
        actor_id: @pull.issue.modifying_user.id,
        reviewer: @user.login,
        reviewer_id: @user.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @pull.issue.modifying_user.login,
        user_id: @pull.issue.modifying_user.id,
      }

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end

    test "generates an audit log entry when a review request is created for a team" do
      events = subscribe("pull_request.create_review_request")
      @pull.review_requests.create(reviewer: @team)

      expected_payload = {
        pull_request_id: @pull.id,
        pull_request_url: @pull.permalink,
        pull_request_title: @pull.title,
        org: @org.name,
        org_id: @org.id,
        reviewer_type: "Team",
        actor: @pull.issue.modifying_user.login,
        actor_id: @pull.issue.modifying_user.id,
        reviewer: @team.combined_slug,
        reviewer_id: @team.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @pull.issue.modifying_user.login,
        user_id: @pull.issue.modifying_user.id,
      }

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end

    test "generates an audit log entry when a review request is removed for a user" do
      events = subscribe("pull_request.remove_review_request")
      review_request = @pull.review_requests.create(reviewer: @user)
      review_request.dismiss
      review_request.save

      expected_payload = {
        pull_request_id: @pull.id,
        pull_request_url: @pull.permalink,
        pull_request_title: @pull.title,
        org: @org.name,
        org_id: @org.id,
        reviewer_type: "User",
        actor: @pull.issue.modifying_user.login,
        actor_id: @pull.issue.modifying_user.id,
        reviewer: @user.login,
        reviewer_id: @user.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @pull.issue.modifying_user.login,
        user_id: @pull.issue.modifying_user.id,
      }

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end

    test "generates an audit log entry when a review request is removed for a team" do
      events = subscribe("pull_request.remove_review_request")
      review_request = @pull.review_requests.create(reviewer: @team)
      review_request.dismiss
      review_request.save

      expected_payload = {
        pull_request_id: @pull.id,
        pull_request_url: @pull.permalink,
        pull_request_title: @pull.title,
        org: @org.name,
        org_id: @org.id,
        reviewer_type: "Team",
        actor: @pull.issue.modifying_user.login,
        actor_id: @pull.issue.modifying_user.id,
        reviewer: @team.combined_slug,
        reviewer_id: @team.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @pull.issue.modifying_user.login,
        user_id: @pull.issue.modifying_user.id,
      }

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end
  end

  context "hydro events" do
    test "emits a hydro event for a review request" do
      Timecop.freeze(10.seconds.ago) do
        @pull.review_requests.create(reviewer: @user)

        assert_hydro_published({
          pull_request: Hydro::EntitySerializer.pull_request(@pull),
          actor: Hydro::EntitySerializer.user(@pull.issue.modifying_user),
          subject_user: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(@pull.repository),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          action: :REQUESTED,
          as_code_owner: false,
        }, schema: "github.v1.PullRequestReviewRequest")
      end
    end

    test "emits a hydro event when a user review request is removed" do
      Timecop.freeze(10.seconds.ago) do
        review_request = @pull.review_requests.create(reviewer: @user)
        review_request.dismiss
        review_request.save

        assert_hydro_published({
          pull_request: Hydro::EntitySerializer.pull_request(@pull),
          actor: Hydro::EntitySerializer.user(@pull.issue.modifying_user),
          subject_user: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(@pull.repository),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          action: :UNREQUESTED,
          as_code_owner: false,
        }, schema: "github.v1.PullRequestReviewRequest")
      end
    end

    test "emits a hydro event when a team review request is removed" do
      Timecop.freeze(10.seconds.ago) do
        review_request = @pull.review_requests.create(reviewer: @team)
        review_request.dismiss
        review_request.save

        assert_hydro_published({
          pull_request: Hydro::EntitySerializer.pull_request(@pull),
          actor: Hydro::EntitySerializer.user(@pull.issue.modifying_user),
          subject_team: Hydro::EntitySerializer.team(@team),
          repository: Hydro::EntitySerializer.repository(@pull.repository),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          action: :UNREQUESTED,
          as_code_owner: false,
        }, schema: "github.v1.PullRequestReviewRequest")
      end
    end

    test "emits a hydro event for a request review from owners file with as_code_owner TRUE" do
      Timecop.freeze(10.seconds.ago) do
        commit_codeowners_file(<<~CODEOWNERS)
          * @collab-1 @#{@team}

          *.js @collab-2
          README @#{@team}
        CODEOWNERS

        commit_readme_changes @pull, :head

        @pull.reload
        @pull.repository.reload

        assert_hydro_published({
          pull_request: Hydro::EntitySerializer.pull_request(@pull),
          actor: Hydro::EntitySerializer.user(@user),
          subject_team: Hydro::EntitySerializer.team(@team),
          repository: Hydro::EntitySerializer.repository(@pull.repository),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          action: :REQUESTED,
          as_code_owner: true,
        }, schema: "github.v1.PullRequestReviewRequest")

        assert_hydro_published({
          pull_request: Hydro::EntitySerializer.pull_request(@pull),
          actor: Hydro::EntitySerializer.user(@user),
          subject_user: Hydro::EntitySerializer.user(@collab_1),
          repository: Hydro::EntitySerializer.repository(@pull.repository),
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          action: :REQUESTED,
          as_code_owner: true,
        }, schema: "github.v1.PullRequestReviewRequest")
      end
    end
  end
  context "prefilling review decisions" do
    test "prefills pull reviews correctly" do
      # owner = create(:user, login: "owner", plan: "micro")
      # user = create(:user, login: "pr-creator")
      # reviewer = create(:user, login: "reviewer")
      source = create(:private_repository, name: "repo", owner: @owner, from_example: :pull_request_source)

      source.add_member @reviewer, action: :write
      source.add_member @user, action: :write

      protected_branch = create(:protected_branch, repository: source, name: "*", creator: @user,
                                pull_request_reviews_enforcement_level: :everyone,
                                required_status_checks_enforcement_level: :non_admins)

      source.commits.create_merge_commit(@user, "master", "master-forward-2").first
      source.heads.create("other-master", source.heads.find("master").target_oid, source.owner)
      pull_1 = PullRequest.create_for!(source,
                                       base: "master",
                                       head: "master-forward-2",
                                       user: @user,
                                       title: "convert to CR line ending",
                                       body: "most valuable PR ever A++++ please do merge",
                                      )

      pull_2 = PullRequest.create_for!(source,
                                       base: "other-master",
                                       head: "topic-partial-merge",
                                       user: @user,
                                       title: "convert to CR line ending",
                                       body: "most valuable PR ever A++++ please do merge",
                                      )

      review1 = pull_1.reviews.create(head_sha: "xxxxx", user: @reviewer)
      review1.approve!

      PullRequest.prefill_review_decisions([pull_1, pull_2], @user)
      decision_1 = pull_1.review_decision(viewer: @user)
      decision_2 = pull_2.review_decision(viewer: @user)
      assert_equal :approved, decision_1
      assert_equal :review_required, decision_2
    end

    test "prefills pull reviews correctly - same head and base" do
      source = create(:private_repository, name: "repo", owner: @owner, from_example: :pull_request_source)

      source.add_member @reviewer, action: :write
      source.add_member @user, action: :write

      create(:protected_branch, repository: source, name: "*", creator: @user,
                                pull_request_reviews_enforcement_level: :everyone,
                                required_status_checks_enforcement_level: :non_admins)

      source.commits.create_merge_commit(@user, "master", "master-forward-2").first
      pull_1 = PullRequest.create_for!(source,
                                        base: "master",
                                        head: "master-forward-2",
                                        user: @user,
                                        title: "convert to CR line ending",
                                        body: "most valuable PR ever A++++ please do merge",
                                        )

      review1 = pull_1.reviews.create(head_sha: "xxxxx", user: @reviewer)
      review1.approve!
      pull_1.close

      pull_2 = PullRequest.create_for!(source,
                                        base: "master",
                                        head: "master-forward-2",
                                        user: @user,
                                        title: "convert to CR line ending",
                                        body: "most valuable PR ever A++++ please do merge",
                                        )

      pull_2.close

      PullRequest.prefill_review_decisions([pull_1, pull_2], @user)
      decision_1 = pull_1.review_decision(viewer: @user)
      decision_2 = pull_2.review_decision(viewer: @user)
      assert_equal :approved, decision_1
      assert_equal :review_required, decision_2
    end

    test "prefills pull reviews correctly - same head different base" do
      source = create(:private_repository, name: "repo", owner: @owner, from_example: :pull_request_source)

      source.add_member @reviewer, action: :write
      source.add_member @user, action: :write

      protected_branch = create(:protected_branch, repository: source, name: "*", creator: @user,
                                pull_request_reviews_enforcement_level: :everyone,
                                required_status_checks_enforcement_level: :non_admins)

      source.commits.create_merge_commit(@user, "master", "master-forward-2").first
      pull_1 = PullRequest.create_for!(source,
                                        base: "master",
                                        head: "master-forward-2",
                                        user: @user,
                                        title: "convert to CR line ending",
                                        body: "most valuable PR ever A++++ please do merge",
                                        )

      review1 = pull_1.reviews.create(head_sha: "xxxxx", user: @reviewer)
      review1.approve!
      pull_1.close

      pull_2 = PullRequest.create_for!(source,
                                        base: "topic-partial-merge",
                                        head: "master-forward-2",
                                        user: @user,
                                        title: "convert to CR line ending",
                                        body: "most valuable PR ever A++++ please do merge",
                                        )

      pull_2.close

      PullRequest.prefill_review_decisions([pull_1, pull_2], @user)
      decision_1 = pull_1.review_decision(viewer: @user)
      decision_2 = pull_2.review_decision(viewer: @user)
      assert_equal :approved, decision_1
      assert_equal :review_required, decision_2
    end
  end

  context "copilot reviews" do
    context "when PR is Created ready for review" do
      test "does create a pending copilot review request if auto reviews enabled" do
        enable_feature_flag(:copilot_reviews_automatic_pull_request_review, @repo)
        PullRequests::Copilot::CodeReviewAccess.any_instance.expects(:auto_reviewable?).returns(true)
        PullRequests::Copilot::CodeReviewGenerator.any_instance.expects(:generate).never

        @pull.request_review_from_copilot(@user)

        assert_equal 1, @pull.review_requests.where(reviewer: @bot).count
      end

      test "does nothing if auto reviews not enabled" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @repo)
        PullRequests::Copilot::CodeReviewAccess.any_instance.expects(:auto_reviewable?).returns(false)
        PullRequests::Copilot::CodeReviewGenerator.any_instance.expects(:generate).never

        @pull.request_review_from_copilot(@user)

        assert_equal 0, @pull.review_requests.where(reviewer: @bot).count
      end
    end

    context "when PR is Created not ready for review" do
      test "does nothing" do
        PullRequests::Copilot::CodeReviewGenerator.any_instance.expects(:generate).never

        @pull.update_attribute(:draft, true)
        @pull.request_review_from_copilot(@user)

        assert_equal 0, @pull.review_requests.where(reviewer: @bot).count
      end
    end

    context "when previously drafted PR is marked as ready for review" do
      test "does create a pending copilot review request if auto reviews enabled" do
        enable_feature_flag(:copilot_reviews_automatic_pull_request_review, @repo)
        PullRequests::Copilot::CodeReviewAccess.any_instance.expects(:auto_reviewable?).returns(true)
        PullRequests::Copilot::CodeReviewGenerator.any_instance.expects(:generate).never

        @pull.request_review_from_copilot(@user)

        assert_equal 1, @pull.review_requests.where(reviewer: @bot).count
      end

      test "does nothing if auto reviews not enabled" do
        disable_feature_flag(:copilot_reviews_automatic_pull_request_review, @repo)
        PullRequests::Copilot::CodeReviewAccess.any_instance.expects(:auto_reviewable?).returns(false)
        PullRequests::Copilot::CodeReviewGenerator.any_instance.expects(:generate).never

        @pull.request_review_from_copilot(@user)

        assert_equal 0, @pull.review_requests.where(reviewer: @bot).count
      end
    end

    context "prevent repeated reviews" do
      test "doesn't request a new review if the bot has already reviewed" do
        PullRequests::Copilot::CodeReviewAccess.any_instance.expects(:auto_reviewable?).returns(true).at_least_once
        PullRequests::Copilot::CodeReviewGenerator.any_instance.expects(:generate).never

        create(:pull_request_review, pull_request: @pull, user: @bot)

        @pull.request_review_from_copilot(@user)

        assert_equal 0, @pull.review_requests.where(reviewer: @bot).count
      end

      test "doesn't request a new review if the bot is already reviewing" do
        PullRequests::Copilot::CodeReviewAccess.any_instance.expects(:auto_reviewable?).returns(true).at_least_once
        PullRequests::Copilot::CodeReviewGenerator.any_instance.expects(:generate).never

        @pull.request_review_from_copilot(@user)
        @pull.request_review_from_copilot(@user)

        assert_equal 1, @pull.review_requests.where(reviewer: @bot).count
      end
    end
  end
end
