# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectWorkflowPrReviewTriggersTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @owner = create(:user, login: "ari")
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_fork)
    @user = create(:user)
    @repo.add_member(@user)

    @reviewers = 1.upto(3).map do |_index|
      reviewer = create(:user)
      @repo.add_member(reviewer)
      reviewer
    end

    issue = create(:issue, user: @forker, repository: @repo)
    @pr = PullRequest.create_for(@repo, {
      base:  "master",
      head:  "#{@fork.user}:topic",
      user:  issue.user,
      issue: issue,
    })

    @project = create(:project, owner: @repo)
    @column = create(:project_column, project: @project)
    @issue = create(:issue, repository: @repo)

    @pr_card = create(:project_card, column: @column, content: @pr.issue)

    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient
  end

  setup do
    example_repo :pull_request_source, @repo
    example_repo :pull_request_fork,   @fork
    GitHub.context.push(actor_id: @owner.id)
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    METADATA_CLIENT.any_instance.stubs(:get_packages_by_repo).returns(OpenStruct.new(packages: []))
  end

  teardown do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  def create_review(review_type, msg: "good job", user: @owner)
    review = @pr.reviews.create!(user: user, head_sha: @pr.head_sha, body: msg)
    case review_type
    when :approved
      review.approve!
    when :changes_requested
      review.request_changes!
    end
    review
  end

  def create_column_with_workflow(review_type)
    column = create(:project_column, project: @project)
    trigger_type = case review_type
    when :approved
      ProjectWorkflow::PR_APPROVED_TRIGGER
    when :pending_approval
      ProjectWorkflow::PR_PENDING_APPROVAL_TRIGGER
    end
    @project.project_workflows.set_workflow(creator: @owner, trigger_type: trigger_type, column: column)
    column
  end

  test "can create a pr approved workflow using helper" do
    workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_APPROVED_TRIGGER, column: @column)
    assert_predicate workflow, :valid?
    assert_equal 1, workflow.actions.size
  end

  test "can create a pr changes requested workflow using helper" do
    workflow = @project.project_workflows.set_workflow(creator: @owner, trigger_type: ProjectWorkflow::PR_PENDING_APPROVAL_TRIGGER, column: @column)
    assert_predicate workflow, :valid?
    assert_equal 1, workflow.actions.size
  end

  context "pr_approved trigger" do
    test "review approval on a PR moves its card into a column" do
      approved_column = create_column_with_workflow(:approved)
      assert_equal @column.id, @pr_card.column_id

      create_review(:approved)

      @pr_card.reload
      assert_equal approved_column.id, @pr_card.column_id
    end

    test "respects the configured minimum number of approving reviewers" do
      protected_branch = create(:protected_branch, repository: @repo,
        name: "master",
        pull_request_reviews_enforcement_level: :everyone,
        required_approving_review_count: 3
      )
      approved_column = create_column_with_workflow(:approved)

      assert_equal @column.id, @pr_card.column_id

      create_review(:approved, user: @reviewers.first)
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id

      create_review(:approved, user: @reviewers.second)
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id

      create_review(:approved, user: @reviewers.third)
      @pr_card.reload

      assert_equal approved_column.id, @pr_card.column_id
    end

    test "respects required code owner reviews" do
      codeowner_path = @pr.diffs.deltas.first.new_file.path
      codeowner = @reviewers.first
      non_codeowner = @reviewers.second

      commit = { message: "Add CODEOWNERS file", committer: @owner }
      @pr.repository.refs.find(@pr.base_ref_name).append_commit(commit, @owner) do |files|
        files.add("CODEOWNERS", "#{codeowner_path} @#{codeowner.login}")
      end

      protected_branch = create(:protected_branch, repository: @repo,
        name: "master",
        pull_request_reviews_enforcement_level: :everyone,
        require_code_owner_review: true
      )
      approved_column = create_column_with_workflow(:approved)

      assert_equal @column.id, @pr_card.column_id

      create_review(:approved, user: non_codeowner)
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id

      create_review(:approved, user: codeowner)
      @pr_card.reload

      assert_equal approved_column.id, @pr_card.column_id
    end

    test "does not trigger if changes requested from another user" do
      create_review(:changes_requested, user: @user, msg: "a few things")
      create_column_with_workflow(:approved)
      assert_equal @column.id, @pr_card.column_id

      create_review(:approved)

      @pr_card.reload
      assert_equal @column.id, @pr_card.column_id
    end

    test "does not trigger if project is closed" do
      @project.close
      create_column_with_workflow(:approved)
      assert_equal @column.id, @pr_card.column_id

      create_review(:approved)

      @pr_card.reload
      assert_equal @column.id, @pr_card.column_id
    end

    test "does not trigger if the card is archived" do
      create_column_with_workflow(:approved)
      @pr_card.archive

      assert_equal @column.id, @pr_card.column_id

      create_review(:approved)
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id
    end

    test "does not trigger if reviewer is spammy and doesn't belong to repo" do
      spammer = create(:user, login: "spammer", spammy: true)
      create_column_with_workflow(:approved)
      assert_equal @column.id, @pr_card.column_id

      create_review(:approved, user: spammer)

      @pr_card.reload
      assert_equal @column.id, @pr_card.column_id
    end unless GitHub.enterprise?
  end

  context "pr_pending_approval trigger" do
    test "review changes requested on a PR moves its card into a column" do
      changes_column = create_column_with_workflow(:pending_approval)
      assert_equal @column.id, @pr_card.column_id

      create_review(:changes_requested)

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id
    end

    test "if PR was approved, changes requested takes precedence" do
      create_review(:approved, user: @user)
      changes_column = create_column_with_workflow(:pending_approval)
      assert_equal @column.id, @pr_card.column_id

      create_review(:changes_requested)

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id
    end

    test "pushes triggering required codeowner reviews moves its card into a column" do
      with_hydro_pr_jobs do
        codeowner = @reviewers.first
        non_codeowner = @reviewers.second

        codeowner_commit = { message: "Add CODEOWNERS file", committer: @owner }
        @pr.repository.refs.find(@pr.base_ref_name).append_commit(codeowner_commit, @owner) do |files|
          files.add("CODEOWNERS", "protected.txt @#{codeowner.login}")
        end

        @repo.protected_branches.create!(
          name: "master",
          creator: @owner,
          pull_request_reviews_enforcement_level: :everyone,
          require_code_owner_review: true,
        )

        approved_column = create_column_with_workflow(:approved)
        changes_column = create_column_with_workflow(:pending_approval)

        assert_equal @column.id, @pr_card.column_id

        create_review(:approved, user: non_codeowner)
        @pr_card.reload
        assert_equal approved_column.id, @pr_card.column_id

        commit = { message: "Editing codeowner protected file", committer: @owner }
        @pr.head_repository.refs.find(@pr.head_ref_name).append_commit(commit, @owner) do |files|
          files.add("protected.txt", "touched!")
        end

        @pr_card.reload
        assert_equal changes_column.id, @pr_card.column_id

        create_review(:approved, user: codeowner)
        @pr_card.reload
        assert_equal approved_column.id, @pr_card.column_id
      end
    end

    test "does not trigger if project is closed" do
      @project.close
      create_column_with_workflow(:pending_approval)
      assert_equal @column.id, @pr_card.column_id

      create_review(:changes_requested)

      @pr_card.reload
      assert_equal @column.id, @pr_card.column_id
    end

    test "does not trigger if the card is archived" do
      create_column_with_workflow(:pending_approval)
      @pr_card.archive

      assert_equal @column.id, @pr_card.column_id

      create_review(:changes_requested)
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id
    end

    test "does not trigger if reviewer is spammy and doesn't belong to repo" do
      spammer = create(:user, login: "spammer", spammy: true)
      create_column_with_workflow(:pending_approval)
      assert_equal @column.id, @pr_card.column_id

      create_review(:changes_requested, user: spammer)

      @pr_card.reload
      assert_equal @column.id, @pr_card.column_id
    end unless GitHub.enterprise?
  end

  context "review_dismissed trigger" do
    test "dismissing approved review moves to changes requested column" do
      approved_review = create_review(:approved)
      changes_column = create_column_with_workflow(:pending_approval)
      create_column_with_workflow(:approved)
      assert_equal @column.id, @pr_card.column_id

      approved_review.dismiss!(@forker, message: "dismiss an approval")

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id
    end

    test "dismissing approved review does nothing if no changes requested column" do
      approved_review = create_review(:approved)
      create_column_with_workflow(:approved)
      assert_equal @column.id, @pr_card.column_id

      approved_review.dismiss!(@forker, message: "dismiss an approval")

      @pr_card.reload
      assert_equal @column.id, @pr_card.column_id
    end

    test "dismissing changes requested review moves to approved column if approved" do
      approved_review = create_review(:approved)
      changes_review = create_review(:changes_requested, user: @user)

      changes_column = create_column_with_workflow(:pending_approval)
      approved_column = create_column_with_workflow(:approved)

      assert_equal @column.id, @pr_card.column_id

      changes_review.dismiss!(@forker, message: "dismiss an approval")

      @pr_card.reload
      assert_equal approved_column.id, @pr_card.column_id

      approved_review.dismiss!(@forker, message: "dismiss an approval")
      @pr_card.reload

      assert_equal changes_column.id, @pr_card.column_id
    end

    test "respects the configured minimum number of approving reviewers" do
      protected_branch = create(:protected_branch, repository: @repo,
        name: "master",
        pull_request_reviews_enforcement_level: :everyone,
        required_approving_review_count: 3
      )
      create_review(:approved, user: @reviewers.first)
      create_review(:approved, user: @reviewers.second)
      changes_review = create_review(:changes_requested, user: @user)
      changes_column = create_column_with_workflow(:pending_approval)
      approved_column = create_column_with_workflow(:approved)

      assert_equal @column.id, @pr_card.column_id

      changes_review.dismiss!(@forker, message: "dismiss an approval")
      @pr_card.reload

      assert_equal changes_column.id, @pr_card.column_id

      final_review = create_review(:approved, user: @reviewers.third)
      @pr_card.reload

      assert_equal approved_column.id, @pr_card.column_id

      final_review.dismiss!(@forker, message: "dismiss an approval")
      @pr_card.reload

      assert_equal changes_column.id, @pr_card.column_id
    end

    test "respects required code owner reviews" do
      codeowner_path = @pr.diffs.deltas.first.new_file.path
      codeowner = @reviewers.first
      non_codeowner = @reviewers.second

      commit = { message: "Add CODEOWNERS file", committer: @owner }
      @pr.repository.refs.find(@pr.base_ref_name).append_commit(commit, @owner) do |files|
        files.add("CODEOWNERS", "#{codeowner_path} @#{codeowner.login}")
      end

      protected_branch = create(:protected_branch, repository: @repo,
        name: "master",
        pull_request_reviews_enforcement_level: :everyone,
        require_code_owner_review: true
      )
      approved_column = create_column_with_workflow(:approved)
      changes_column = create_column_with_workflow(:pending_approval)

      assert_equal @column.id, @pr_card.column_id

      create_review(:approved, user: non_codeowner)
      owner_review = create_review(:approved, user: codeowner)
      @pr_card.reload

      assert_equal approved_column.id, @pr_card.column_id

      owner_review.dismiss!(@forker, message: "dismiss a change")
      @pr_card.reload

      assert_equal changes_column.id, @pr_card.column_id
    end

    test "dismissing changes requested review does nothing if pr not approved" do
      assert_equal @column.id, @pr_card.column_id

      changes_column = create_column_with_workflow(:pending_approval)
      create_column_with_workflow(:approved)

      changes_review = create_review(:changes_requested)

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id

      changes_review.dismiss!(@forker, message: "dismiss a change")

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id
    end

    test "dismissing reviews moves to correct sequence of columns" do
      changes_column = create_column_with_workflow(:pending_approval)
      approved_column = create_column_with_workflow(:approved)

      assert_equal @column.id, @pr_card.column_id

      create_review(:approved)

      @pr_card.reload
      assert_equal approved_column.id, @pr_card.column_id

      changes_review = create_review(:changes_requested)

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id

      create_review(:approved, user: @user)

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id

      changes_review.dismiss!(@forker, message: "dismiss an approval")
      @pr_card.reload

      assert_equal approved_column.id, @pr_card.column_id
    end

    test "dismissing changes requested review does not move to approved if another change review exists from a different user" do
      another_user = create(:user)
      @repo.add_member(another_user)

      create_review(:changes_requested)

      changes_column = create_column_with_workflow(:pending_approval)
      create_column_with_workflow(:approved)

      assert_equal @column.id, @pr_card.column_id

      changes_review = create_review(:changes_requested, user: another_user)

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id

      create_review(:approved, user: @user)

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id

      changes_review.dismiss!(@forker, message: "dismiss an approval")
      @pr_card.reload

      assert_equal changes_column.id, @pr_card.column_id
    end

    test "dismissing latest review moves to approved even if an older changes requested review exists for the same user" do
      create_review(:changes_requested)
      create_review(:approved)
      changes_column = create_column_with_workflow(:pending_approval)
      approved_column = create_column_with_workflow(:approved)

      assert_equal @column.id, @pr_card.column_id

      changes_review = create_review(:changes_requested, user: @user)

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id

      changes_review.dismiss!(@forker, message: "dismiss an approval")
      @pr_card.reload

      assert_equal approved_column.id, @pr_card.column_id
    end

    test "does not trigger if the card is archived" do
      approved_review = create_review(:approved)
      changes_column = create_column_with_workflow(:pending_approval)
      create_column_with_workflow(:approved)
      @pr_card.archive

      assert_equal @column.id, @pr_card.column_id

      approved_review.dismiss!(@forker, message: "dismiss an approval")
      @pr_card.reload

      assert_equal @column.id, @pr_card.column_id
    end

    test "ignores previous reviews from spammy users when a review is dismissed" do
      spammer = create(:user, login: "spammer", spammy: true)

      create_review(:approved)
      create_review(:changes_requested, user: spammer)

      changes_column = create_column_with_workflow(:pending_approval)
      approved_column = create_column_with_workflow(:approved)

      assert_equal @column.id, @pr_card.column_id

      changes_review = create_review(:changes_requested, user: @user)

      @pr_card.reload
      assert_equal changes_column.id, @pr_card.column_id

      changes_review.dismiss!(@forker, message: "dismiss an approval")
      @pr_card.reload

      assert_equal approved_column.id, @pr_card.column_id
    end unless GitHub.enterprise?
  end
end
