# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"
require "test_helpers/conditional_access/filter_test_helper"

class PullRequestTestBase < GitHub::TestCase
  include HydroTestHelpers
  include PullRequestIntegrationTestHelpers
  include RepositoriesTestHelper
  include ConditionalAccess::FilterTestHelper
  include AuditLog::IntegrationTestHelpers
  include PullRequestSynchronizationTestHelpers
  include Marketplace::Domain::Provider

  PR_JOBS = [
    MaintainTrackingRefJob,
    DestroyMergeRefsJob,
  ]

  def perform_enqueued_pr_jobs
    with_enqueued_pr_sync_jobs(additional_jobs: PR_JOBS) do
      yield
    end
  end

  fixtures do
    Spokesd.enable_spokesd

    @ryan   = create(:user, email: "rtomayko@gmail.com", login: "rtomayko")
    @owner  = create(:user, login: "owner", plan: "micro")

    @org = create(:organization, login: "acme", admin: @owner)
    @team = create(:team, organization: @org, name: "Employee", privacy: :closed)
    @org_repo = create(:repository, owner: @org, from_example: :pull_request_source)
    @team.add_repository(@org_repo, :push)

    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @private_repo = create(:private_repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "forker")
    @drama  = create(:user, login: "jdrama", email: "drama@example.com")
    @drama.add_email "drama@example.com"
    @turtle = create(:user, login: "turtle")
    @vince  = create(:staff_admin_user, login: "vince")
    @fork, msg = @source.fork(forker: @forker)
    assert @fork, "forking #{@source.inspect} as #{@forker.inspect} failed: #{msg.inspect}"
    @issue =
      create(:issue,
        user: @forker,
        repository: @source,
        body: "hey @vince look at this real quick",
      )

    @second_repo = create(:repository, owner: @owner, from_example: :refs_heads_refs_heads)
    example_repo :pull_request_fork,   @fork

    @commit = @fork.commits.find(@fork.ref_to_sha("topic")).freeze

    @comm   = create :commit_comment, user: @owner, repository: @fork,
      position: 0, path: "color.js", commit_id: @commit.oid

    # this is here for some cases that need to create the PR in the test to
    # assert that certain things happen during creation. a more clear and less
    # cluttered way of doing this would be nice.
    perform_enqueued_pr_jobs do
      ref = @fork.heads.create("topic-2", @fork.heads.find("master").target, @fork.owner)
      metadata = { message: "blah", committer: @fork.owner }
      ref.append_commit(metadata, @fork.owner)

      ref2 = @fork.heads.create("topic-3", ref.target, @fork.owner)
      metadata = { message: "blah blah", committer: @fork.owner }
      ref2.append_commit(metadata, @fork.owner)
    end

    @pull =
      PullRequest.new(
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @fork.owner,
      )
    refute_nil @pull.issue
    @issue.pull_request = @pull

    perform_enqueued_pr_jobs do
      @pull.save!
    end

    @source.allow_auto_merge(actor: @owner)

    make_trusted_oauth_apps_owner
    @actions_app = create(:launch_integration)
    refute_nil @actions_app

    example_repo_snapshot
  end

  # Note: Avoid adding logic that performs file IO / git ops or really anything heavy
  # here since this is run before each test in this large suite. Add logic to
  # the fixtures block or individual test instead.
  #
  # See: https://github.com/github/github/pull/39905
  setup do
    ActionMailer::Base.deliveries.clear
    reset_cache
    example_repo_restore
  end

  def create_conflicting_commits(pull_request)
    perform_enqueued_pr_jobs do
      metadata = { message: "blah", committer: pull_request.user }
      head_ref = pull_request.head_repository.heads.find(pull_request.head_ref)
      commit = head_ref.append_commit(metadata, pull_request.user) do |files|
        files.add("blah.txt", "This might conflict?")
      end

      metadata = { message: "blah", committer: pull_request.user }
      base_ref = pull_request.base_repository.heads.find(pull_request.base_ref)
      commit = base_ref.append_commit(metadata, pull_request.user) do |files|
        files.add("blah.txt", "This will conflict!")
      end
    end

    pull_request.reload
  end

  # Used for tests which use stubs make a PR appear merged
  class FakeSpokesApiAlwaysMerged
    def ahead_behind_contains(base:, tips:, reduce_cost_for_spokes_api:)
      tips
    end
  end
  private_constant :FakeSpokesApiAlwaysMerged
end

class PullRequestTest < PullRequestTestBase
  context "deleting branch on merge" do
    test "deletes branch on merge by user if repo setting enabled on head repo" do
      base_repo = @pull.base_repository
      head_repo = @pull.head_repository
      head_repo.update_merge_settings(head_repo.owner, delete_branch_allowed: true)
      refute_predicate base_repo, :delete_branch_on_merge?
      assert_predicate head_repo, :delete_branch_on_merge?

      @pull.merge(@pull.user)
      refute_predicate @pull, :head_ref_exist?
      assert_predicate @pull, :merged?
    end

    test "does not delete branch on merge by user if repo setting is not enabled on head repo" do
      base_repo = @pull.base_repository
      head_repo = @pull.head_repository
      base_repo.update_merge_settings(base_repo.owner, delete_branch_allowed: true)
      assert_predicate base_repo, :delete_branch_on_merge?
      refute_predicate head_repo, :delete_branch_on_merge?

      @pull.merge(@pull.user)
      assert_predicate @pull, :head_ref_exist?
      assert_predicate @pull, :merged?
    end

    test "deletes branch on merge after auto-updating dependent PR base refs" do
      repo = @fork

      pull =
        PullRequest.create_for! repo,
          base: "topic",
          head: "topic-2",
          user: repo.owner,
          issue: create(:issue, user: repo.owner, repository: repo)
      dependent_pull =
        PullRequest.create_for! repo,
          base: "topic-2",
          head: "topic-3",
          user: repo.owner,
          issue: create(:issue, user: repo.owner, repository: repo)

      repo.update_merge_settings(repo.owner, delete_branch_allowed: true)
      assert_predicate repo, :delete_branch_on_merge?

      pull.reload
      pull.merge(repo.owner)
      refute_predicate pull, :head_ref_exist?
      assert_predicate pull, :merged?

      dependent_pull.reload
      assert_equal "topic", dependent_pull.base_ref_name
    end

    test "does not delete branch on merge if auto-updating dependent PR base refs fails" do
      PullRequest.stub_const(:AUTO_CHANGE_BASE_MAX_PULL_REQUESTS, 0) do
        repo = @fork

        pull =
          PullRequest.create_for! repo,
            base: "topic",
            head: "topic-2",
            user: repo.owner,
            issue: create(:issue, user: repo.owner, repository: repo)
        dependent_pull =
          PullRequest.create_for! repo,
            base: "topic-2",
            head: "topic-3",
            user: repo.owner,
            issue: create(:issue, user: repo.owner, repository: repo)

        repo.update_merge_settings(repo.owner, delete_branch_allowed: true)
        assert_predicate repo, :delete_branch_on_merge?

        pull.reload
        pull.merge(repo.owner)
        assert_predicate pull, :head_ref_exist?
        assert_predicate pull, :merged?

        dependent_pull.reload
        assert_equal "topic-2", dependent_pull.base_ref_name
      end
    end

    test "deletes branch on merge by GitHub App if repo setting enabled on head repo", skip_enterprise: true do
      installation = make_integration_installation(
        integration: @actions_app,
        repository: @source,
        permissions: { "contents" => :write, "pull_requests" => :write },
      )

      pull = create :pull_request,
        repository: @source,
        user: @source.owner,
        head_ref: "master-forward-2"

      head_repo = pull.head_repository
      head_repo.update_merge_settings(head_repo.owner, delete_branch_allowed: true)
      assert_predicate head_repo, :delete_branch_on_merge?

      pull.merge(installation.bot)
      refute_predicate pull, :head_ref_exist?
      assert_predicate pull, :merged?
    end

    test "does not delete branch on merge by GitHub App if repo setting is not enabled on head repo", skip_enterprise: true do
      installation = make_integration_installation(
        integration: @actions_app,
        repository: @source,
        permissions: { "contents" => :write, "pull_requests" => :write },
      )

      pull = create :pull_request,
        repository: @source,
        user: @source.owner,
        head_ref: "master-forward-2"

      refute_predicate pull.head_repository, :delete_branch_on_merge?

      pull.merge(installation.bot)
      assert_predicate pull, :head_ref_exist?
      assert_predicate pull, :merged?
    end
  end

  unless GitHub.enterprise?
    test "fails validation if user is interaction blocked" do
      User::InteractionAbility.stubs(:interaction_allowed?).returns(false)
      User::InteractionAbility.stubs(:ban_expiry).returns(DateTime.now + 1.day)
      interaction_ban_user = create(:user)
      begin
        create(:pull_request,
          repository: @source,
          base_repository: @source,
          base_user: @source.owner,
          base_ref: "master",
          head_repository: @fork,
          head_user: @fork.owner,
          head_ref: "topic",
          issue: @issue,
          user: interaction_ban_user,
        )
      rescue ActiveRecord::RecordInvalid => e
        assert_includes e.message, "suspended for 1 day"
      end
    end

    test "fails validation on update of the issue body if user is interaction blocked" do
      interaction = RepositoryInteractionAbility.new(@source)
      interaction.set_ability(:collaborators_only, @source.owner)

      refute @pull.issue.update_body("hello!", @forker)

      assert_includes @pull.issue.errors[:base],
        "could not be created. Interactions on this repository have been restricted to collaborators only."
    end

    test "passes validation on update of the issue body if user is not interaction blocked" do
      interaction = RepositoryInteractionAbility.new(@source)
      interaction.set_ability(:collaborators_only, @source.owner)

      assert @pull.issue.update_body("hello!", @source.owner)
      assert_empty @pull.issue.errors[:base]
    end
  end

  context "#for_repository" do
    test "returns pull requests if the repository has any" do
      assert_equal [@pull], PullRequest.for_repository(@source)
    end

    test "returns empty if the repository has no PRs" do
      assert_empty PullRequest.for_repository(create :repository)
    end
  end

  context ".open_based_on_ref" do
    test "returns open pull request with matching base or head ref" do
      closed_pull = PullRequest.create_for!(@org_repo, title: "hello", user: @owner, base: "master", head: "master-forward-2")
      closed_pull.close(@owner)

      open_pull = PullRequest.create_for!(@org_repo, title: "hello", user: @owner, base: "master", head: "master-forward-2")

      assert_same_elements [open_pull], PullRequest.open_based_on_ref(@org_repo, "master")
      assert_same_elements [open_pull], PullRequest.open_based_on_ref(@org_repo, "master-forward-2")
    end

    test "returns scope that can be chained" do
      org_pull = PullRequest.create_for!(@org_repo, title: "hello", user: @owner, base: "master", head: "master-forward-2")

      assert_equal 1, PullRequest.open_based_on_ref(@org_repo, "master").where(id: org_pull.id).count
    end
  end

  test "head_ref_exist? will not fail if head_ref is nil" do
    @pull.head_ref = nil

    refute @pull.head_ref_exist?
  end

  test "head_ref_exist? will not fail if head_repository is nil" do
    @pull.head_repository = nil

    refute @pull.head_ref_exist?
  end

  test "sync_issue_updated_at with fractional difference" do
    time = Time.current
    @pull.update!(updated_at: time)
    @issue.update!(updated_at: time)

    new_updated_at = @issue.updated_at + 0.5
    refute_equal new_updated_at, @issue.updated_at
    @pull.updated_at = new_updated_at

    @pull.expects(:update_issue_updated_at_via_sql).never
    @pull.save!

    @pull.reload
    @issue.reload

    assert_equal @pull.updated_at, @issue.updated_at
  end

  test "sync_issue_updated_at with significant difference" do
    time = Time.current
    @pull.update!(updated_at: time)
    @issue.update!(updated_at: time)

    @pull.updated_at = @issue.updated_at + 10
    refute_equal @pull.updated_at, @issue.updated_at

    @pull.save!

    @pull.reload
    @issue.reload

    assert_equal @pull.updated_at, @issue.updated_at
  end

  context "#touch" do
    test "updates issue then PR if issue is touched" do
      Timecop.freeze do
        some_time_ago = 10.minutes.ago
        issue = @pull.issue

        issue.update!(updated_at: some_time_ago)

        updated_tables = log_updated_tables do
          perform_enqueued_jobs only: [IssueOrchestration.job_class] do
            issue.touch
          end
        end

        assert @pull.reload.updated_at > some_time_ago
        assert_equal @pull.updated_at, issue.reload.updated_at

        # note: Pull request is touched in an `after_commit` hook.
        assert_equal %w[issues issue_orchestrations pull_requests], updated_tables.uniq
      end
    end

    test "updates PR then issue if PR is touched" do
      Timecop.freeze do
        some_time_ago = 10.minutes.ago
        issue = @pull.issue

        perform_enqueued_jobs only: [IssueOrchestration.job_class] do
          @pull.update!(updated_at: some_time_ago)
        end

        updated_tables = log_updated_tables { @pull.touch }

        assert @pull.reload.updated_at > some_time_ago
        assert_equal @pull.updated_at, issue.reload.updated_at

        # note: Issue is touched in an `after_commit` hook.
        assert_equal %w[pull_requests issues], updated_tables
      end
    end
  end

  test "indicating cross-repo pull" do
    assert @pull.cross_repo?

    pull =
      PullRequest.new(
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @source,
        head_user: @source.owner,
        head_ref: "topic",
      )
    assert !pull.cross_repo?
  end

  test "creates a PullRequest with requested reviewers" do
    @source.add_member @forker
    pull =
      PullRequest.create_for! @source,
        base: "owner:master",
        head: "forker:topic-2",
        user: @forker,
        title: @issue.title,
        body: @issue.body,
        reviewer_user_ids: [@owner.id]

    pull.reload

    assert_equal pull.review_requests.pending.reviewers, [@owner]
  end

  test "creates a PullRequest with teams" do
    @org_repo.add_member @forker
    @team.add_member(@forker)

    pull =
      PullRequest.create_for! @org_repo,
        base: "master",
        head: "master-merged-topic",
        user: @forker,
        title: @issue.title,
        body: @issue.body,
        reviewer_user_ids: [@owner.id],
        reviewer_team_ids: [@team.id]

    pull.reload

    assert_same_elements [@owner, @team], pull.review_requests.pending.reviewers
  end

  test "tracks references in pull request body" do
    @org_repo.add_member @forker
    @team.add_member(@forker)

    perform_enqueued_jobs(only: ProcessMentionedReferencesJob) do
      pull =
        PullRequest.create_for! @org_repo,
          base: "master",
          head: "master-merged-topic",
          user: @forker,
          title: @issue.title,
          body: "@#{@team.combined_slug}",
          reviewer_user_ids: [@owner.id],
          reviewer_team_ids: [@team.id]

      pull.reload
      assert_equal pull.mentioned_teams, [@team]
      reference = @team.references.last
      assert_equal reference.source, pull.issue
    end
  end

  test "creates a PullRequest but does not request reviewers without base push access, via a fork" do
    pull =
      PullRequest.create_for! @source,
        base: "owner:master",
        head: "forker:topic-2",
        user: @forker,
        title: @issue.title,
        body: @issue.body,
        reviewer_user_ids: [@owner.id]

    pull.reload

    assert_empty pull.review_requests.pending
  end

  test "validation fails if base branch is being renamed" do
    create(:repository_branch_rename, repository: @source, old_name: "master")
    issue = @source.issues.build(
      title: "Bad PR",
      body: "Blah",
      user: @forker,
      user_hidden: false,
    )
    pull = @source.comparison("master", "master-forward-2").build_pull_request(user: @source.owner)
    pull.issue = issue

    refute_predicate pull, :valid?
    assert_includes pull.errors[:base_ref], "is being renamed"
  end

  test "validation fails if issue's pull_request_id is set to 0" do
    issue = @source.issues.build(
      title: "Bad PR",
      body: "Blah",
      user: @forker,
      user_hidden: false,
    )
    pull = @source.comparison("master", "master-forward-2").build_pull_request(user: @source.owner)
    pull.issue = issue
    assert pull.valid?

    pull.issue.pull_request_id = 0

    assert_raises(ActiveRecord::RecordInvalid) do
      pull.save!
      assert pull.errors[:pull_request_id].include?("is invalid")
    end
  end

  test "creates if requesting reviewers raises a codeowner error" do
    @team.add_member(@forker)
    PullRequest.any_instance.expects(:request_review_from_codeowners).once.raises(PullRequest::DetermineCodeownersError.new(nil))
    pull = T.let(nil, T.nilable(PullRequest))
    assert_performed_with(job: RequestPullRequestReviewersJob) do
      pull = PullRequest.create_for @org_repo,
        base: "master",
        head: "master-merged-topic",
        user: @forker,
        title: @issue.title,
        body: @issue.body
    end

    assert_predicate pull, :persisted?
  end

  test "generates contribution timestamp based on Time.zone on create" do
    Time.use_zone "Australia/Melbourne" do
      pull = PullRequest.create_for!(@source,
        base: "#{@source.owner}:master",
        head: "#{@fork.owner}:topic-2",
        user: @fork.owner,
        title: "blah",
        body: "blah")

      assert_equal Time.zone.now.utc_offset, pull.contributed_at.utc_offset
    end
  end

  test "returns local times for old issues" do
    24.times do |i|
      time = Time.utc(2014, 1, 1) + i * 3600
      @pull.contributed_at = time
      @pull.created_at = time
      @pull.save!
      @pull = PullRequest.find(@pull.id)
      assert_equal time.localtime.to_date, @pull.contributed_on
      assert_equal time, @pull.contribution_time
    end
  end

  test "pull request identifiers do not crash if repository is gone" do
    refute_nil @pull.permalink
    refute_nil @pull.message_id
    @pull.repository = nil
    assert_nil @pull.permalink
    assert_nil @pull.message_id
  end

  test "participants" do
    # mentioning the issue from another issue does not qualify as participating
    create(:issue, repository: @pull.base_repository).comments.create!({
      repository: @pull.repository,
      user: @turtle,
      body: "this must have to do with ##{@pull.number}",
    })

    # commit authors with generic email addresses are not participants
    assert_includes @pull.changed_commits.map(&:author_email), "drama@example.com"

    assert_equal [@forker, @owner, @ryan], @pull.participants

    # users who don't have any access to the repo are not participants
    @source.toggle_visibility(actor: @owner)
    @pull.reload

    assert_equal [@owner], @pull.participants
  end if GitHub.email_detect_generic_domains?

  # Specifically, reviewers that have not made line comments.
  test "reviewers are participants" do
    pending_reviewer = create(:user)
    submitted_reviewer = create(:user)
    @source.add_member(pending_reviewer)
    @source.add_member(submitted_reviewer)
    @pull.reviews.create!(user: pending_reviewer, head_sha: @pull.head_sha, body: "pending", state: :pending)
    @pull.reviews.create!(user: submitted_reviewer, head_sha: @pull.head_sha, body: "approved", state: :approved)

    refute_includes @pull.participants, pending_reviewer, "Pending reviewer should not be a participant"
    assert_includes @pull.participants, submitted_reviewer, "Submitted reviewer should be a participant"
  end

  test "mannequins reviewers are considered participants in private repository" do
    submitted_reviewer = create(:mannequin)

    issue = create(:issue, repository: @private_repo)
    @private_pull =
      PullRequest.create!(
        repository: @private_repo,
        base_repository: @private_repo,
        base_user: @private_repo.owner,
        base_ref: "master",
        head_repository: @private_repo,
        head_user: @private_repo.owner,
        head_ref: "master-forward-2",
        issue: issue,
        user: @private_repo.owner,
      )

    @private_pull.reviews.create!(user: submitted_reviewer, head_sha: @private_pull.head_sha, body: "approved", state: :approved)

    assert_includes @private_pull.participants, submitted_reviewer, "Submitted reviewer should be a participant"
  end

  test "bots are not participants" do
    installation = make_integration_installation(repository: @source, permissions: { "pull_requests" => :write })
    perform_enqueued_pr_jobs { @pull.merge(installation.bot) }
    refute_includes @pull.participants, installation.bot
  end

  test "participants work in orgs with people who are not org members but are on the repo" do
    non_org_member = create(:user, login: "non-org-member")
    @org_repo.add_member(non_org_member)
    pull = PullRequest.create_for!(@org_repo, title: "hello", user: non_org_member, base: "master", head: "master-forward-2")
    assert_includes pull.participants_for(non_org_member), non_org_member
  end

  test "generating qualified base and head refs" do
    assert_equal "owner:master", @pull.base
    assert_equal "forker:topic", @pull.head
  end

  test "accessing the active comparison object" do
    compare = @pull.comparison
    assert compare.cross_repository?
    assert_equal "owner", compare.base_user_login
    assert_equal "master", compare.base_ref
    assert_equal "forker", compare.head_user_login
    assert_equal "topic", compare.head_ref
    assert_equal 3, compare.commits.length
    assert_equal "diverged", compare.status
  end

  test "validating commits exist between the base and head refs on create" do
    pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:#{@source.ref_to_sha("master")}",
      user: @forker,
      issue: @issue)
    refute pull.save
    assert pull.errors[:base].any? { |message| message =~ /No commits between/ }
  end

  test "validating commits are required on create for a draft pull request" do
    commit_oid = @source.ref_to_sha(@source.default_branch)
    @source.heads.create("new-branch", commit_oid, @owner, reflog_data: {})
    pull = PullRequest.create_for(@source,
      base: @source.default_branch,
      head: "new-branch",
      user: @owner,
      title: "A sample empty PR",
      draft: true)
    refute pull.save
  end

  test "validating common history between the base and head refs on create" do
    metadata = { committer: @forker, message: "disjoint history" }
    commit = @fork.commits.create(metadata) {}

    @fork.heads.find("topic").update(commit, @fork.owner)

    pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.owner}:topic",
      user: @forker)

    refute pull.valid?
    assert_includes pull.errors[:base], "The forker:topic branch has no history in common with owner:master"
  end

  test "validating an existing pull request with the same refs does not exist" do
    @pull.save!

    pull =
      PullRequest.create_for(@source,
         base: "master",
         head: "forker:topic",
         user: @forker,
      )
    assert pull.errors.present?
    assert pull.errors[:base].any? { |message| message =~ /pull request already exists/ }
  end

  test "accepts PR on locked repo not within migration" do
    Repository.any_instance.stubs(:locked_on_migration?).returns(true)
    assert @pull.valid?,
      "Pull Request should be valid but had the following errors: #{@pull.errors.full_messages}"
  end

  test "accepts PR on locked repo within migration" do
    Repository.any_instance.stubs(:locked_on_migration?).returns(true)
    GitHub.stubs(:importing?).returns(true)
    assert @pull.valid?
  end

  test "allows repo to be archived" do
    Repository.any_instance.stubs(:archived?).returns(true)
    assert @pull.valid?,
      "Pull Request should be valid but had the following errors: #{@pull.errors.full_messages}"
  end

  if GitHub.email_verification_enabled?
    test "validating user has verified email" do
      @forker.stubs(:content_creation_requires_email_verification?).returns(true)
      pull =
        PullRequest.create_for(@source,
           base: "master",
           head: "forker:topic-2",
           user: @forker,
        )
      assert pull.errors.present?
      assert_includes_match /email address must be verified/, pull.errors[:base]
    end
  end

  test "validating pull request repo and base match" do
    pull = PullRequest.create_for @fork,
      base: "owner:master",
      head: "forker:topic",
      user: @forker
    assert pull.errors.present?
  end

  test "validating that the base_ref is a branch on create" do
    commit_oid = @pull.base_repository.heads.find(@pull.base_ref).target_oid

    pull = PullRequest.create_for(@source,
      base: "#{@source.owner}:#{commit_oid}",
      head: "#{@fork.owner}:topic-2",
      user: @fork.owner,
      title: "blah",
      body: "blah")

    assert !pull.valid?
    assert pull.errors[:base_ref].include?("must be a branch")

    @source.tags.create("something", commit_oid, @source.owner)

    pull = PullRequest.create_for(@source,
      base: "#{@source.owner}:something",
      head: "#{@fork.owner}:topic-2",
      user: @fork.owner,
      title: "blah",
      body: "blah")

    assert !pull.valid?
    assert pull.errors[:base_ref].include?("must be a branch")
  end

  test "uses safe_ref_name for head_ref and base_ref if branch exists" do
    pull = PullRequest.create_for(@source,
      base: "#{@source.owner}:master",
      head: "#{@source.owner}:refs/heads/master-forward-2",
      user: @source.owner,
      title: "blah",
      body: "blah"
    )

    assert pull.valid?
    assert pull.head_ref == "master-forward-2"
  end

  test "is invalid if using fully refs and  if branch exits and shortend does not" do
    pull = PullRequest.create_for(@second_repo,
      base: "#{@second_repo.owner}:refs/heads/master",
      head: "#{@second_repo.owner}:refs/heads/foobar",
      user: @second_repo.owner,
      title: "blah",
      body: "blah"
    )

    refute pull.valid?
  end

  test "validating that the base_ref is a branch on update" do
    commit_oid = @pull.base_repository.heads.find(@pull.base_ref).target_oid
    @pull.update(base_ref: commit_oid)

    assert !@pull.valid?
    assert @pull.errors[:base_ref].include?("must be a branch")

    @source.tags.create("something", commit_oid, @source.owner)
    @pull.update(base_ref: "something")

    assert !@pull.valid?
    assert @pull.errors[:base_ref].include?("must be a branch")
  end

  test "validating that the head_ref isn't a heads-namespaced branch" do
    pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:heads/master",
      user: @forker,
      issue: @issue)
    assert !pull.save
    assert pull.errors[:head].any? { |message| message =~ /must not include 'heads\/' namespace/ }
  end

  context "base_ref and head_ref beginning with refs/heads/ validation" do
    context "when the feature flag is enabled" do
      test "validating that head_ref does not allow beginning with refs/heads/" do
        GitHub.flipper[:disallow_refs_heads_via_validation].enable(@source)
        GitHub.flipper[:clean_refs_heads_before_validation].disable(@source) # ensure we're not cleaning before validation

        @pull.head_ref = "refs/heads/topic"

        assert !@pull.valid?, "Pull request is valid when it should not be"
        assert @pull.errors[:head_ref].any? { |message| message =~ /must not include 'refs\/heads\/'/ },
                "Pull request errors do not include the expected refs/heads message"
      end

      test "validating that base_ref does not allow beginning with refs/heads/" do
        GitHub.flipper[:disallow_refs_heads_via_validation].enable(@source)
        GitHub.flipper[:clean_refs_heads_before_validation].disable(@source) # ensure we're not cleaning before validation

        @pull.base_ref = "refs/heads/master"

        assert !@pull.valid?, "Pull request is valid when it should not be"
        assert @pull.errors[:base_ref].any? { |message| message =~ /must not include 'refs\/heads\/'/ },
                "Pull request errors do not include the expected refs/heads/ message"
      end
    end

    context "when the feature flag is disabled" do
      test "validating that head_ref allows beginning with refs/heads/" do
        GitHub.flipper[:disallow_refs_heads_via_validation].disable(@source)

        @pull.head_ref = "refs/heads/topic"

        assert @pull.valid?, "Pull request is invalid when it should be valid"
        assert !@pull.errors[:head_ref].any? { |message| message =~ /must not include 'refs\/heads\/'/ },
                "Pull request errors unexpectedly include the refs/heads/ message"
      end

      test "validating that base_ref does not allow beginning with refs/heads/" do
        GitHub.flipper[:disallow_refs_heads_via_validation].disable(@source)

        @pull.base_ref = "refs/heads/master"

        assert @pull.valid?, "Pull request is invalid when it should be valid"
        assert !@pull.errors[:base_ref].any? { |message| message =~ /must not include 'refs\/heads\/'/ },
                "Pull request errors unexpectedly include the refs/heads/ message"
      end
    end
  end

  context "base_ref and head_ref beginning with refs/heads/ cleaning" do
    context "when the feature flag is enabled" do
      test "refs/heads is automatically cleaned from the beginning of head_ref" do
        GitHub.flipper[:clean_refs_heads_before_validation].enable(@source)

        @pull.head_ref = "refs/heads/topic"
        @pull.valid? # we don't care about the result of the validation, just that it doesn't clean

        assert_equal "topic", @pull.head_ref, "Pull request head_ref was not cleaned"
      end

      test "refs/heads is automatically cleaned from the beginning of base_ref" do
        GitHub.flipper[:clean_refs_heads_before_validation].enable(@source)

        @pull.base_ref = "refs/heads/master"
        @pull.valid? # we don't care about the result of the validation, just that it doesn't clean

        assert_equal "master", @pull.base_ref, "Pull request base_ref was not cleaned"
      end

      test "when the disallow_refs_heads_via_validation feature flag is enabled, there is no validation error" do
        GitHub.flipper[:clean_refs_heads_before_validation].enable(@source)
        GitHub.flipper[:disallow_refs_heads_via_validation].enable(@source)

        @pull.head_ref = "refs/heads/topic"
        @pull.base_ref = "refs/heads/master"

        assert @pull.valid?, "Pull request is invalid when it should be valid"
        assert_equal "topic", @pull.head_ref, "Pull request head_ref was not cleaned"
        assert_equal "master", @pull.base_ref, "Pull request base_ref was not cleaned"
      end
    end

    context "when the feature flag is disabled" do
      test "refs/heads is left at the beginning of head_ref" do
        GitHub.flipper[:clean_refs_heads_before_validation].disable(@source)

        @pull.head_ref = "refs/heads/topic"
        @pull.valid? # we don't care about the result of the validation, just that it doesn't clean

        assert_equal "refs/heads/topic", @pull.head_ref, "Pull request head_ref was cleaned when it should not have been"
      end

      test "refs/heads is left at the beginning of base_ref" do
        GitHub.flipper[:clean_refs_heads_before_validation].disable(@source)

        @pull.base_ref = "refs/heads/master"
        @pull.valid? # we don't care about the result of the validation, just that it doesn't clean

        assert_equal "refs/heads/master", @pull.base_ref, "Pull request base_ref was cleaned when it should not have been"
      end
    end
  end

  # see https://github.com/github/github/issues/62000
  test "validating all refs are readable" do
    repo = create(:private_repository, owner: @owner, from_example: :pull_request_source)
    repo.add_member @forker, action: :write

    forked = create(:fork_repository, forker: @forker, fork_repo: repo, from_example: :pull_request_fork)

    repo.disassociate_member(@forker, repo.owner)

    pull = PullRequest.create_for(forked, title: "References inaccessible ref",
                                          head: "#{@owner.name}:master-forward-2",
                                          base: "master",
                                          user: @forker)

    refute pull.valid?, "should not be able to see master-forward-2 due to removal from repo"

    # also ensure another member who is not associated with repo cannot create a PR against it.
    other_user = create(:user)
    forked.add_member(other_user)

    pull = PullRequest.create_for(forked, title: "References inaccessible ref",
                                          head: "#{@owner.name}:master-forward-2",
                                          base: "master",
                                          user: other_user)

    refute pull.valid?, "should not be able to see master-forward-2 due to never having been a member of parent repo"
  end

  test "validate maximum PRs with duplicate head_shas" do
    GitHub.stub(:duplicate_head_sha_limit, 2) do
      head_sha = @pull.head_sha

      @fork.heads.create("new-branch-same-sha-1", head_sha, @fork.owner, reflog_data: {})
      pull1 = PullRequest.create_for @source,
                base: "#{@owner.name}:master",
                head: "#{@forker}:new-branch-same-sha-1",
                user: @forker,
                title: "Duplicate sha"
      assert pull1.save, "couldn't save valid pull request"

      @fork.heads.create("new-branch-same-sha-2", head_sha, @fork.owner, reflog_data: {})
      pull2 = PullRequest.create_for @source,
                base: "#{@owner.name}:master",
                head: "#{@forker}:new-branch-same-sha-2",
                user: @forker,
                title: "Duplicate sha"
      refute pull2.valid?, "should not be able to create another pull with this head_sha"
      assert_includes_match /cannot have more than #{GitHub.duplicate_head_sha_limit} pull requests with the same head_sha/, pull2.errors[:base]
    end
  end

  test "creating the tracking ref for the head commit" do
    assert_equal @fork.heads.find("topic").target_oid,
                 @source.refs.read("refs/pull/#{@pull.number}/head").target_oid
  end

  test "grabbing the base and head sha from the comparison on create" do
    assert @pull.save
    refute_nil @pull.base_sha
    refute_nil @pull.head_sha
    assert_equal @pull.comparison.base_sha, @pull.base_sha
    assert_equal @pull.comparison.head_sha, @pull.head_sha
  end

  test "calculating optimal SHA1s for historical changes object" do
    assert_equal @source.ref_to_sha("master"), @pull.comparison.base_sha
    assert_equal @fork.ref_to_sha("topic"),  @pull.comparison.head_sha

    changes = @pull.historical_comparison
    assert changes.cross_repository?
    assert_equal "owner", changes.base_user_login
    assert_equal @source.ref_to_sha("master"), changes.base_ref
    assert_equal "forker", changes.head_user_login
    assert_equal @fork.ref_to_sha("topic"), changes.head_ref
    assert_equal 3, changes.commits.length
    assert_equal "diverged", changes.status
  end

  test "retrieving pull request timeline" do
    @issue.comments.create(body: "HELLO", user: @owner)
    @issue.comments.create(body: "GOODBYE", user: @forker)

    assert_equal 5, @pull.timeline_for(@owner).length # + 3 commits, no commit comment
  end

  test "retrieving pull request timeline after a lock" do
    Timecop.freeze 1.day.ago do
      @pull.issue.lock(@owner)
    end

    # commit comment that makes it onto the locked thread
    create :commit_comment, user: @owner, repository: @fork,
      position: 1, path: "color.js", commit_id: @commit.oid
    # commit comment that *doesn't* make it onto the locked thread
    create :commit_comment, user: @drama, repository: @fork,
      position: 2, path: "color.js", commit_id: @commit.oid

    assert_equal 4, @pull.timeline_for(@drama).length
  end

  test "retrieving pull request timeline after set archived" do
    @source.set_archived

    # commit comment that makes it onto the locked thread
    create :commit_comment, user: @owner, repository: @fork,
      position: 1, path: "color.js", commit_id: @commit.oid
    # commit comment that *doesn't* make it onto the locked thread
    create :commit_comment, user: @drama, repository: @fork,
      position: 2, path: "color.js", commit_id: @commit.oid

    assert_equal 3, @pull.timeline_for(@drama).length
  end

  test "keeping commit references from in-PR commits out of the timeline" do
    @repo = @pull.repository

    pr_commit = @pull.changed_commits.last
    @issue.reference_from_commit(@owner, pr_commit.oid)
    @issue.events.create!(event: "merged", commit_id: pr_commit.oid, actor: @owner)

    pre_pr_oid    = @repo.refs.read("master").target.parent_oids.first
    pre_pr_commit = @repo.commits.find(pre_pr_oid)

    # It may seem odd to get the commit from the oid only to use the oid
    # immediately afterwards, but the commit is used later
    @issue.reference_from_commit(@owner, pre_pr_commit.oid)

    timeline = @pull.timeline_for(@owner)
    assert_equal 5, timeline.length  # 3 commits + 1 commit reference + 1 commit merge event
    commit_refs = timeline.select { |i|  i.is_a?(IssueEvent) && i.reference? && i.commit? }
    commit_refs.collect!(&:commit)

    refute_includes commit_refs, pr_commit
    assert_includes commit_refs, pre_pr_commit
  end

  test "keeping the before-merge close event out of the timeline" do
    @pull.repository

    perform_enqueued_pr_jobs do
      Timecop.travel(2.minutes.ago) do
        assert @pull.close(@owner)
      end
      Timecop.travel(1.minute.ago) do
        assert @pull.open(@owner)
      end
      assert @pull.merge(@owner)
    end

    timeline = @pull.timeline_for(@owner)
    # the referenced event referencing the merge commit is filtered out

    assert_equal 6, timeline.length  # 3 commits + 3 events (close, reopen, merge)

    events = timeline[3..-1].collect(&:event)
    assert_equal %w[closed reopened merged], events
  end

  test "does not include pending comments from other users in review_comment_threads" do
    repo = create(:private_repository, owner: @owner, from_example: :pull_request_source)
    repo.add_member @forker, action: :write

    forked = create(:fork_repository, forker: @forker, fork_repo: repo, from_example: :pull_request_fork)

    pull =
      create(:pull_request,
        repository: repo,
        base_repository: repo,
        base_user: repo.owner,
        base_ref: "master",
        head_repository: forked,
        head_user: @forker,
        head_ref: "topic",
        user: @forker,
      )

    review = pull.reviews.create!(
      user: @forker,
      head_sha: pull.head_sha,
    )

    comment = create(:pull_request_review_comment,
      pull_request: pull,
      user: @forker,
      commit_id: pull.head_sha,
      path: "file10",
      original_position: 1,
      body: "this is a pending comment",
      pull_request_review_id: review.id,
    )
    assert_predicate comment, :pending?

    assert_empty pull.review_comment_threads_for(@owner)
  end

  test "does include your own pending comments in review_comment_threads" do
    review = @pull.reviews.create!(
      user: @forker,
      head_sha: @pull.head_sha,
    )

    comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @forker,
      commit_id: @pull.head_sha,
      path: "file10",
      original_position: 1,
      body: "ship it",
      pull_request_review_id: review.id,
    )

    assert_equal [comment], @pull.review_comment_threads_for(@forker).first.comments
  end

  test "does not include pending comments from other users in file_review_comment_threads_for" do
    repo = create(:private_repository, owner: @owner, from_example: :pull_request_source)
    repo.add_member @forker, action: :write

    forked = create(:fork_repository, forker: @forker, fork_repo: repo, from_example: :pull_request_fork)


    pull =
      create(:pull_request,
        repository: repo,
        base_repository: repo,
        base_user: repo.owner,
        base_ref: "master",
        head_repository: forked,
        head_user: @forker,
        head_ref: "topic",
        user: @forker,
      )

    review = pull.reviews.create!(
      user: @forker,
      head_sha: pull.head_sha,
    )

    comment = create(:pull_request_review_comment,
      pull_request: pull,
      user: @forker,
      commit_id: pull.head_sha,
      path: "file10",
      body: "this is a pending comment",
      pull_request_review_id: review.id,
      subject_type: :file,
      blob_position: nil,
    )
    assert_predicate comment, :pending?

    assert_empty pull.file_review_comment_threads_for(@owner)
  end

  test "does include your own pending comments in file_review_comment_threads" do
    review = @pull.reviews.create!(
      user: @forker,
      head_sha: @pull.head_sha,
    )

    comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @forker,
      commit_id: @pull.head_sha,
      path: "file10",
      body: "ship it",
      pull_request_review_id: review.id,
      subject_type: :file,
      blob_position: nil,
    )

    assert_equal [comment], @pull.file_review_comment_threads_for(@forker).first.comments
  end

  test "review comments are sorted by creation date" do
    review = @pull.reviews.create!(
      user: @forker,
      head_sha: @pull.head_sha,
    )

    comment1 = Timecop.freeze(5.minutes.from_now) do
      create(:pull_request_review_comment,
        pull_request: @pull,
        user: @forker,
        commit_id: @pull.head_sha,
        path: "file10",
        original_position: 1,
        body: "ship it",
        pull_request_review_id: review.id,
      )
    end

    comment2 = Timecop.freeze(2.minutes.from_now) do
      create(:pull_request_review_comment,
        pull_request: @pull,
        user: @forker,
        commit_id: @pull.head_sha,
        path: "file10",
        original_position: 1,
        body: "ship it",
        pull_request_review_id: review.id,
      )
    end

    assert_equal [comment2, comment1], @pull.review_comments_for(@forker)
  end

  test "handles repositioning positionless review threads" do

    review_thread = create(:pull_request_review_thread, pull_request: @pull)

    nil_positions = PullRequestReviewComment::POSITIONING_ATTRS.zip(Array.new(PullRequestReviewComment::POSITIONING_ATTRS.length, nil)).to_h
    %w[diff_hunk subject_type].each { |key| nil_positions.delete(key) }
    review_thread.update_columns(nil_positions.merge({ "left_blob" => false, "outdated" => false, "compressed_diff_hunk" => nil }))
    refute_predicate review_thread, :has_positioning_data?
    assert_equal [review_thread], @pull.recalculate_all_positions
  end

  context "blocked_from_reviewing?" do
    test "returns true if blocked by the repository owner" do
      refute @pull.blocked_from_reviewing?(@drama)

      @pull.repository.owner.block(@drama)
      @pull.reload

      assert @pull.blocked_from_reviewing?(@drama)
    end

    test "returns true if blocked by PR owner and does not have write+ access" do
      refute @pull.blocked_from_reviewing?(@drama)

      @pull.user.block(@drama)
      @pull.reload

      assert @pull.blocked_from_reviewing?(@drama)
    end

    test "returns false, even if blocked by PR owner, if they do have write+ access" do
      @pull.repository.add_member(@drama, action: :write)

      @pull.user.block(@drama)
      @pull.reload

      refute @pull.blocked_from_reviewing?(@drama)
    end
  end

  test "setting author for commits" do
    @pull.save!

    user = create(:user, email: "SomeUser@someplace.com")
    ref = @fork.heads.find("topic")

    metadata = { message: "empty commit",
      committer: { email: user.email, name: "someone" },
    }

    perform_enqueued_pr_jobs do
      ref.append_commit(metadata, user)
    end

    metadata = { message: "empty commit 2",
      committer: { email: "rToMaYkO@gmail.com", name: "someone else" },
    }

    perform_enqueued_pr_jobs do
      ref.append_commit(metadata, user)
    end

    @pull.reload

    emails  = @pull.changed_commits.collect(&:author_email)
    authors = @pull.changed_commits.collect(&:author)

    assert_equal ["rtomayko@gmail.com", "rtomayko@gmail.com", "drama@example.com", user.email, "rToMaYkO@gmail.com"], emails
    assert_equal [@ryan, @ryan, nil, user, @ryan], authors
  end if GitHub.email_detect_generic_domains?

  test "creating a revert branch" do
    repo = create(:repository, owner: preview_user, from_example: :simple)

    base_ref = repo.heads.find("master")
    head_ref = repo.heads.create("topic", base_ref.target_oid, repo.owner)

    metadata = { message: "blah", committer: repo.owner }

    head_ref.append_commit(metadata, repo.owner) do |files|
      files.add("blah.txt", "blahblahblah")
    end

    pull = PullRequest.create_for!(repo,
      user: repo.owner,
      base: "#{repo.owner}:master",
      head: "#{repo.owner}:topic",
      title: "blah",
      body: "blah",
    )

    perform_enqueued_pr_jobs do
      assert pull.merge.first
    end

    repo.reload
    base_ref = repo.heads.find("master")

    assert repo.blob(base_ref.target_oid, "blah.txt")

    revert_branch, error = perform_enqueued_pr_jobs do
      pull.revert(pull.user)
    end

    assert_nil error
    assert_nil repo.blob(revert_branch.target_oid, "blah.txt")
  end

  test "creating a revert branch for a squash-merge" do
    repo = create(:repository, owner: preview_user, from_example: :simple)

    base_ref = repo.heads.find("master")

    head_ref = repo.heads.create("topic", base_ref.target_oid, repo.owner)
    head_ref.append_commit({ message: "blah", committer: repo.owner }, repo.owner) do |files|
      files.add("blah.txt", "blahblahblah")
    end

    head_ref.append_commit({ message: "blah", committer: repo.owner }, repo.owner) do |files|
      files.add("blah.txt", "blahblahblah1234")
    end

    pull = PullRequest.create_for!(repo,
      user: repo.owner,
      base: "#{repo.owner}:master",
      head: "#{repo.owner}:topic",
      title: "blah",
      body: "blah",
    )

    perform_enqueued_pr_jobs do
      assert pull.merge(method: :squash).first
    end

    base_ref = repo.heads.find("master")

    other_head_ref = repo.heads.create("other-topic", base_ref.target_oid, repo.owner)
    other_head_ref.append_commit({ message: "another change", committer: repo.owner }, repo.owner) do |files|
      files.add("other.txt", "This is another file")
    end

    other_pull = PullRequest.create_for!(repo,
      user: repo.owner,
      base: "#{repo.owner}:master",
      head: "#{repo.owner}:other-topic",
      title: "blah",
      body: "blah",
    )

    perform_enqueued_pr_jobs do
      assert other_pull.merge(method: :squash).first
    end

    assert repo.blob(base_ref.target_oid, "blah.txt")

    revert_branch, error = perform_enqueued_pr_jobs do
      pull.revert(pull.user)
    end

    assert_nil error
    assert_nil repo.blob(revert_branch.target_oid, "blah.txt")
    refute_nil repo.blob(revert_branch.target_oid, "other.txt")
  end

  test "merging old PRs where mergeable and merge_commit_sha got out of sync" do
    @pull.update!(mergeable: true, merge_commit_sha: nil)
    assert @pull.merge.first
  end

  test "closing a PR deletes the hidden merge and rebase refs" do
    @pull.create_merge_commit

    assert_predicate @pull.repository.refs.read(@pull.rebase_ref), :exist?
    assert_predicate @pull.repository.refs.read(@pull.merge_ref), :exist?

    perform_enqueued_pr_jobs do
      @pull.close
    end

    refute_predicate @pull.repository.refs.read(@pull.rebase_ref), :exist?
    refute_predicate @pull.repository.refs.read(@pull.merge_ref), :exist?
  end

  test "closing a PR via its issue deletes the hidden merge and rebase refs" do
    @pull.create_merge_commit

    assert_predicate @pull.repository.refs.read(@pull.rebase_ref), :exist?
    assert_predicate @pull.repository.refs.read(@pull.merge_ref), :exist?

    perform_enqueued_pr_jobs do
      @pull.issue.reload.close
    end

    refute_predicate @pull.repository.refs.read(@pull.rebase_ref), :exist?
    refute_predicate @pull.repository.refs.read(@pull.merge_ref), :exist?
  end

  test "merging a PR deletes the hidden merge and rebase refs" do
    @pull.create_merge_commit

    assert_predicate @pull.repository.refs.read(@pull.rebase_ref), :exist?
    assert_predicate @pull.repository.refs.read(@pull.merge_ref), :exist?

    perform_enqueued_pr_jobs do
      @pull.merge
    end

    refute_predicate @pull.repository.refs.read(@pull.rebase_ref), :exist?
    refute_predicate @pull.repository.refs.read(@pull.merge_ref), :exist?
  end

  test "destroying all tracking refs of a PR deletes the hidden merge and rebase refs" do
    @pull.create_merge_commit

    assert_predicate @pull.repository.refs.read(@pull.rebase_ref), :exist?
    assert_predicate @pull.repository.refs.read(@pull.merge_ref), :exist?

    @pull.destroy_tracking_refs

    refute_predicate @pull.repository.refs.read(@pull.rebase_ref), :exist?
    refute_predicate @pull.repository.refs.read(@pull.merge_ref), :exist?
  end

  test "merging a PR with an unknown merge method fails" do
    err = assert_raises(ArgumentError) { @pull.merge method: :foobar }
    assert_equal "Unknown merge method", err.message
  end

  test "related issue rollup summary is not updated when a repository is missing during PR destroy" do
    @pull.update!(mergeable: true, merge_commit_sha: nil)
    assert @pull.merge.first

    # It should be noticed that the repository is missing, and the update checks skipped
    Issue.any_instance.expects(:update_notification_summary).never

    @pull.repository.delete
    @pull.reload
    @pull.destroy
  end

  context "#maintain_tracking_ref" do
    test "skips updating tracking refs if the pull's repository is missing" do
      @pull.issue.delete
      @pull.reload

      assert_nil @pull.maintain_tracking_ref(@creator)
    end

    test "skips updating tracking refs if the pull's issue is missing" do
      @pull.repository.delete
      @pull.reload

      assert_nil @pull.maintain_tracking_ref(@creator)
    end

    test "repo.pushed_at is not changed" do
      GitHub.flipper[:skip_update_pushed_at_on_ref_update].enable

      Timecop.freeze do
        @pull.repository.update_attribute(:pushed_at, 1.week.ago)

        @pull.maintain_tracking_ref(@creator)

        assert_equal @pull.repository.pushed_at.change(usec: 0).utc, 1.week.ago.change(usec: 0).utc
      end
    end
  end

  test "restrict the PR to only be merged if the head ref is at an expected point" do
    good_commit = @pull.head_repository.heads.find("topic").target_oid
    bad_commit  = good_commit.reverse

    result  = T.let(false, T::Boolean)
    message = T.let(nil, T.nilable(String))

    perform_enqueued_pr_jobs do
      result, message = @pull.merge(expected_head: bad_commit)
    end

    refute result
    assert_equal "Head branch was modified. Review and try the merge again.", message

    perform_enqueued_pr_jobs do
      result, message = @pull.merge(expected_head: good_commit)
    end

    assert result
    assert_match /\A[0-9a-f]{40}\z/, message, "should be the merge commit OID"
  end

  unless GitHub.enterprise?
    test "merging the PR as a user with no primary email address" do
      User.any_instance.stubs(:must_verify_email?).returns(true)

      result, message, status = @pull.merge(@owner)

      refute result
      assert_match /email address must be verified/, message
      assert_equal :denied, status
    end
  end

  test "merging the PR with unsatisfied required status checks" do
    @pull.repository.protect_branch(@pull.base_ref_name, creator: @owner, required_status_checks: { contexts: %w[ci/janky], include_admins: true }, entry_point: :test_case)

    result, message, status = @pull.merge(@owner)

    refute result
    assert_equal "Required status check \"ci/janky\" is expected.", message
    assert_equal :protected_branch, status
  end

  test "leaves pull requests hanging around with the head_repository_id when the head_repository is destroyed" do
    @pull.save!
    fork_id = @fork.id
    @fork.destroy

    assert_nil Repository.find_by(id: fork_id)
    assert pr = PullRequest.find_by(id: @pull.id)
    assert_equal fork_id, pr&.head_repository_id
  end

  test "combined status returns the combined status for the head sha" do
    @pull.save!
    status = @pull.combined_status
    assert_equal @pull.head_sha, status.sha
    assert_equal @pull.base_repository, status.repository
  end

  context "#create_merge_commit" do
    test "does not try to prepare a rebase when repo doesn't support merge/rebase merges" do
      GitHub.flipper[:cprmc_skip_rebase_via_api].enable(@source)

      @source.update_merge_settings(@owner, merge_allowed: false)
      @source.update_merge_settings(@owner, rebase_allowed: false)
      refute @pull.repository.merge_commit_allowed?
      refute @pull.repository.rebase_merge_allowed?

      assert @pull.create_merge_commit
      assert_equal true, @pull.reload.mergeable

      refute_predicate @source.refs.read(@pull.rebase_ref), :exist?
    end

    test "stores rebase conflicts" do
      refute @pull.rebase_conflicts?
      perform_enqueued_pr_jobs do
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

      @pull.reload.create_merge_commit
      assert @pull.rebase_conflicts?

      @pull.merge(@pull.user)
      refute @pull.rebase_conflicts?
    end

    test "doesn't erroneously mark a PR as unmergeable when we haven't fetched the necessary objects" do
      assert_predicate @pull, :cross_repo?

      metadata = { message: "blah", committer: @fork.owner }
      commit = @fork.heads.find("topic").append_commit(metadata, @fork.owner) {}

      # commit should not be in the base repo
      refute @pull.base_repository.rpc.object_exists?(commit.oid, "commit")

      @pull.update_column(:head_sha, commit.oid)

      assert_equal false, @pull.create_merge_commit
      assert_nil @pull.mergeable
    end

    test "promptly returns nil for closed PRs" do
      refute_predicate @pull, :closed?
      @pull.close(@owner)
      assert_predicate @pull, :closed?

      assert_nil @pull.create_merge_commit
    end

    test "does not update `mergeable` in the database if the pull request's head_sha moved" do
      assert_predicate @pull, :cross_repo?

      @pull.create_merge_commit
      assert_predicate @pull, :mergeable?

      perform_enqueued_pr_jobs do
        metadata = { message: "blah", committer: @fork.owner }
        commit = @fork.heads.find("topic").append_commit(metadata, @fork.owner) {}
      end

      @pull.create_merge_commit
      assert_nil @pull.mergeable

      @pull.reload
      @pull.create_merge_commit
      assert_predicate @pull, :mergeable?
    end

    test "indicates a draft pull request with commits is mergeable" do
      repo = create(:repository, owner: @ryan, from_example: :pull_request_source)
      head_ref = repo.heads.create("topic", repo.heads.find("master").target, @ryan)
      head_ref.append_commit({ message: "a change", committer: @ryan }, @ryan) do |files|
        files.add("README.txt", "one\ntwo\nthree\n")
      end
      pull = create(:pull_request, repository: repo, base_repository: repo, base_user: @ryan,
                    base_ref: "master", head_repository: repo, head_user: @ryan, head_ref: "topic",
                    user: @ryan, draft: true)
      pull.create_merge_commit
      assert_predicate pull, :currently_mergeable?
    end

    test "does not leave any unsaved changes on the pull request" do
      refute_predicate @pull, :changed?

      @pull.create_merge_commit

      refute_predicate @pull, :changed?
    end
  end

  context "instrumentation" do
    test "create is included in audit log" do
      pr = T.let(nil, T.nilable(PullRequest))
      events = assert_performed_audit_entries(count: 1, only: "pull_request.create") do
        pr = PullRequest.create_for!(@org_repo, title: "hello", user: @owner, base: "master", head: "master-forward-2")
      end
      assert_subset_hash({ pull_request_id: pr&.id, actor_id: @owner.id, repo_id: @org_repo.id, repo: "#{@org.login}/#{@org_repo.name}", org: @org.login, org_id: @org.id, user: @owner.login, user_id: @owner.id }, events.first)
    end

    test "close is included in audit log" do
      events = assert_performed_audit_entries(count: 1, only: "pull_request.close") do
        @pull.close(@pull.user)
      end
      assert_subset_hash({ pull_request_id: @pull.id, actor_id: @pull.user_id }, events.first)
    end

    test "reopen is included in audit log" do
      @pull.close(@pull.user)
      events = assert_performed_audit_entries(count: 1, only: "pull_request.reopen") do
        @pull.reopened(@pull.user)
      end
      assert_subset_hash({ pull_request_id: @pull.id, actor_id: @pull.user_id }, events.first)
    end

    test "merge is included in audit log" do
      events = assert_performed_audit_entries(count: 1, only: "pull_request.merge") do
        @pull.merge(@pull.user)
      end
      assert_subset_hash({ pull_request_id: @pull.id, actor_id: @pull.user_id }, events.first)
    end

    test "indirect merge is included in audit log" do
      before = @pull.head_sha
      events = assert_performed_audit_entries(count: 1, only: "pull_request.indirect_merge") do
        # Stub the sync job to always say that PR is "merged"
        @pull.base_repository.stubs(:spokes_api).returns(FakeSpokesApiAlwaysMerged.new)

        @pull.synchronize!(user: @pull.user, repo: @pull.repository)
      end
      after = @pull.head_sha
      # the head_sha does not really change because we are only stubbing out the merged check. This only asserts that
      # the values are in the audit log
      assert_subset_hash({ pull_request_id: @pull.id, actor_id: @pull.user_id, before: before, after: after }, events.first)
    end

    test "marked 'draft' is included in audit log" do
      events = assert_performed_audit_entries(count: 1, only: "pull_request.converted_to_draft") do
        @pull.convert_to_draft(user: @pull.user)
      end
      assert_subset_hash({ pull_request_id: @pull.id, actor_id: @pull.user_id }, events.first)
    end

    test "marked 'in progress' is included in audit log" do
      events = assert_performed_audit_entries(count: 1, only: "pull_request.in_progress") do
        @pull.in_progress_state!
      end
      assert_subset_hash({ pull_request_id: @pull.id, actor_id: @pull.user_id }, events.first)
    end

    test "marked 'ready_for_review' is included in audit log" do
      @pull.update!(draft: true)
      events = assert_performed_audit_entries(count: 1, only: "pull_request.ready_for_review") do
        @pull.ready_for_review!(user: @pull.user)
      end
      assert_subset_hash({ pull_request_id: @pull.id, actor_id: @pull.user_id }, events.first)
    end

    test "primary_resource is in the payload" do
      event_count = 0
      event_payload = T.let({}, Hash)
      subscriber = GitHub.subscribe("pull_request.create") do |_, _, _, _, payload|
        event_payload = payload
        event_count += 1
      end

      pull = PullRequest.create_for!(@org_repo, title: "hello", user: @owner, base: "master", head: "master-forward-2")
      expected_payload = {
        pull_request_id: pull.id,
        pull_request_url: pull.permalink,
        pull_request_title: pull.title,
        user_id: @owner.id,
        user: @owner.login,
        repo: pull.repository.nwo,
        repo_id: pull.repository_id,
        public_repo: pull.repository.public?,
        org: @org_repo.organization.display_login,
        org_id: @org_repo.organization_id,
        actor: @owner.display_login,
        actor_id: @owner.id,
      }

      assert_equal 1, event_count
      assert_subset_hash expected_payload, event_payload
      assert_equal pull.attributes, event_payload[:primary_resource]
    ensure
      GitHub.unsubscribe(subscriber)
    end

    test "emits event when conflict is introduced" do
      @pull.create_merge_commit
      assert_equal @pull.mergeable, true

      expected = {
        mergeable: false,
        pull_request_id: @pull.id,
        pull_request_url: @pull.permalink,
        pull_request_title: @pull.title,
        repo: @pull.repository.nwo,
        repo_id: @pull.repository_id,
        public_repo: @pull.repository.public?,
        user: @forker.login,
        user_id: @forker.id,
      }
      event_count = 0
      subscriber = GitHub.subscribe("pull_request.mergeability") do |_, _, _, _, payload|
        assert_subset_hash expected, payload

        event_count += 1
      end

      create_conflicting_commits(@pull)

      @pull.reload
      assert_nil @pull.mergeable

      @pull.create_merge_commit
      assert_equal @pull.mergeable, false
      assert_equal 1, event_count
    ensure
      GitHub.unsubscribe(subscriber)
    end

    test "emits event when previous conflict has been resolved" do
      # 1. Create conflict
      create_conflicting_commits(@pull)
      @pull.reload

      @pull.create_merge_commit
      refute @pull.mergeable
      refute_nil @pull.conflict

      expected = {
        mergeable: true,
        pull_request_id: @pull.id,
        pull_request_url: @pull.permalink,
        pull_request_title: @pull.title,
        repo: @pull.repository.nwo,
        repo_id: @pull.repository_id,
        public_repo: @pull.repository.public?,
        user: @forker.login,
        user_id: @forker.id,
      }
      event_count = 0
      subscriber = GitHub.subscribe("pull_request.mergeability") do |_, _, _, _, payload|
        assert_subset_hash expected, payload

        event_count += 1
      end

      # 2. Resolve conflict
      perform_enqueued_pr_jobs do
        changes = -> (files) { files.remove("blah.txt") }
        create(:commit, repository: @pull.base_repository, branch: @pull.base_ref, changes: changes)
      end

      # 3. Create merge commit and assert event fired
      @pull.reload
      @pull.create_merge_commit
      assert_equal @pull.mergeable, true
      assert_equal 1, event_count
    ensure
      GitHub.unsubscribe(subscriber)
    end

    test "emits an event when mergeable is initially checked (and there is no conflict)" do
      event_count = 0
      subscriber = GitHub.subscribe("pull_request.mergeability") do |_, _, _, _, payload|
        assert payload[:mergeable]
        event_count += 1
      end

      assert_nil @pull.mergeable
      assert_nil @pull.conflict

      @pull.create_merge_commit
      assert_equal 1, event_count
    ensure
      GitHub.unsubscribe(subscriber)
    end

    test "emit an event when mergeable is initially checked (and there is a conflict)" do
      event_count = 0
      subscriber = GitHub.subscribe("pull_request.mergeability") do |_, _, _, _, payload|
        refute payload[:mergeable]
        event_count += 1
      end

      create_conflicting_commits(@pull)
      @pull.reload

      assert_nil @pull.mergeable
      assert_nil @pull.conflict

      @pull.create_merge_commit
      assert_equal 1, event_count
    ensure
      GitHub.unsubscribe(subscriber)
    end

    test "doesn't emit an event when pull remains mergeable" do
      @pull.create_merge_commit

      event_count = 0
      subscriber = GitHub.subscribe("pull_request.mergeability") do |_, _, _, _, _payload|
        event_count += 1
      end

      @pull.create_merge_commit

      assert_equal 0, event_count
    ensure
      GitHub.unsubscribe(subscriber)
    end

    test "doesn't emit an event when conflict remains" do
      create_conflicting_commits(@pull)
      @pull.reload
      @pull.create_merge_commit

      event_count = 0
      subscriber = GitHub.subscribe("pull_request.mergeability") do |_, _, _, _, _payload|
        event_count += 1
      end

      @pull.create_merge_commit

      assert_equal 0, event_count
    ensure
      GitHub.unsubscribe(subscriber)
    end

    test "doesn't emit an event when conflict can't be calculated" do
      event_count = 0
      subscriber = GitHub.subscribe("pull_request.mergeability") do |_, _, _, _, _payload|
        event_count += 1
      end

      pull = create(:pull_request, :disable_disk_access, repository: @pull.repository)
      pull.create_merge_commit

      assert_equal false, pull.mergeable
      assert_nil pull.conflict
      assert_equal 0, event_count
    ensure
      GitHub.unsubscribe(subscriber)
    end

    test "audit log events include repo information" do
      events = assert_performed_audit_entries(count: 1, only: "pull_request.create") do
        PullRequest.create_for!(@org_repo, title: "hello", user: @owner, base: "master", head: "master-forward-2")
      end
      assert_subset_hash({ repo: @org_repo.nwo, repo_id: @org_repo.id, user: @owner.login, user_id: @owner.id }, events.first)
    end

    test "audit log events include owner information for PRs against org repos" do
      events = assert_performed_audit_entries(count: 1, only: "pull_request.create") do
        PullRequest.create_for!(@org_repo, title: "hello", user: @owner, base: "master", head: "master-forward-2")
      end
      assert_subset_hash({ org: @org.name, org_id: @org.id, user: @owner.login, user_id: @owner.id }, events.first)
    end

    test "audit log events do not include owner information for PRs against user repos" do
      events = assert_performed_audit_entries(count: 1, only: "pull_request.create") do
        PullRequest.create_for!(@source, title: "hello", user: @forker, base: "master", head: "forker:topic-2")
      end
      assert_subset_hash({ user: @forker.login, user_id: @forker.id }, events.first)

      assert_equal @forker.id, events.first[:user_id],
        "Expected the user ID of the actor (#{@forker.id}) not the owner (#{@owner.id}), got: #{events.first[:user_id]}"

      assert_nil events.first[:org]
      assert_nil events.first[:org_id]
    end

    test "audit log events include business information when it's available" do
      business = create(:business)
      @org.update! business: business

      events = assert_performed_audit_entries(count: 1, only: "pull_request.create") do
        PullRequest.create_for!(@org_repo, title: "hello", user: @owner, base: "master", head: "master-forward-2")
      end

      assert_subset_hash({ business_id: business.id, business: business.slug, user: @owner.login, user_id: @owner.id }, events.first)
    end

    test "update_branch with rebase is included in audit log" do
      @pull.create_merge_commit
      events = assert_performed_audit_entries(count: 1, only: "pull_request.rebase") do
        @pull.rebase_head_on_base(
          user: @fork.user,
          author_email: @pull.user.default_author_email(@pull.repository, @pull.head_sha),
        )
      end
      assert_subset_hash({ pull_request_id: @pull.id, actor_id: @pull.user_id }, events.first)
    end
  end

  test "doesn't return conflicted files if merge commit is outdated" do
    create_conflicting_commits(@pull)
    @pull.create_merge_commit
    @pull.reload
    assert_equal @pull.mergeable, false
    assert_equal ["blah.txt"], @pull.conflicted_files

    @pull.merge_base_into_head(user: @pull.user, base_oid: @pull.base_sha, resolve_conflicts: { "blah.txt" => "This might conflict?" })
    assert_nil @pull.mergeable
    assert_nil @pull.conflicted_files
  end

  context "#conflict_resolvable?" do
    test "returns false for a pull request without conflicts" do
      assert_nil @pull.mergeable

      @pull.create_merge_commit
      assert_equal @pull.mergeable, true

      refute_predicate @pull, :conflict_resolvable?
    end

    test "returns true for a pull request with resolvable conflicts" do
      assert_nil @pull.mergeable

      @pull.create_merge_commit
      assert_equal @pull.mergeable, true

      create_conflicting_commits(@pull)

      @pull.reload
      assert_nil @pull.mergeable

      @pull.create_merge_commit
      assert_equal @pull.mergeable, false

      assert_predicate @pull, :conflict_resolvable?
    end

    test "returns false if the conflict is outdated by a new change on the base branch" do
      assert_nil @pull.mergeable

      @pull.create_merge_commit
      assert_equal @pull.mergeable, true

      create_conflicting_commits(@pull)

      @pull.reload
      assert_nil @pull.mergeable

      @pull.create_merge_commit
      assert_equal @pull.mergeable, false

      assert_predicate @pull, :conflict_resolvable?

      perform_enqueued_pr_jobs do
        metadata = { message: "blah", committer: @fork.owner }
        commit = @pull.base_repository.heads.find(@pull.base_ref).append_commit(metadata, @fork.owner) do |files|
          files.add("zelda.txt", "Breath of the Wild")
        end
      end

      @pull.reload
      assert_nil @pull.mergeable
      refute_nil @pull.conflict
      refute_predicate @pull, :conflict_resolvable?
    end

    test "returns false if the conflict is outdated by a new change on the head branch" do
      assert_nil @pull.mergeable

      @pull.create_merge_commit
      assert_equal @pull.mergeable, true

      create_conflicting_commits(@pull)

      @pull.reload
      assert_nil @pull.mergeable

      @pull.create_merge_commit
      assert_equal @pull.mergeable, false

      assert_predicate @pull, :conflict_resolvable?

      perform_enqueued_pr_jobs do
        metadata = { message: "blah", committer: @fork.owner }
        commit = @pull.head_repository.heads.find(@pull.head_ref).append_commit(metadata, @fork.owner) do |files|
          files.add("zelda.txt", "Breath of the Wild")
        end
      end

      @pull.reload
      assert_nil @pull.mergeable
      refute_nil @pull.conflict
      refute_predicate @pull, :conflict_resolvable?
    end
  end

  test "create_merge_commit doesn't clobber simultaneous updates from merge" do
    refute @pull.closed?

    trial_merge_oid, real_merge_oid = [@pull.safe_user, @owner].map do |user|
      @pull.repository.commits.create_merge_commit(
        user,
        @pull.mergeable_base_sha,
        @pull.mergeable_head_sha,
        resolve_conflicts: nil,
      ).first.oid
    end

    refute_equal trial_merge_oid, real_merge_oid

    PullRequest::Prepare.any_instance.stubs(:perform).returns([true, trial_merge_oid], [true, real_merge_oid])

    fresh_pull = PullRequest.find(@pull.id)
    fresh_pull.issue # load it now so it isn't loaded fresh after the merge

    success, error = @pull.merge
    assert success, "expected pull to merge"

    expected_merge_oid = @pull.merge_commit_sha

    fresh_pull.create_merge_commit

    assert_equal expected_merge_oid, PullRequest.find(fresh_pull.id).merge_commit_sha
  end

  # https://github.com/github/github/pull/30105#issuecomment-71137620
  test "can synchronize a public cross-repo pull when the head commit is in the cache but not in the base repository" do
    assert @pull.cross_repo?
    assert @pull.base_repository.public?

    # Use the cache for the GitRPC cache.
    enable_cache_storage
    commit = T.let(nil, T.untyped)
    with_enqueued_pr_sync_jobs do # don't run MaintainTrackingRefJob
      metadata = { message: "blah", committer: @fork.owner }
      commit = @fork.heads.find("topic").append_commit(metadata, @fork.owner) {}

      # commit should not be in the base repo
      refute @pull.base_repository.rpc.object_exists?(commit.oid, "commit")

      # but it should be in the cache
      assert @pull.base_repository.rpc.cache.get(commit.gitrpc_cache_key)
    end

    @pull.reload

    assert_equal commit.oid, @pull.head_sha

    reset_cache
    disable_cache_storage
  end

  test "can merge a PR even if it hasn't had the MaintainTrackingRef job run yet" do
    assert @pull.cross_repo?

    metadata = { message: "blah", committer: @fork.owner }
    commit = @fork.heads.find("topic").append_commit(metadata, @fork.owner) {}
    @pull.catch_up

    # commit should not be in the base repo
    refute @pull.base_repository.rpc.object_exists?(commit.oid, "commit")

    @pull.reload

    success, error = @pull.merge
    assert success, error
  end

  context "while importing" do
    test "skips specific callbacks during import" do
      GitHub.importing do
        pull_request = PullRequest.new
        pull_request.expects(:record_concrete_commit_points).never
        pull_request.expects(:prefix_refs).never
        pull_request.expects(:repo_and_base_must_match).never
        pull_request.expects(:must_have_commits).never
        pull_request.expects(:base_ref_is_real_branch).never
        pull_request.expects(:head_ref_is_not_namespaced).never
        pull_request.expects(:duplicate_check).never
        pull_request.expects(:validate_refs_readable).never
        pull_request.expects(:head_ref_is_not_from_merge_queue).never

        pull_request.save
      end
    end

    test "does not kick off update_close_issue_references background job" do
      create(:importable_pull_request,
        repository: @source,
        base_repository: @source,
        head_repository: @fork,
        base_ref: "master",
        head_ref: "topic-2",
        base_user: @source.owner,
        head_user: @fork.owner,
        base_sha: @source.heads["master"].sha,
        head_sha: @fork.heads["topic-2"].sha,
      )

      refute_includes enqueued_jobs.pluck("job_class"), "UpdateCloseIssueReferencesJob"
    end
  end

  test "async_body_html does not unfurl issues referenced in the same repo without context[:viewer]" do
    marketplace_domain.repository_settings.clear_docker_file_status(@source.id)
    assert_equal @pull.async_body_html.sync, "<p dir=\"auto\">hey <a class=\"user-mention notranslate\" data-hovercard-type=\"user\" data-hovercard-url=\"/users/vince/hovercard\" data-octo-click=\"hovercard-link-click\" data-octo-dimensions=\"link_type:self\" href=\"https://github.com/vince\">@vince</a> look at this real quick</p>"

    @pull.issue.body = @pull.default_body + "##{@pull.issue.number}"
    refute_includes @pull.async_body_html.sync, @pull.title
  end

  test "async_body_html does not unfurl issues referenced in different repo without context[:viewer]" do
    marketplace_domain.repository_settings.clear_docker_file_status(@source.id)
    repo = create(:repository)
    issue = create(:issue, repository: repo)

    @pull.issue.body = "closes #{repo.nwo}##{@pull.issue.number}"
    refute_includes @pull.async_body_html.sync, issue.title
  end

  test "async_body_html unufurls pull request references when context passes viewer" do
    issue = create(:issue, repository: @private_repo)
    pull_request =
      PullRequest.new(
        repository: @private_repo,
        base_repository: @private_repo,
        base_user: @private_repo.owner,
        base_ref: "master",
        head_repository: @private_repo,
        head_user: @private_repo.owner,
        head_ref: "topic",
        issue: issue,
        user: @private_repo.owner,
      )

    pull_request.issue&.body = "<li>fixes #{@pull.repository.nwo}##{@pull.issue.number}</li>"
    context = { viewer: @private_repo.owner, cap_filter: cap_authorizing_filter([@pull.issue]), unfurl_references: true }
    assert_includes pull_request.async_body_html(context: context).sync, @pull.title

    @private_repo.add_member(@drama)
    context = { viewer: @drama, cap_filter: cap_authorizing_filter([@pull.issue]), unfurl_references: true }
    assert_includes pull_request.async_body_html(context: context).sync, @pull.title
  end

  test "async_body_html has tooltip for link to issues closed by the pull request" do
    issue = create(:issue, repository: @private_repo)
    pull_request =
      PullRequest.new(
        repository: @private_repo,
        base_repository: @private_repo,
        base_user: @private_repo.owner,
        base_ref: "master",
        head_repository: @private_repo,
        head_user: @private_repo.owner,
        head_ref: "topic",
        issue: issue,
        user: @private_repo.owner,
      )

    pull_request.issue&.body = "fixes #{issue.repository.nwo}##{issue.number}"
    context = { viewer: @private_repo.owner, cap_filter: cap_authorizing_filter([@pull.issue]), unfurl_references: true }

    body_html = pull_request.async_body_html(context: context).sync
    assert T.unsafe(body_html).include?("aria-label=\"This pull request closes issue ##{@issue.number}.\"")
  end

  test "default_body returns PULL_REQUEST_TEMPLATE content when one is found" do
    example_repo :magic_config_files, @source

    assert_equal "Please describe your change:\n", @pull.default_body
  end

  test "default_body returns org level PULL_REQUEST_TEMPLATE content when one is found" do
    org = create(:organization)
    org_repo = create(:repository, owner: org, from_example: :rebase_pull_request)
    dot_github_repo = create(:repository, owner: org, name: ".github", from_example: :magic_config_files)

    pull = create(:pull_request,
      repository: org_repo,
      base_repository: org_repo,
      base_user: org_repo.owner,
      base_ref: "master",
      head_repository: org_repo,
      head_user: org_repo.owner,
      head_ref: "contrib",
      issue: create(:issue, repository: org_repo),
    )
    assert_equal "Please describe your change:\n", pull.default_body
  end

  test "default_body returns nested PULL_REQUEST_TEMPLATE content when found" do
    example_repo :dot_github_w_nesting, @source
    @pull.body_template_name = "contribution.md"
    assert_equal "Thanks for your contribution.\n", @pull.default_body
  end

  test "default_body returns nested PULL_REQUEST_TEMPLATE content from org's .github repo when one is found" do
    org = create(:organization)
    org_repo = create(:repository, owner: org, from_example: :rebase_pull_request)
    dot_github_repo = create(:repository, owner: org, name: ".github", from_example: :dot_github_w_nesting)

    pull = create(:pull_request,
      repository: org_repo,
      base_repository: org_repo,
      base_user: org_repo.owner,
      base_ref: "master",
      head_repository: org_repo,
      head_user: org_repo.owner,
      head_ref: "contrib",
      issue: create(:issue, repository: org_repo),
    )
    pull.body_template_name = "contribution.md"
    assert_equal "Thanks for your contribution.\n", pull.default_body
  end

  test "default_body returns nested PULL_REQUEST_TEMPLATE content from user's .github repo when one is found" do
    user_repo = create(:repository, owner: @owner, from_example: :rebase_pull_request)
    dot_github_repo = create(:repository, owner: @owner, name: ".github", from_example: :dot_github_w_nesting)

    pull = create(:pull_request,
      repository: user_repo,
      base_repository: user_repo,
      base_user: user_repo.owner,
      base_ref: "master",
      head_repository: user_repo,
      head_user: user_repo.owner,
      head_ref: "contrib",
      issue: create(:issue, repository: user_repo),
    )
    pull.body_template_name = "contribution.md"
    assert_equal "Thanks for your contribution.\n", pull.default_body
  end

  test "default_body doesn't insert extra newlines before PULL_REQUEST_TEMPLATE content when the diff is a single commit with short message" do
    short_message = "Short commit message"
    assert short_message.length < Commits::CommitMessage::MAX, "message was expected to be shorter than Commits::CommitMessage::MAX"

    example_repo :magic_config_files, @source

    base_ref = @source.heads.find("master")
    head_ref = @source.heads.create("short-message", base_ref.target, @source.owner)

    head_ref.append_commit({ message: short_message, committer: @source.owner }, @source.owner)

    issue = create(:issue,
      user: @source.owner,
      repository: @source,
      body: "",
    )

    pull = PullRequest.new(
      repository: @source,
      base_repository: @source,
      base_user: @source.owner,
      base_ref: "master",
      head_repository: @source,
      head_user: @source.owner,
      head_ref: "short-message",
      issue: issue,
      user: @source.owner,
    )

    assert_equal "Please describe your change:\n", pull.default_body
  end

  test "default_body finds PULL_REQUEST_TEMPLATE content in .github/" do
    example_repo :dot_github, @source

    assert_equal "What'd you change?\n", @pull.default_body
  end

  test "default_body only finds templates named PULL_REQUEST_TEMPLATE" do
    example_repo :dirty_dotgithub, @source

    assert_empty @pull.default_body
  end

  test "default_body contains the remainder of a long single-commit message" do
    message = ("Long message " * 10).strip
    assert message.length > Commits::CommitMessage::MAX, "message is expected to be longer than Commits::CommitMessage::MAX"

    base_ref = @source.heads.find("master")
    head_ref = @source.heads.create("long-message", base_ref.target, @source.owner)

    head_ref.append_commit({ message: message, committer: @source.owner }, @source.owner)

    issue = create(:issue,
      user: @source.owner,
      repository: @source,
      body: "",
    )

    pull = PullRequest.new(
      repository: @source,
      base_repository: @source,
      base_user: @source.owner,
      base_ref: "master",
      head_repository: @source,
      head_user: @source.owner,
      head_ref: "long-message",
      issue: issue,
      user: @source.owner,
    )

    assert_equal Commits::CommitMessage.new(message).body, pull.default_body
  end

  test "default_body contains the remainder of a long single-commit message before the PULL_REQUEST_TEMPLATE content" do
    example_repo :magic_config_files, @source

    message = ("Long message " * 10).strip
    assert message.length > Commits::CommitMessage::MAX, "message is expected to be longer than Commits::CommitMessage::MAX"

    base_ref = @source.heads.find("master")
    head_ref = @source.heads.create("long-message", base_ref.target, @source.owner)

    head_ref.append_commit({ message: message, committer: @source.owner }, @source.owner)

    issue = create(:issue,
      user: @source.owner,
      repository: @source,
      body: "",
    )

    pull = PullRequest.new(
      repository: @source,
      base_repository: @source,
      base_user: @source.owner,
      base_ref: "master",
      head_repository: @source,
      head_user: @source.owner,
      head_ref: "long-message",
      issue: issue,
      user: @source.owner,
    )

    assert_equal "#{Commits::CommitMessage.new(message).body}\n\nPlease describe your change:\n", pull.default_body
  end

  test "when flagged, single-commit PR's default_body is unwrapped" do
    example_repo :magic_config_files, @source

    message = <<~MESSAGE
      Here biginneth the Book of the Tales of Caunterbury.

      Whan that Aprille with his shoures soote The droghte of March hath
      perced to the roote, And bathed every veyne in swich licour, Of which
      vertu engendred is the flour;

      Whan Zephirus eek with his swete breeth Inspired hath in every holt and
      heeth The tendre croppes, and the yonge sonne Hath in the Ram his halfe
      cours yronne, And smale foweles maken melodye, That slepen al the nyght
      with open eye, So priketh hem nature in hir corages;

      Thanne longen folk to goon on pilgrimages, And palmeres for to seken
      straunge strondes, To ferne halwes, kowthe in sondry londes;

      And specially, from every shires ende Of Engelond, to Caunterbury they
      wende, The hooly blisful martir for to seke, That hem hath hopen whan
      that they were seeke.
    MESSAGE

    base_ref = @source.heads.find("master")
    head_ref = @source.heads.create("long-message", base_ref.target, @source.owner)

    head_ref.append_commit({ message:, committer: @source.owner }, @source.owner)

    issue = create(:issue,
      user: @source.owner,
      repository: @source,
      body: "",
    )

    pull = PullRequest.new(
      repository: @source,
      base_repository: @source,
      base_user: @source.owner,
      base_ref: "master",
      head_repository: @source,
      head_user: @source.owner,
      head_ref: "long-message",
      issue: issue,
      user: @source.owner,
    )

    assert_equal <<~EXPECTED, pull.default_body
      Whan that Aprille with his shoures soote The droghte of March hath perced to the roote, And bathed every veyne in swich licour, Of which vertu engendred is the flour;

      Whan Zephirus eek with his swete breeth Inspired hath in every holt and heeth The tendre croppes, and the yonge sonne Hath in the Ram his halfe cours yronne, And smale foweles maken melodye, That slepen al the nyght with open eye, So priketh hem nature in hir corages;

      Thanne longen folk to goon on pilgrimages, And palmeres for to seken straunge strondes, To ferne halwes, kowthe in sondry londes;

      And specially, from every shires ende Of Engelond, to Caunterbury they wende, The hooly blisful martir for to seke, That hem hath hopen whan that they were seeke.

      Please describe your change:
    EXPECTED
  end

  test "default_body is empty when there's no PULL_REQUEST_TEMPLATE or commit message remainder" do
    assert_empty @pull.default_body
  end

  test "disallows PR creation for rando with no push access regardless of body" do
    example_repo :magic_config_files, @source
    assert_equal @pull.default_body, "Please describe your change:\n"

    @pull.issue.body = @pull.default_body + "\r" # ensure that carriage returns are removed when comparing
    @pull.user = create(:user)
    assert @pull.user_unable_to_create_pr?

    @pull.issue.body = "I added a real description this time"
    assert @pull.user_unable_to_create_pr?
  end unless GitHub.enterprise?

  test "can destroy a PR's issue after the repo and PR are gone" do
    assert PullRequest.find_by(id: @pull.id), "Pull request should exist before destroy"
    issue_id = @pull.issue.id
    pull_id = @pull.id

    @pull.repository.delete
    @pull.delete

    perform_enqueued_pr_jobs do
      Issue.destroy(issue_id)
    end

    assert !Issue.find_by(id: issue_id), "The destroyed issue(#{issue_id}) should be gone"
    assert !PullRequest.find_by(id: pull_id), "A destroyed issue should destroy the PR(#{pull_id})"
  end

  test "can destroy a PR" do
    assert PullRequest.find_by(id: @pull.id), "Pull request should exist before destroy"
    perform_enqueued_pr_jobs do
      @pull.destroy
    end
    assert !PullRequest.find_by(id: @pull.id), "Pull request should not exist after destroy"
  end

  test "can destroy the repository issues relation when there is a PR present" do
    assert PullRequest.find_by(id: @pull.id), "Pull request should exist before destroy"
    p_id = @pull.id
    i_id = @pull.issue.id

    issue = @pull.issue
    assert Issue.find_by(id: issue.id), "Issue backing the PR should exist"

    perform_enqueued_pr_jobs do
      @source.issues.destroy_all
    end
    assert !PullRequest.find_by(id: p_id), "Pull request should not exist after destroy"
    assert !Issue.find_by(id: i_id), "Issue should not exist after destroy"

  end

  test "it can have one import" do
    import = create(:import)
    pull_request = create(:pull_request, :disable_disk_access)

    pull_request.import = import
    pull_request.save!
    assert_equal pull_request.import, import
  end

  test "cross collab validation should succeed if it meets conditions" do
    base_repo = @source
    head_repo = @fork

    pull = create(:pull_request,
      repository: base_repo,
      base_repository: base_repo,
      base_user: base_repo.owner,
      base_ref: "master",
      head_repository: head_repo,
      head_user: head_repo.owner,
      head_ref: "master-plus-one-commit",
      issue: create(:issue, repository: base_repo, user: head_repo.owner),
    )

    pull.fork_collab_state = :allowed

    assert pull.save
  end

  test "cross collab validation should fail on PR update if it does meet conditions" do
    base_repo = @source
    head_repo = @fork

    pull = create(:pull_request,
      repository: base_repo,
      base_repository: base_repo,
      base_user: base_repo.owner,
      base_ref: "master",
      head_repository: head_repo,
      head_user: head_repo.owner,
      head_ref: "master-plus-one-commit",
      issue: create(:issue, repository: base_repo),
    )

    pull.fork_collab_state = :allowed

    refute pull.save
    assert_equal 1, pull.errors.size
  end

  test "cross collab validation should always be done on create" do
    base_repo = @source
    head_repo = @fork

    pull = build(:pull_request,
      repository: base_repo,
      base_repository: base_repo,
      base_user: base_repo.owner,
      base_ref: "master",
      head_repository: head_repo,
      head_user: head_repo.owner,
      head_ref: "master-plus-one-commit",
      issue: create(:issue, repository: base_repo),
      fork_collab_state: :allowed
    )

    refute pull.save
    assert_equal 1, pull.errors.size
  end

  test "cross collab validation should not run if the field has not changed" do
    base_repo = @source
    head_repo = @fork

    pull = create(:pull_request,
      repository: base_repo,
      base_repository: base_repo,
      base_user: base_repo.owner,
      base_ref: "master",
      head_repository: head_repo,
      head_user: head_repo.owner,
      head_ref: "master-plus-one-commit",
      issue: create(:issue, repository: base_repo),
    )

    pull.fork_collab_state = :denied # default value

    PullRequest.any_instance.expects(:fork_collab_allowed?).never

    assert pull.save
  end

  context "searchability" do
    test "is not searchable with a missing repository" do
      assert @pull.is_searchable?, "regular pull request is searchable"
      @pull.repository = nil
      refute @pull.is_searchable?, "missing repository"
    end

    test "is not searchable with an inactive repository" do
      assert @pull.is_searchable?, "regular pull request is searchable"
      @pull.repository.active = false
      refute @pull.is_searchable?, "inactive repository"
    end

    if GitHub.spamminess_check_enabled?
      test "is not searchable with a spammy repository" do
        assert @pull.is_searchable?, "regular pull request is searchable"
        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { @pull.repository.owner.mark_as_spammy }
        @pull.reload

        refute @pull.is_searchable?, "spammy repository"
      end
    end

    test "is not searchable with a disabled repository" do
      assert @pull.is_searchable?, "regular pull request is searchable"
      @pull.repository.stubs(:disabled?).returns(true)

      refute @pull.is_searchable?, "disabled repository"
    end

    test "is not searchable when repository access is disabled" do
      assert @pull.is_searchable?, "regular pull request is searchable"
      @pull.repository.access.disable("size", @pull.repository.owner)

      refute @pull.is_searchable?, "repository access disabled repository"
    end

    test "is not searchable with a missing issue" do
      assert @pull.is_searchable?, "regular pull request is searchable"
      @pull.issue = nil
      refute @pull.is_searchable?, "missing issue"
    end

    test "is not searchable when user_hidden" do
      assert @pull.is_searchable?, "regular pull request is searchable"
      @pull.stubs(:user_hidden).returns(true)
      refute @pull.is_searchable?, "user_hidden"
    end

    test "is searchable with a missing base_user" do
      assert @pull.is_searchable?, "regular pull request is searchable"
      @pull.base_user = nil
      assert @pull.is_searchable?, "missing base_user is searchable"
    end

    if GitHub.spamminess_check_enabled?
      test "is not searchable if the author is spammy" do
        assert @pull.is_searchable?, "regular pull request is searchable"

        @pull.user = @forker
        @pull.user.mark_as_spammy
        refute @pull.is_searchable?, "author is spammy"
      end
    end
  end

  context "#resynchronize_search_index" do
    test "increments datadog counter" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      assert_difference 'GitHub.dogstats.increments("pull_request.reindexed").count', 1 do
        @pull.resynchronize_search_index
      end
    end

    test "logs to failbot with an appropriate app" do
      Failbot.expects(:report).with do |_e, context|
        assert_equal "github-pull-requests", context[:app]
      end

      @pull.resynchronize_search_index
    end

    test "synchronizes index" do
      Search.expects(:add_to_search_index).with("pull_request", @pull.id)

      @pull.resynchronize_search_index
    end
  end

  context "#async_load_pull_request_commit" do
    test "returns a PullRequestCommit object for the given commit oid" do
      pull_request_commit = @pull.async_load_pull_request_commit(@pull.head_sha).sync

      refute_nil pull_request_commit
      assert_instance_of Platform::Models::PullRequestCommit, pull_request_commit

      commit = pull_request_commit.commit
      refute_nil commit

      assert_instance_of Commit, commit
      assert_equal @pull.head_sha, commit.oid
      assert_equal @pull.repository, commit.repository
    end

    test "returns nil if no commit with the given commit oid is found" do
      assert_nil @pull.async_load_pull_request_commit("deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef").sync
    end

    test "head_sha deleted on merged pr still returns PullRequestCommit object" do
      # Add a new commit that won't be referenced by anything else in @fork
      perform_enqueued_pr_jobs do
        @fork.heads.find("topic").append_commit({ message: "a commit", committer: @fork.owner }, @fork.owner) do |files|
          files.add("some-new-file", "foo")
        end
      end

      @pull.reload

      assert @fork.commits.exist?([@pull.head_sha]), "#{@pull.head_sha} should be reachable in @fork"
      perform_enqueued_pr_jobs { assert @pull.merge }
      perform_enqueued_pr_jobs { assert @pull.cleanup_head_ref(@fork.owner) }

      # Trigger gc so the pull's HEAD will be removed in the @fork repo
      gc!(@fork)
      refute @fork.commits.exist?([@pull.head_sha]), "#{@pull.head_sha} should not be reachable in @fork"

      # But we'll still find the commit since it's been merged into the @source repo
      pull_request_commit = @pull.async_load_pull_request_commit(@pull.head_sha).sync
      refute_nil pull_request_commit
      assert_instance_of Platform::Models::PullRequestCommit, pull_request_commit
    end
  end

  context "#async_viewer_can_update?" do
    test "returns whether the given user can edit the issue" do
      refute_predicate @pull, :locked?

      repo   = @pull.repository
      owner  = repo.owner
      collab = create(:user)
      author = @pull.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      repo.add_member(collab)

      # author is not a repo collab
      refute_includes repo.members, author

      assert @pull.async_viewer_can_update?(owner).sync
      assert @pull.async_viewer_can_update?(collab).sync
      assert @pull.async_viewer_can_update?(author).sync
      refute @pull.async_viewer_can_update?(staff).sync
      refute @pull.async_viewer_can_update?(user).sync
      refute @pull.async_viewer_can_update?(nil).sync

      assert @pull.issue.lock(owner)
      assert_predicate @pull.issue, :locked?

      # Find a new object so that we don't keep any cached ivars around
      @pull = PullRequest.find(@pull.id)

      assert @pull.async_viewer_can_update?(owner).sync
      assert @pull.async_viewer_can_update?(collab).sync
      refute @pull.async_viewer_can_update?(author).sync
      refute @pull.async_viewer_can_update?(staff).sync
      refute @pull.async_viewer_can_update?(user).sync
      refute @pull.async_viewer_can_update?(nil).sync
    end
  end

  context "#async_viewer_cannot_update_reasons" do
    test "returns a list of reason codes that describe why the the given user can not edit" do
      refute_predicate @pull, :locked?

      repo   = @pull.repository
      owner  = repo.owner
      collab = create(:user)
      author = @pull.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      repo.add_member(collab)

      # author is not a repo collab
      refute_includes repo.members, author

      assert_empty @pull.async_viewer_cannot_update_reasons(owner).sync
      assert_empty @pull.async_viewer_cannot_update_reasons(collab).sync
      assert_empty @pull.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], @pull.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:insufficient_access], @pull.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], @pull.async_viewer_cannot_update_reasons(nil).sync

      assert @pull.issue.lock(owner)
      assert_predicate @pull.issue, :locked?

      # Find a new object so that we don't keep any cached ivars around
      @pull = PullRequest.find(@pull.id)

      assert_empty @pull.async_viewer_cannot_update_reasons(owner).sync
      assert_empty @pull.async_viewer_cannot_update_reasons(collab).sync
      assert_equal [:locked], @pull.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:locked, :insufficient_access], @pull.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:locked, :insufficient_access], @pull.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], @pull.async_viewer_cannot_update_reasons(nil).sync
    end

    context "when interaction limits are enabled" do
      test "returns insufficient_access for non-collaborator author" do
        author = @pull.user

        assert_empty @pull.async_viewer_cannot_update_reasons(author).sync

        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:collaborators_only, @source.owner)
        @pull.issue.reload_repository

        assert_equal [:insufficient_access], @pull.async_viewer_cannot_update_reasons(author).sync
      end

      test "returns empty list for collaborator author" do
        collab = create(:user)
        @source.add_member(collab)

        interaction = RepositoryInteractionAbility.new(@source)
        interaction.set_ability(:collaborators_only, @source.owner)
        assert_empty @pull.async_viewer_cannot_update_reasons(collab).sync
      end
    end
  end

  context "#head_is_default_or_protected_branch?" do
    test "returns true if head branch is protected on head repo" do
      branch = create(:protected_branch, repository: @pull.head_repository, name: @pull.head_ref_name)

      assert @pull.head_is_default_or_protected_branch?
    end

    test "returns false if head branch is protected on base repo" do
      branch = create(:protected_branch, repository: @pull.base_repository, name: @pull.head_ref_name)

      refute @pull.head_is_default_or_protected_branch?
    end

    test "returns true if head branch is the default branch on head repo" do
      refute @pull.head_is_default_or_protected_branch?

      # Create ref on source repo otherwise the `update_default_branch` will fail
      @source.heads.create(@pull.head_ref_name, @source.heads.find("master").target, @source.owner)

      assert @pull.head_repository.update_default_branch(@pull.head_ref_name)
      assert_equal @pull.head_ref_name, @pull.head_repository.default_branch

      assert @pull.head_is_default_or_protected_branch?
    end

    test "returns false if head branch matches the default branch on base repo but is not default branch on head repo" do
      refute @pull.head_is_default_or_protected_branch?

      # Create ref on source repo otherwise the `update_default_branch` will fail
      @source.heads.create(@pull.head_ref_name, @source.heads.find("master").target, @source.owner)

      assert @pull.base_repository.update_default_branch(@pull.head_ref_name)
      assert_equal @pull.head_ref_name, @pull.base_repository.default_branch

      refute @pull.head_is_default_or_protected_branch?
    end
  end

  context "#fork_collab_available_for_user?" do
    test "returns false for an org-forked pull request" do
      org_fork = create(:fork_repository, forker: @owner, fork_repo: @source, organization: @org, from_example: :pull_request_fork)

      org_fork_pull_request = PullRequest.create(
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: org_fork,
        head_user: @owner,
        head_ref: "master-plus-one-commit",
        issue: create(:issue, repository: @source),
        user: @owner,
      )

      refute org_fork_pull_request.fork_collab_available_for_user?(@owner)
    end

    test "returns true for user-forked pull request to a private, org-owned repo" do
      repo = create(:private_repository, owner: @org)
      repo.allow_private_repository_forking(actor: @owner)
      repo.add_member @forker, action: :write

      forked = create(:fork_repository, forker: @forker, fork_repo: repo, from_example: :pull_request_fork)

      user_fork_pull_request = PullRequest.create(
        repository: repo,
        base_repository: repo,
        base_user: @org,
        base_ref: "master",
        head_repository: forked,
        head_user: @forker,
        head_ref: "master-plus-one-commit",
        issue: create(:issue, repository: repo),
        user: @forker,
      )

      assert user_fork_pull_request.fork_collab_available_for_user?(@forker)
    end

    test "returns true for user-forked pull request to a public, org-owned repo" do
      repo = create(:repository, owner: @org)
      repo.add_member @forker, action: :write

      forked = create(:fork_repository, forker: @forker, fork_repo: repo, from_example: :pull_request_fork)

      user_fork_pull_request = PullRequest.create(
        repository: repo,
        base_repository: repo,
        base_user: @org,
        base_ref: "master",
        head_repository: forked,
        head_user: @forker,
        head_ref: "master-plus-one-commit",
        issue: create(:issue, repository: repo),
        user: @forker,
      )

      assert user_fork_pull_request.fork_collab_available_for_user?(@forker)
    end
  end

  context "#memex_suggestion_hash" do
    test "dumps relevant attributes of the object" do
      # Fri, March 6, 2020 8pm UTC.
      updated_at = Time.utc(2020, 3, 06, 20, 00, 00)

      pull = create(
        :pull_request,
        :disable_disk_access,
        repository: @org_repo,
        user: @owner,
      ).tap do |p|
        p.issue.title = "The Antidote"
        p.issue.save!

        # Apparently the fixture for pull request creation touches `updated_at`.
        # Reset it here so that we can assert on the serialization format of the
        # timestamp below.
        p.update(updated_at: updated_at)
      end

      expected_hash = {
        id: pull.id,
        isDraft: false,
        lastInteractionAt: nil,
        number: pull.number,
        state: "open",
        title: "The Antidote",
        type: "PullRequest",
        updatedAt: "2020-03-06T20:00:00Z",
      }

      assert_equal expected_hash, pull.memex_suggestion_hash
    end
  end

  context "#memex_content_hash" do
    test "dumps base attributes of the object" do
      pull = create(
        :pull_request,
        :disable_disk_access,
        repository: @org_repo,
        user: @owner,
      )

      expected_hash = {
        id: pull.id,
        url: pull.permalink,
      }

      assert_equal expected_hash, pull.memex_content_hash
    end
  end

  context "#enqueue_mergeable_update" do
    test "enqueues if pull is open" do
      assert_enqueued_with(job: CreatePullRequestMergeCommitJob) do
        @pull.enqueue_mergeable_update
      end
    end

    test "skips enqueue if pull is closed" do
      @pull.close
      assert_no_enqueued_jobs(only: CreatePullRequestMergeCommitJob) do
        @pull.enqueue_mergeable_update
      end
    end

    test "skips enqueue if pull is merged" do
      @pull.merge
      assert_no_enqueued_jobs(only: CreatePullRequestMergeCommitJob) do
        @pull.enqueue_mergeable_update
      end
    end

    test "doesn't enqueue if base ref is missing" do
      @pull.update_attribute(:base_ref, "no-such-branch")
      assert_nil @pull.current_base_sha
      refute @pull.currently_mergeable?

      assert_no_enqueued_jobs(only: CreatePullRequestMergeCommitJob) do
        @pull.enqueue_mergeable_update
      end
    end
  end

  context "#can_change_base_branch?" do
    if GitHub.merge_queues_enabled?
      test "returns true for pull request that is open and not in merge queue" do
        GitHub.flipper[:merge_queue].enable(@source)
        @source.protect_branch(@source.default_branch,
          creator: @source.owner,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )

        assert_predicate @pull, :open?
        assert_nil @pull.merge_queue_entry
        assert_predicate @pull, :can_change_base_branch?
      end

      test "returns true if in merge queue if feature flag is disabled" do
        # MQ is unconditionally enabled for GHES repos
        skip if GitHub.enterprise?

        entry = create(:merge_queue_entry)
        pull = entry.pull_request

        assert_predicate entry.queue.branch_rule_evaluator, :merge_queue_enabled?

        GitHub.flipper[:merge_queue].disable

        assert_predicate pull, :open?
        refute_nil pull.merge_queue_entry
        assert_predicate pull, :can_change_base_branch?
      end

      test "returns false for pull request that is open and but in merge queue" do
        entry = create(:merge_queue_entry)
        pull = entry.pull_request
        repo = entry.repository
        GitHub.flipper[:merge_queue].enable(repo)
        repo.protect_branch(repo.default_branch,
          creator: repo.owner,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )

        assert_predicate pull, :open?
        refute_nil pull.merge_queue_entry
        refute_predicate pull, :can_change_base_branch?
      end

      test "returns false for pull request that is closed and not in merge queue" do
        GitHub.flipper[:merge_queue].enable(@source)
        @source.protect_branch(@source.default_branch,
          creator: @source.owner,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )
        @pull.close(@pull.user)
        refute_predicate @pull, :open?
        assert_nil @pull.merge_queue_entry
        refute_predicate @pull, :can_change_base_branch?
      end
    else
      test "returns true for open pull request" do
        assert_predicate @pull, :open?
        assert_predicate @pull, :can_change_base_branch?
      end

      test "returns false for closed pull request" do
        @pull.close(@pull.user)
        refute_predicate @pull, :open?
        refute_predicate @pull, :can_change_base_branch?
      end
    end
  end

  test "base ref is deleted" do
    base_ref = @source.heads.find(@pull.base_ref)

    perform_enqueued_pr_jobs do
      assert base_ref.delete(@source.owner)
    end

    assert !@source.heads.include?(@pull.base_ref)
    assert @pull.reload.closed?
    assert @pull.events.map(&:event).include?("base_ref_deleted")
  end

  context "perform auto-merge" do
    test "does nothing if there's no auto-merge request for this pull request" do
      @pull.perform_auto_merge
      refute_predicate @pull, :merged?
    end

    test "does nothing if already merged" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request
      pull.merge
      pull.expects(:merge).never

      pull.perform_auto_merge
    end

    test "does nothing if enabler is admin, branch policies are enforced on admins, and status is blocked" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true
      }, enforce_admins: true, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.create_merge_commit

      assert @source.adminable_by?(@owner)
      assert_equal :blocked, @pull.merge_state(viewer: @owner).status
      refute @pull.merge_state(viewer: @owner).admin_override_possible?

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "does nothing if enabler is admin, branch policies are enforced on admins, and status is unknown when there are unmet requirements" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        required_approving_review_count: 1
      }, enforce_admins: true, entry_point: :test_case)

      create(:auto_merge_request, pull_request: @pull, user: @owner)

      assert @source.adminable_by?(@owner)
      assert_equal :unknown, @pull.merge_state(viewer: @owner).status
      refute @pull.merge_state(viewer: @owner).clean?
      refute @pull.merge_state(viewer: @owner).admin_override_possible?

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "does nothing if enabler is admin, branch policies are enforced on admins, and status is unknown when all requirements are met" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        required_approving_review_count: 1
      }, enforce_admins: true, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)

      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert @source.adminable_by?(@owner)
      assert_equal :unknown, @pull.merge_state(viewer: @owner).status
      refute @pull.merge_state(viewer: @owner).admin_override_possible?

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "merges if enabler is admin, branch policies are enforced on admins, and status is unstable when all requirements are met" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_status_checks: { include_admins: true, contexts: ["Context 2"], strict: false }, enforce_admins: true, entry_point: :test_case)
      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: @owner, merge_method: "auto_squash_and_merge")
      @pull.create_merge_commit
      create :status, repository: @source,
                state: "failure",
                sha: @pull.head_sha,
                context: "Context 1"
      create :status, repository: @source,
                state: "success",
                sha: @pull.head_sha,
                context: "Context 2"

      assert @source.adminable_by?(@owner)
      assert_equal :unstable, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?

      changed_files = @pull.changed_files_for_instrumentation.map { |file| Hydro::EntitySerializer.changed_file(file, overrides: { change_type: file.change_type_symbol }) }
      expected_hydro_message = {
        actor: Hydro::EntitySerializer.user(@owner),
        actor_profile_location: "",
        author: Hydro::EntitySerializer.user(@pull.user),
        repository: Hydro::EntitySerializer.repository(@pull.repository),
        pull_request: Hydro::EntitySerializer.pull_request(@pull, overrides: { changed_files: changed_files }),
        repository_owner: Hydro::EntitySerializer.user(@pull.repository.owner),
        issue: Hydro::EntitySerializer.issue(@pull.issue),
        merge_action: :AUTO_MERGE,
        merge_method: :SQUASH,
        merge_state_status: :UNSTABLE,
        opener_login: @forker.login,
        opener_profile_location: "",
        protected_branch: Hydro::EntitySerializer.protected_branch(@pull.base_branch_rule_evaluator&.original_protected_branch),
        merge_commit_title: auto_merge_request.commit_title,
        merge_commit_message: @pull.default_squash_commit_message(author: @owner),
        default_merge_commit_message_and_title: false,
        merge_commit_sha: @pull.merge_commit_sha
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestMerge")
    end

    test "does nothing if enabler is admin, branch policies are enforced on admins, and status is behind" do
      @source.refs["master"].append_commit({ message: "Commit", committer: @owner }, @owner) do |files|
        files.add("new-file.txt", "New file")
      end
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_status_checks: { include_admins: true, contexts: ["Context 2"], strict: true }, enforce_admins: true, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.create_merge_commit

      assert @source.adminable_by?(@owner)
      assert_equal :behind, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "does nothing if enabler is admin, branch policies are enforced on admins, and status is dirty" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, enforce_admins: true, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.update_attribute(:mergeable, false)

      assert @source.adminable_by?(@owner)
      assert_equal :dirty, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "merges if enabler is admin, branch policies are enforced on admins, and status is has_hooks" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, enforce_admins: true, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.create_merge_commit
      PullRequest::MergeState.any_instance.stubs(:has_hooks?).returns(true)
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert @source.adminable_by?(@owner)

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
    end

    test "does nothing if enabler is admin, branch policies aren't enforced on admins, and status is blocked" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, enforce_admins: false, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.create_merge_commit

      assert @source.adminable_by?(@owner)
      assert_equal :blocked, @pull.merge_state(viewer: @owner).status
      assert @pull.merge_state(viewer: @owner).admin_override_possible?
      assert @pull.merge_state(viewer: @owner).admin_override_possible?

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "does nothing if enabler is admin, branch policies aren't enforced on admins, and status is unknown when there are unmet requirements" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, enforce_admins: false, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)

      assert @source.adminable_by?(@owner)
      assert_equal :unknown, @pull.merge_state(viewer: @owner).status
      refute @pull.merge_state(viewer: @owner).clean?
      refute @pull.merge_state(viewer: @owner).admin_override_possible?

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "does nothing if enabler is admin, branch policies aren't enforced on admins, and status is unknown when all requirements are met" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, enforce_admins: false, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)

      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert @source.adminable_by?(@owner)
      assert_equal :unknown, @pull.merge_state(viewer: @owner).status
      refute @pull.merge_state(viewer: @owner).admin_override_possible?

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "merges if enabler is admin, branch policies aren't enforced on admins, and status is unstable when all requirements are met" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_status_checks: { include_admins: true, contexts: ["Context 2"], strict: false }, enforce_admins: true, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.create_merge_commit
      create :status, repository: @source,
                state: "failure",
                sha: @pull.head_sha,
                context: "Context 1"
      create :status, repository: @source,
                state: "success",
                sha: @pull.head_sha,
                context: "Context 2"

      assert @source.adminable_by?(@owner)
      assert_equal :unstable, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
    end

    test "does nothing if enabler is admin, branch policies aren't enforced on admins, and status is behind" do
      @source.refs["master"].append_commit({ message: "Commit", committer: @owner }, @owner) do |files|
        files.add("new-file.txt", "New file")
      end
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_status_checks: { contexts: %w[ci/janky] }, enforce_admins: false, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.create_merge_commit

      assert @source.adminable_by?(@owner)
      assert_equal :behind, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "does nothing if enabler is admin, branch policies aren't enforced on admins, and status is dirty" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_status_checks: { contexts: %w[ci/janky] }, enforce_admins: false, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.update_attribute(:mergeable, false)

      assert @source.adminable_by?(@owner)
      assert_equal :dirty, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "merges if enabler is admin, branch policies aren't enforced on admins, and status is has_hooks" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, enforce_admins: false, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.create_merge_commit
      PullRequest::MergeState.any_instance.stubs(:has_hooks?).returns(true)

      assert @source.adminable_by?(@owner)

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
    end

    test "does nothing if enabler is not admin and status is blocked" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @source.add_member(@forker)
      create(:auto_merge_request, pull_request: @pull, user: @forker)
      @pull.create_merge_commit

      assert_equal :blocked, @pull.merge_state(viewer: @forker).status
      refute @source.adminable_by?(@forker)

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "does nothing if enabler is not admin and status is unknown when some requirements aren't met" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @source.add_member(@forker)
      create(:auto_merge_request, pull_request: @pull, user: @forker)

      refute @source.adminable_by?(@forker)
      assert_equal :unknown, @pull.merge_state(viewer: @forker).status

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "does nothing if enabler is not admin and status is unknown when all requirements are met" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @source.add_member(@forker)
      create(:auto_merge_request, pull_request: @pull, user: @forker)

      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      refute @source.adminable_by?(@forker)
      assert_equal :unknown, @pull.merge_state(viewer: @forker).status

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "merges if enabler is not admin and status is unstable when all requirements are met" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_status_checks: { include_admins: true, contexts: ["Context 2"], strict: false }, enforce_admins: true, entry_point: :test_case)
      @source.add_member(@forker)
      create(:auto_merge_request, pull_request: @pull, user: @forker)
      @pull.create_merge_commit
      create :status, repository: @source,
                state: "failure",
                sha: @pull.head_sha,
                context: "Context 1"
      create :status, repository: @source,
                state: "success",
                sha: @pull.head_sha,
                context: "Context 2"

      refute @source.adminable_by?(@forker)
      assert_equal :unstable, @pull.merge_state(viewer: @forker).status

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
    end

    test "does nothing if enabler is not admin and status is behind" do
      @source.refs["master"].append_commit({ message: "Commit", committer: @owner }, @owner) do |files|
        files.add("new-file.txt", "New file")
      end
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_status_checks: { contexts: %w[ci/janky] }, entry_point: :test_case)
      @source.add_member(@forker)
      create(:auto_merge_request, pull_request: @pull, user: @forker)
      @pull.create_merge_commit

      refute @source.adminable_by?(@forker)
      assert_equal :behind, @pull.merge_state(viewer: @forker).status

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "does nothing if enabler is not admin and status is dirty" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @source.add_member(@forker)
      create(:auto_merge_request, pull_request: @pull, user: @forker)
      @pull.update_attribute :mergeable, false

      refute @source.adminable_by?(@forker)
      assert_equal :dirty, @pull.merge_state(viewer: @forker).status

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
    end

    test "merges if enabler is not admin and status is has_hooks" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @source.add_member(@forker)
      create(:auto_merge_request, pull_request: @pull, user: @forker)
      @pull.create_merge_commit
      PullRequest::MergeState.any_instance.stubs(:has_hooks?).returns(true)
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      refute @source.adminable_by?(@forker)

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
    end

    test "does not merge when require linear history is enabled and merge method is merge commit" do
      @source.repository.protect_branch("master", creator: @source.owner, required_linear_history: true, required_pull_request_reviews: { require_code_owner_reviews: true }, enforce_admins: true, entry_point: :test_case)
      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: @source.owner, merge_method: "auto_merge")
      @pull.create_merge_commit
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert_predicate @pull.merge_state(viewer: auto_merge_request.user), :clean?
      assert_predicate @pull.merge_state(viewer: auto_merge_request.user), :blocked_only_by_required_linear_history?
      assert_equal @pull.merge_state(viewer: auto_merge_request.user).rules_engine_evaluation_result.failed_rule_types, ["required_linear_history"]

      @pull.perform_auto_merge

      refute_predicate @pull, :merged?
      assert_equal auto_merge_request.reload.merge_error, "merge_commit"
    end

    test "merges when require linear history is enabled and merge method is not merge commit" do
      @source.repository.protect_branch("master", creator: @source.owner, required_linear_history: true, required_pull_request_reviews: { require_code_owner_reviews: true }, enforce_admins: true, entry_point: :test_case)
      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: @source.owner, merge_method: "auto_rebase_and_merge")
      @pull.create_merge_commit
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert_predicate @pull.merge_state(viewer: auto_merge_request.user), :clean?
      assert_predicate @pull.merge_state(viewer: auto_merge_request.user), :blocked_only_by_required_linear_history?
      assert_equal @pull.merge_state(viewer: auto_merge_request.user).rules_engine_evaluation_result.failed_rule_types, ["required_linear_history"]

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
    end

    test "merges pull request when status is clean" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @pull.create_merge_commit
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert_equal :clean, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
    end

    test "merges with default when merge_method is auto_merge" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request
      review = pull.reviews.create! user: pull.repository.owner, head_sha: pull.head_sha
      assert review.approve!
      pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      pull.expects(:merge).with(
        auto_merge_request.user,
        author_email: nil,
        message_title: auto_merge_request.commit_title,
        message: auto_merge_request.commit_message,
        method: :merge,
        merge_action: :auto_merge,
        merge_state_status: :clean,
        reflog_data: {},
      ).returns([true, pull.base_sha])

      pull.perform_auto_merge
    end

    test "merges with squash when merge_method is auto_squash_and_merge" do
      auto_merge_request = create(:auto_merge_request, merge_method: :auto_squash_and_merge)
      pull = auto_merge_request.pull_request
      review = pull.reviews.create! user: pull.repository.owner, head_sha: pull.head_sha
      assert review.approve!
      pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      pull.expects(:merge).with(
        auto_merge_request.user,
        author_email: nil,
        message_title: auto_merge_request.commit_title,
        message: auto_merge_request.commit_message,
        method: :squash,
        merge_action: :auto_merge,
        merge_state_status: :clean,
        reflog_data: {},
      ).returns([true, pull.base_sha])

      pull.perform_auto_merge
    end

    test "merges with rebase when merge_method is auto_rebase_and_merge" do
      auto_merge_request = create(:auto_merge_request, merge_method: :auto_rebase_and_merge)
      pull = auto_merge_request.pull_request
      review = pull.reviews.create! user: pull.repository.owner, head_sha: pull.head_sha
      assert review.approve!
      pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      pull.expects(:merge).with(
        auto_merge_request.user,
        author_email: nil,
        message_title: auto_merge_request.commit_title,
        message: auto_merge_request.commit_message,
        method: :rebase,
        merge_action: :auto_merge,
        merge_state_status: :clean,
        reflog_data: {},
      ).returns([true, pull.base_sha])

      pull.perform_auto_merge
    end

    test "if merge fails, auto-merge is disabled" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request
      review = pull.reviews.create! user: pull.repository.owner, head_sha: pull.head_sha
      assert review.approve!
      pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      pull.expects(:merge).with(
        auto_merge_request.user,
        author_email: nil,
        message_title: auto_merge_request.commit_title,
        message: auto_merge_request.commit_message,
        method: :merge,
        merge_action: :auto_merge,
        merge_state_status: :clean,
        reflog_data: {},
      ).returns([false, "rule violation", :repository_rule_violation])

      pull.perform_auto_merge
      refute pull.reload.auto_merge_request.present?
    end

    test "raises error on parent mismatch and does not disable auto-merge" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request
      review = pull.reviews.create! user: pull.repository.owner, head_sha: pull.head_sha
      assert review.approve!
      pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      pull.expects(:merge).with(
        auto_merge_request.user,
        author_email: nil,
        message_title: auto_merge_request.commit_title,
        message: auto_merge_request.commit_message,
        method: :merge,
        merge_action: :auto_merge,
        merge_state_status: :clean,
        reflog_data: {},
      ).returns([false, "Base branch was modified. Review and try the merge again.", :parent_mismatch])

      assert_raises(Git::Ref::ComparisonMismatch) do
        pull.perform_auto_merge
      end
      assert pull.reload.auto_merge_request.present?
    end

    test "if merge fails due to missing workflow scope, auto-merge is disabled" do
      auto_merge_request = create(:auto_merge_request, merge_method: :auto_rebase_and_merge)
      pull = auto_merge_request.pull_request
      review = pull.reviews.create! user: pull.repository.owner, head_sha: pull.head_sha
      assert review.approve!
      pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      pull.expects(:merge).with(
        auto_merge_request.user,
        author_email: nil,
        message_title: auto_merge_request.commit_title,
        message: auto_merge_request.commit_message,
        method: :rebase,
        merge_action: :auto_merge,
        merge_state_status: :clean,
        reflog_data: {},
      ).returns([false, "refusing to allow a GitHub App to create or update workflow `.github/workflows/attack.yml` without `workflows` permission", :workflow_policy_update_error])

      pull.perform_auto_merge
      refute pull.reload.auto_merge_request.present?
    end

    test "if PR is not mergeable the merge_error is updated" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request
      pull.update_attribute(:mergeable, nil)

      pull.perform_auto_merge

      assert_equal "not_mergeable", auto_merge_request.reload.merge_error
    end

    test "merges with non-primary email if auto-merge is set with non-primary email", skip_enterprise: true do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @pull.create_merge_commit
      @owner.add_email("git@hub.com", is_primary: false)
      @owner.emails.each(&:verify!)
      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: @owner, commit_email_address: @owner.emails.where(email: "git@hub.com")[0])
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert_equal :clean, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
      commit = @source.commits.find(@pull.merge_commit_sha)
      assert_equal "git@hub.com", commit.author_email
    end

    test "merges with primary email if auto-merge is set with primary email" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @pull.create_merge_commit
      @owner.add_email("git@hub.com", is_primary: true)
      @owner.emails.each(&:verify!)
      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: @owner, commit_email_address: @owner.primary_user_email)
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert_equal :clean, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
      commit = @source.commits.find(@pull.merge_commit_sha)
      assert_equal "git@hub.com", commit.author_email
    end

    test "merges with primary email if on GitHub Enterprise", enterprise_only: true do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @pull.create_merge_commit
      @owner.add_email("git@hub.com", is_primary: false)
      @owner.emails.each(&:verify!)
      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: @owner, commit_email_address: @owner.emails.where(email: "git@hub.com")[0])
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert_equal :clean, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
      commit = @source.commits.find(@pull.merge_commit_sha)
      assert_equal @owner.primary_user_email.email, commit.author_email
    end

    test "merges with primary email if auto-merge request's email is nil" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @pull.create_merge_commit
      @owner.add_email("git@hub.com", is_primary: true)
      @owner.emails.each(&:verify!)
      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: @owner, commit_email_address: nil)
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert_equal :clean, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
      commit = @source.commits.find(@pull.merge_commit_sha)
      assert_equal "git@hub.com", commit.author_email
    end

    test "merges with github provided email if user's emails are private" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @pull.create_merge_commit
      @owner.add_email("git@hub.com", is_primary: false)
      @owner.emails.each(&:verify!)
      @owner.primary_user_email.toggle_visibility
      assert_predicate @owner.primary_user_email, :private?

      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: @owner, commit_email_address: @owner.emails.with_role("stealth"))
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert_equal :clean, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
      commit = @source.commits.find(@pull.merge_commit_sha)
      assert_equal @owner.outbound_email, commit.author_email
    end

    test "merges and closes when auto-merge was enabled by a github app" do
      app = create(:integration)
      source_app_installation = make_integration_installation(
        integration: app,
        repository: @source,
        permissions: { "contents" => :write },
      )
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true,
      }, entry_point: :test_case)
      @pull.create_merge_commit

      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: source_app_installation.bot)
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      assert_equal :clean, @pull.merge_state(viewer: @owner).status

      @pull.perform_auto_merge

      assert_predicate @pull, :merged?
      assert_predicate @pull, :closed?
    end

    test "merges and closes when auto-merge was enabled by a github app and status checks are required" do
      # === Have another user create the pull request
      @org_repo.add_member(@forker)
      @team.add_member(@forker)

      # === Create the app
      app = create(:integration)
      source_app_installation = make_integration_installation(
        integration: app,
        repository: @org_repo,
        permissions: {
          "contents" => :write,
          "metadata" => :read,
          "pull_requests" => :write,
          "statuses" => :write,
        },
      )

      # === Allow actor to auto_merge
      @org_repo.allow_auto_merge(actor: source_app_installation.bot)

      # === Set up an organization pull and protected branch
      org_pull = PullRequest.create_for!(@org_repo, title: "hello", user: @forker, base: "master", head: "master-forward-2")
      protected_branch = @org_repo.protect_branch(
        org_pull.base_ref_name,
        creator: @owner,
        restrictions: { integrations: [app.slug] },
        entry_point: :test_case,
      )
      assert protected_branch.authorized_actors.include?(source_app_installation), "installation should be authorized on protected branch"
      protected_branch.update_required_status_checks(include_admins: true, contexts: ["test_context"])
      protected_branch.save!
      after_oid = org_pull.create_merge_commit

      perform_enqueued_jobs(only: AutoMergeJob) do
        # === Create a pending status check
        create(
          :status,
          sha: org_pull.head_sha,
          state: "pending",
          creator: @owner,
          repository: @org_repo,
          context: "test_context"
        )

        # === Actor creates an auto_merge request, blocked by pending status check
        AutoMergeRequest.create!(
          pull_request: org_pull,
          user: source_app_installation.bot,
          merge_method: :auto_merge,
          commit_title: "auto merge request"
        )

        # === Successful status check's on_create callback kicks off the auto_merge
        create(
          :status,
          sha: org_pull.head_sha,
          state: "success",
          creator: @owner,
          repository: @org_repo,
          context: "test_context"
        )
      end

      org_pull.reload
      assert_predicate org_pull, :merged?
      assert_predicate org_pull, :closed?
    end

    test "disables automerge when blocked because of authorized_users_only" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request
      PullRequest::MergeState.any_instance.stubs(:blocked_by_unauthorized_protection?).returns(true)
      pull.perform_auto_merge

      pull.reload
      refute_predicate pull, :merged?
      refute_predicate pull, :closed?
      refute_predicate pull.auto_merge_request, :present?
      last_event = pull.events.order("id desc").last
      assert_equal "auto_merge_disabled", last_event.event
      assert_equal "denied", last_event.issue_event_detail.message
    end
  end

  context "enqueue auto-merge job if enabled" do
    test "enqueues job if there is an auto_merge_request" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request

      assert_enqueued_with(job: AutoMergeJob, args: [pull]) do
        pull.enqueue_auto_merge_job_if_enabled
      end
    end

    test "doesn't enqueue job if is not an auto_merge_request" do
      assert_no_enqueued_jobs do
        @pull.enqueue_auto_merge_job_if_enabled
      end
    end

    test "enqueues job to check if pull request is mergeable" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request

      assert_enqueued_with(job: AutoMergeJob, args: [pull]) do
        pull.enqueue_auto_merge_job_if_enabled
      end
    end

    test "enqueues job when require linear history is enabled" do
      @source.repository.protect_branch("master", creator: @source.owner, required_linear_history: true,  required_pull_request_reviews: {
        require_code_owner_reviews: true
      }, enforce_admins: true, entry_point: :test_case)
      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: @source.owner, merge_method: "auto_rebase_and_merge")
      @pull.create_merge_commit
      review = @pull.reviews.create! user: @source.owner, head_sha: @pull.head_sha
      assert review.approve!
      @pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      refute_predicate @pull.merge_state(viewer: auto_merge_request.user), :can_update_ref?
      assert_predicate @pull.merge_state(viewer: auto_merge_request.user), :clean?
      assert_equal @pull.merge_state(viewer: auto_merge_request.user).rules_engine_evaluation_result.failed_rule_types, ["required_linear_history"]

      assert_enqueued_with(job: AutoMergeJob, args: [@pull]) do
        @pull.enqueue_auto_merge_job_if_enabled
      end
    end

    test "enqueues job when merge state is unknown" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true
      }, enforce_admins: true, entry_point: :test_case)
      auto_merge_request = create(:auto_merge_request, pull_request: @pull, user: @source.owner, merge_method: "auto_rebase_and_merge")

      assert_predicate @pull.merge_state(viewer: auto_merge_request.user), :unknown?

      assert_enqueued_with(job: AutoMergeJob, args: [@pull]) do
        @pull.enqueue_auto_merge_job_if_enabled
      end
    end
  end

  context "can enable auto-merge" do
    test "returns true when all conditions are met" do
      @pull.repository.allow_auto_merge(actor: @source.owner)
      assert_equal :unknown, @pull.merge_state(viewer: @source.owner).status
      create(:protected_branch, repository: @pull.repository, name: "master", pull_request_reviews_enforcement_level: "everyone")

      assert @pull.can_enable_auto_merge(actor: @source.owner).allowed?
    end

    test "returns false when auto-merge is not allowed" do
      @source.disallow_auto_merge(actor: @source.owner)
      assert_equal :unknown, @pull.merge_state(viewer: @source.owner).status
      create(:protected_branch, repository: @pull.repository, name: "master", pull_request_reviews_enforcement_level: "everyone")

      refute @pull.can_enable_auto_merge(actor: @source.owner).allowed?
    end

    test "returns false when pull request is mergeable" do
      @pull.repository.allow_auto_merge(actor: @source.owner)
      @pull.create_merge_commit
      assert_equal :clean, @pull.merge_state(viewer: @source.owner).status

      refute @pull.can_enable_auto_merge(actor: @source.owner).allowed?
    end

    test "returns false when pull request is a draft" do
      @pull.repository.allow_auto_merge(actor: @source.owner)
      assert_equal :unknown, @pull.merge_state(viewer: @source.owner).status
      create(:protected_branch, repository: @pull.repository, name: "master", pull_request_reviews_enforcement_level: "everyone")
      @pull.convert_to_draft(user: @source.owner)

      refute @pull.can_enable_auto_merge(actor: @source.owner).allowed?
    end

    test "returns false when pull request is closed" do
      @pull.repository.allow_auto_merge(actor: @source.owner)
      assert_equal :unknown, @pull.merge_state(viewer: @source.owner).status
      create(:protected_branch, repository: @pull.repository, name: "master", pull_request_reviews_enforcement_level: "everyone")
      @pull.close(@source.owner)

      refute @pull.can_enable_auto_merge(actor: @source.owner).allowed?
    end

    test "returns false when pull request is merged" do
      @pull.repository.allow_auto_merge(actor: @source.owner)
      assert_equal :unknown, @pull.merge_state(viewer: @source.owner).status
      create(:protected_branch, repository: @pull.repository, name: "master", pull_request_reviews_enforcement_level: "everyone")
      @pull.stubs(:merged?).returns(true)

      refute @pull.can_enable_auto_merge(actor: @source.owner).allowed?
    end

    test "returns false if user doesn't have access to the repository" do
      @pull.repository.allow_auto_merge(actor: @source.owner)
      assert_equal :unknown, @pull.merge_state(viewer: @source.owner).status
      create(:protected_branch, repository: @pull.repository, name: "master", pull_request_reviews_enforcement_level: "everyone")

      refute @pull.can_enable_auto_merge(actor: @fork.owner).allowed?
    end

    test "returns false if repository does not require reviews, status checks, nor required review thread resolution on base branch" do
      @pull.repository.allow_auto_merge(actor: @source.owner)
      assert_equal :unknown, @pull.merge_state(viewer: @source.owner).status

      refute @pull.can_enable_auto_merge(actor: @source.owner).allowed?
    end

    test "returns false when an AutoMergeRequest already exists" do
      @pull.repository.allow_auto_merge(actor: @source.owner)
      assert_equal :unknown, @pull.merge_state(viewer: @source.owner).status
      create(:protected_branch, repository: @pull.repository, name: "master", pull_request_reviews_enforcement_level: "everyone")

      assert @pull.can_enable_auto_merge(actor: @source.owner).allowed?

      create(:auto_merge_request, pull_request: @pull, user: @source.owner)
      refute @pull.can_enable_auto_merge(actor: @source.owner).allowed?
    end
  end

  context "can disable auto-merge" do
    test "returns false if user doesn't have access to the repo" do
      user = create(:user)
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true
      }, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.reload
      refute_nil @pull.auto_merge_request

      refute @pull.can_disable_auto_merge?(actor: user)
    end

    test "returns false if pull request doesn't have an auto_merge_request" do
      assert_nil @pull.auto_merge_request

      refute @pull.can_disable_auto_merge?(actor: @owner)
    end

    test "returns false if pull request is a draft" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true
      }, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.reload
      refute_nil @pull.auto_merge_request
      @pull.convert_to_draft(user: @owner)
      assert @pull.draft?

      refute @pull.can_disable_auto_merge?(actor: @owner)
    end

    test "returns false if pull request is closed" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true
      }, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.reload
      refute_nil @pull.auto_merge_request
      @pull.close(@owner)
      assert @pull.closed?

      refute @pull.can_disable_auto_merge?(actor: @owner)
    end

    test "returns false if pull request is merged" do
      repo = create(:repository)
      pull = setup_pull_request(repository: repo)
      repo.protect_branch(pull.base_ref_name, creator: repo.owner, required_pull_request_reviews: {
        require_code_owner_reviews: true
      }, entry_point: :test_case)
      repo.allow_auto_merge(actor: repo.owner)
      create(:auto_merge_request, pull_request: pull, user: repo.owner)
      pull.merge
      pull.reload
      refute_nil pull.auto_merge_request
      assert pull.merged?

      refute pull.can_disable_auto_merge?(actor: pull.user)
    end

    test "returns true if user can disable" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true
      }, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.reload
      refute_nil @pull.auto_merge_request

      assert @pull.can_disable_auto_merge?(actor: @owner)
    end

    test "returns true if user is PR author but only has read access to repo" do
      @source.protect_branch(@pull.base_ref_name, creator: @owner, required_pull_request_reviews: {
        require_code_owner_reviews: true
      }, entry_point: :test_case)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @source.add_member(@fork.owner, action: :read)
      @pull.reload
      refute_nil @pull.auto_merge_request

      assert @pull.can_disable_auto_merge?(actor: @fork.owner)
    end
  end

  context "delete auto-merge request on PR state changes" do
    test "Deletes auto-merge request if PR is converted to draft" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request
      pull.convert_to_draft(user: pull.user)
      assert_predicate pull, :draft?
      assert_nil pull.reload.auto_merge_request
    end

    test "Deletes auto-merge request if PR is closed" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request
      pull.close
      assert_predicate pull, :closed?
      assert_nil pull.reload.auto_merge_request
    end

    test "Doesn't delete auto-merge request if PR is merged" do
      auto_merge_request = create(:auto_merge_request)
      pull = auto_merge_request.pull_request
      review = pull.reviews.create! user: pull.repository.owner, head_sha: pull.head_sha
      assert review.approve!
      pull.reset_memoized_attributes # PullRequest caches @latest_enforced_reviews

      pull.merge(pull.user)
      assert_predicate pull, :merged?
      refute_nil pull.reload.auto_merge_request
    end
  end

  context "#pushed_to_head_since_open" do
    test "false for users that have not pushed, true for those that have" do
      refute @pull.pushed_to_head_since_open?(@vince), "expected false for @vince before they push to PR"
      perform_enqueued_pr_jobs do
        @fork.refs.find(@pull.head_ref).append_commit({ message: "a", committer: @vince }, @vince)
      end
      assert @pull.pushed_to_head_since_open?(@vince), "expected true for @vince after they push"
    end

    test "false for users that pushed to the branch before open" do
      travel_to(@pull.created_at - 1.day) do
        perform_enqueued_pr_jobs do
          @fork.refs.find(@pull.head_ref).append_commit({ message: "a", committer: @vince }, @vince)
        end
      end
      refute @pull.pushed_to_head_since_open?(@vince), "expected false for @vince when push is before @pull.created_at"
    end
  end

  context "#in_progress_state!" do
    test "draft PR can always be marked ready for review" do
      owner = create(:user, plan: :pro)
      repo = create(:repository, owner: owner, from_example: :pull_request_source)
      assert repo.plan_supports?(:draft_prs)

      head_ref = repo.heads.create("topic", repo.heads.find("master").target, owner)
      head_ref.append_commit({ message: "a change", committer: owner }, owner) do |files|
        files.add("README.txt", "one\ntwo\nthree\n")
      end
      pull = create(:pull_request, repository: repo, base_repository: repo, base_user: owner,
        head_user: owner, base_ref: "master", head_ref: "topic", draft: true)
      assert pull.draft?

      repo.update!(private: :true)
      repo.reload
      refute repo.plan_supports?(:draft_prs)

      pull.ready_for_review!(user: owner)
      refute pull.draft?
    end

    test "emits hydro event when marking as in progress" do
      @pull.in_progress_state!

      msg = {
        pull_request: Hydro::EntitySerializer.pull_request(@pull),
        issue: Hydro::EntitySerializer.issue(@pull.issue),
        actor: Hydro::EntitySerializer.user(@pull.user),
        repository: Hydro::EntitySerializer.repository(@pull.repository),
        repository_owner: Hydro::EntitySerializer.user(@pull.repository.owner),
        reviewable_state_was: "ready"
      }

      assert_hydro_published(msg, schema: "github.v1.PullRequestInProgress")
    end
  end

  context ".labeled" do
    test "finds issues with many labels by a single passed label name" do
      label = create(:label, name: "label", repository: @source)
      other_label = create(:label, name: "other_label", repository: @source)

      @issue.add_labels [label, other_label]

      assert_equal [@pull], PullRequest.labeled(["label"])
    end

    test "finds issues by label name irrespective of its casing" do
      label = create(:label, name: "label", repository: @source)
      other_label = create(:label, name: "other_label", repository: @source)

      @issue.add_labels [label, other_label]

      assert_equal [@pull], PullRequest.labeled(["LABEL"])
    end

    test "finds issues with all passed passed labels" do
      label = create(:label, name: "label", repository: @source)
      other_label = create(:label, name: "other_label", repository: @source)
      unrelated_label = create(:label, name: "unrelated_label", repository: @source)
      @issue.add_labels [label, other_label]

      assert_equal [@pull], PullRequest.labeled(%w[label unrelated_label]).to_a
      assert_equal [@pull], PullRequest.labeled(%w[label other_label]).to_a.uniq
    end
  end

  context "#async_diff_relative_position_for_thread_id_with_viewer" do
    test "returns nil when a passed thread id does not belong to the pull request" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "review body!",
      )

      review_thread = create(:pull_request_review_thread,
        pull_request_review: review,
        pull_request: @pull,
        path: "file10",
        blob_position: 5,
        position: 1,
        original_position: 1,
        commit_id: @pull.head_sha,
        original_commit_id: @pull.head_sha,
      )

      comment = create(:pull_request_review_comment,
        user: @owner,
        body: "moose bites can be deadly.",
        pull_request: @pull,
        pull_request_review: review,
        pull_request_review_thread: review_thread,
        commit_id: @pull.head_sha,
        path: "file10",
        original_position: 1,
      )
      comment.submit!

      result = @pull.async_diff_relative_position_for_thread_id_with_viewer(thread_id: (review_thread.id + 1), viewer: @owner).sync
      assert_nil result
    end

    test "returns nil when a passed viewer does not have access to a thread" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "review body!",
      )

      review_thread = create(:pull_request_review_thread,
        pull_request_review: review,
        pull_request: @pull,
        path: "file10",
        blob_position: 5,
        position: 1,
        original_position: 1,
        commit_id: @pull.head_sha,
        original_commit_id: @pull.head_sha,
      )

      comment = create(:pull_request_review_comment,
        user: @owner,
        body: "moose bites can be deadly.",
        pull_request: @pull,
        pull_request_review: review,
        pull_request_review_thread: review_thread,
        commit_id: @pull.head_sha,
        path: "file10",
        original_position: 1,
      )

      result = @pull.async_diff_relative_position_for_thread_id_with_viewer(thread_id: review_thread.id, viewer: @forker).sync
      assert_nil result
    end

    test "returns a position when a passed viewer has access to the thread and the thread id is valid" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "review body!",
      )

      review_thread = create(:pull_request_review_thread,
        pull_request_review: review,
        pull_request: @pull,
        path: "file10",
        blob_position: 5,
        position: 1,
        original_position: 1,
        commit_id: @pull.head_sha,
        original_commit_id: @pull.head_sha,
      )

      comment = create(:pull_request_review_comment,
        user: @owner,
        body: "moose bites can be deadly.",
        pull_request: @pull,
        pull_request_review: review,
        pull_request_review_thread: review_thread,
        commit_id: @pull.head_sha,
        path: "file10",
        original_position: 1,
      )
      comment.submit!

      result = @pull.async_diff_relative_position_for_thread_id_with_viewer(thread_id: review_thread.id, viewer: @owner).sync
      assert_equal 1, result
    end
  end

  context "#async_pull_comparison" do
    test "only generates as single promise per combination of passed arguments" do
      @pull.async_pull_comparison

      assert_equal 1, @pull.instance_variable_get(:@async_pull_comparison).keys.count

      # repeating the comparison call to assert that no new promises are hashed
      # or otherwise saved on the pull request

      @pull.async_pull_comparison

      assert_equal 1, @pull.instance_variable_get(:@async_pull_comparison).keys.count
    end
  end

  context "adding comments" do
    test "PR and connected project item are touched when an IssueComment is added" do
      memex_project = create(:memex_project, owner: @owner)
      pr_item = create(:memex_project_item, memex_project: memex_project, content: @pull)

      pull_timestamp = @pull.updated_at
      item_timestamp = pr_item.updated_at

      Timecop.freeze(3.hours.from_now) do
        perform_enqueued_jobs only: [IssueOrchestration.job_class, IssueCommentOrchestration.job_class] do
          # @issue is connected to @pull
          create :issue_comment, issue: @issue, body: "hello!", user: @owner
        end

        TouchMemexProjectItemsJob.perform_now(@pull)

        pr_item.reload
        @pull.reload

        refute_equal @pull.updated_at, pull_timestamp
        refute_equal pr_item.updated_at, item_timestamp
      end
    end

    test "PR and connected project item are touched when an pr review comment is added" do
      review = create(:pull_request_review, pull_request: @pull, user: @ryan)
      memex_project = create(:memex_project, owner: @owner)
      pr_item = create(:memex_project_item, memex_project: memex_project, content: @pull)

      pull_timestamp = @pull.updated_at
      item_timestamp = pr_item.updated_at

      Timecop.freeze(3.hours.from_now) do
        create(:pull_request_review_comment,
          pull_request: @pull,
          user: @owner,
          body: "another comment",
          pull_request_review: review,
        )
        review.comment!

        TouchMemexProjectItemsJob.perform_now(@pull)

        pr_item.reload
        @pull.reload

        refute_equal @pull.updated_at, pull_timestamp
        refute_equal pr_item.updated_at, item_timestamp
      end
    end
  end

  context "#store_conflicts" do
    test "with no existing conflict" do
      @pull.store_conflicts({
        base: "1" * 40,
        head: "2" * 40,
        conflicted_files: {
          "example.txt" => true,
        }
      })

      conflict = @pull.conflict.reload
      assert_equal("1" * 40, conflict.base_sha)
      assert_equal("2" * 40, conflict.head_sha)
      assert_equal({ "conflicted_files" => { "example.txt" => true } }.to_json, conflict.info)
    end

    test "with an existing conflict" do
      @pull.create_conflict!(
        base_sha: "0" * 40,
        head_sha: "0" * 40,
        info: "{}",
      )
      @pull.store_conflicts({
        base: "1" * 40,
        head: "2" * 40,
        conflicted_files: {
          "example.txt" => true,
        }
      })

      conflict = @pull.conflict.reload
      assert_equal("1" * 40, conflict.base_sha)
      assert_equal("2" * 40, conflict.head_sha)
      assert_equal({ "conflicted_files" => { "example.txt" => true } }.to_json, conflict.info)
    end

    test "with an existing conflict created after checking for existence" do
      # Make sure @pull has loaded `conflict`
      assert_nil @pull.conflict

      # Create a conflict without updating @pull's state
      PullRequestConflict.create!(
        pull_request: @pull,
        base_sha: "0" * 40,
        head_sha: "0" * 40,
        info: "{}",
      )

      @pull.store_conflicts({
        base: "1" * 40,
        head: "2" * 40,
        conflicted_files: {
          "example.txt" => true,
        }
      })

      conflict = @pull.conflict.reload
      assert_equal("1" * 40, conflict.base_sha)
      assert_equal("2" * 40, conflict.head_sha)
      assert_equal({ "conflicted_files" => { "example.txt" => true } }.to_json, conflict.info)
    end
  end

  test "PR base and head do not include shortcode in multi-tenant environment" do
    on_multi_tenant_enterprise
    GitHub.flipper.enable(:tenant_namespacing)
    user = create(:emu)
    business = user.enterprise_managed_business
    org = create(:organization, business: business, admin: user, name: "testorg")
    repo = create(:repository, owner: org, admin: user, from_example: :pull_request_fork)


    pull = create(:pull_request,
      repository: repo,
      head_repository: repo,
      base_repository: repo,
      base_ref:  "master",
      head_ref:  "topic",
      user:  user,
      title:  "a cross-repo PR",
      body:  "nothing special",
    )

    assert_equal "testorg:master", pull.base
    assert_equal "testorg:topic", pull.head
  end

  context "#stale" do
    test "returns true when pull request is open and pull's head sha does not match the current_head_oid" do
      @pull.update(head_sha: "12345678")

      assert @pull.open?
      assert @pull.stale?
    end

    test "returns false when pull request is closed" do
      @pull.close

      assert @pull.closed?
      refute @pull.stale?
    end

    test "returns false when pull request is open and pull's head sha does match current_head_oid" do
      assert @pull.open?
      refute @pull.stale?
    end

    test "returns false when pull has no current_head_oid because fork was deleted" do
      assert @pull.open?
      @pull.stubs(:current_head_oid).returns(nil)
      refute @pull.stale?
    end
  end

  context "#latest_unsynced_push_to_head_ref" do
    test "returns the latest push for the head ref after the current_head_oid when it exists" do
      push = create(:push, repository: @pull.head_repository, ref: "refs/heads/#{@pull.head_ref}", after: @pull.current_head_oid)

      assert_equal @pull.latest_unsynced_push_to_head_ref, push
    end

    test "does not return the latest push for the head ref after the current_head_oid when it does not exist" do
      push = create(:push, repository: @pull.repository, ref: "refs/heads/#{@pull.head_ref}", after: @pull.current_head_oid)

      assert_nil @pull.latest_unsynced_push_to_head_ref
    end

    test "returns nil if the latest push does not exist" do
      push = create(:push, repository: @pull.head_repository, ref: "refs/heads/#{@pull.head_ref}")

      assert_nil @pull.latest_unsynced_push_to_head_ref
    end
  end

  context "Azure Boards links" do
    test "Returns links if feature flag is enabled" do
      GitHub.flipper[:azure_boards_links_in_pr_development_section].enable(@owner)
      text = "Some text with [AB#1234](https://buildcanary.visualstudio.com/df601317-1b56-4cdc-84ff-685abe87c420/_workitems/edit/1234) link to be extracted"

      pull = PullRequest.create_for!(@source, title: "hello", user: @owner, base: "master", head: "master-forward-2", body: text)

      assert_equal 1, pull.links.size
      assert_equal pull.links.first.text, "AB#1234"
      assert_equal pull.links.first.url, "https://buildcanary.visualstudio.com/df601317-1b56-4cdc-84ff-685abe87c420/_workitems/edit/1234"
    end

    test "Returns no links if feature flag is disabled" do
      GitHub.flipper[:azure_boards_links_in_pr_development_section].disable(@owner)
      text = "Some text with [AB#1234](https://buildcanary.visualstudio.com/df601317-1b56-4cdc-84ff-685abe87c420/_workitems/edit/1234) link to be extracted"

      pull = PullRequest.create_for!(@source, title: "hello", user: @owner, base: "master", head: "master-forward-2", body: text)

      assert_equal 0, pull.links.size
    end

    test "Removes duplicate links" do
      GitHub.flipper[:azure_boards_links_in_pr_development_section].enable(@owner)
      text = "Some text with two identical [AB#1234](https://buildcanary.visualstudio.com/df601317-1b56-4cdc-84ff-685abe87c420/_workitems/edit/1234) "\
        "[AB#1234](https://buildcanary.visualstudio.com/df601317-1b56-4cdc-84ff-685abe87c420/_workitems/edit/1234) links to be extracted "\
        "and one more link [AB#42](https://buildcanary.visualstudio.com/df601317-1b56-4cdc-84ff-685abe87c420/_workitems/edit/42)"

      pull = PullRequest.create_for!(@source, title: "hello", user: @owner, base: "master", head: "master-forward-2", body: text)

      assert_equal 2, pull.links.size
      assert_equal pull.links[0].text, "AB#1234"
      assert_equal pull.links[0].url, "https://buildcanary.visualstudio.com/df601317-1b56-4cdc-84ff-685abe87c420/_workitems/edit/1234"
      assert_equal pull.links[1].text, "AB#42"
      assert_equal pull.links[1].url, "https://buildcanary.visualstudio.com/df601317-1b56-4cdc-84ff-685abe87c420/_workitems/edit/42"
    end
  end

  context "#reopened" do
    test "emits synchronize event" do
      GitHub.flipper[:reopen_synchronize_event_head_repository].enable
      @pull.close(@pull.user)
      perform_enqueued_pr_jobs do
        commit = @pull.head_repository.refs.find(@pull.head_ref).append_commit({ message: "a", committer: @owner }, @owner)
        @pull.open(@pull.user)
        @pull.reload
        assert_equal @pull.head_sha, commit.oid
      end

      assert_hydro_messages(count: 1, schema: "github.v1.PullRequestSynchronize")
      event = decoded_hydro_messages.find { |m| m.schema == "github.v1.PullRequestSynchronize" }
      assert_equal event.data.message[:repository][:id], @pull.head_repository.id
      assert_equal event.data.message[:base_repository][:id], @pull.base_repository.id
    end
  end
end

# These tests call share_spokesdb, which disables transactional tests. Calling this slows tests down drastically,
# so isolate the tests which need it to their own class.
class PullRequestTestSharedSpokes < PullRequestTestBase
  Spokesd.share_spokesdb(self)

  # https://github.com/github/github/issues/36850
  test "reverting a cross-repo pull where the un-networked revert repository does not have the relevant objects" do
    source = create(:repository, from_example: :simple)

    fork1 = fast_fork_repo(source, example: :simple)
    fork2 = fast_fork_repo(source, example: :simple)

    [source, fork1, fork2].each(&:disable_shared_storage)

    base_ref = source.heads.find("master")
    head_ref = fork1.heads.create("topic", base_ref.target_oid, fork1.owner)

    metadata = { message: "blah", committer: fork1.owner }

    head_ref.append_commit(metadata, fork1.owner) do |files|
      files.add("blah.txt", "blahblahblah")
    end

    pull = perform_enqueued_pr_jobs do
      PullRequest.create_for!(source,
        base: "#{source.owner}:master",
        head: "#{fork1.owner}:topic",
        user: fork1.owner,
        title: "blah")
    end

    perform_enqueued_pr_jobs do
      assert pull.merge.first
    end

    source.reload
    base_commit = source.heads.find("master").target

    assert source.blob(base_commit.oid, "blah.txt")

    # without shared storage, fork2 should be missing the relevant
    # objects that were merged from the pull and are required to perform a revert.
    assert_raises(GitRPC::ObjectMissing) do
      fork2.commits.find(base_commit.oid)
    end

    revert_branch, error = perform_enqueued_pr_jobs do
      pull.revert(fork2.owner)
    end

    assert_nil error
    assert_equal fork2, revert_branch.repository
    assert_nil fork2.blob(revert_branch.target_oid, "blah.txt")
  end
end
