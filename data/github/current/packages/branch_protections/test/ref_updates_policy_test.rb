# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class RefUpdatesPolicyTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include SecretScanning::Features::FeatureFlagHelper
  include PushTestHelper

  fixtures do
    make_trusted_oauth_apps_owner
    create(:merge_queue_integration)

    @user = create(:user)
    @org = create(:business_plus_organization)
    @org.add_member @user, action: :admin
    @repo = create(:repository, owner: @org)

    @repo_with_merge_queue = create(:repository, :has_merge_queue, owner: @user)
  end

  setup do
    @repo.refs.map do |ref|
      ref.delete(@user)
    end

    Spokesd.enable_spokesd
  end

  test "updating refs which change workflow files as app without scope" do
    # Just test that WorfklowUpdatesPolicy is being called correctly
    app = create :integration, default_permissions: { "checks" => :write }, owner: @user
    installation = make_integration_installation(integration: @app, repository: @repo, permissions: { "contents" => :write })

    oid_add_workflow = create_commit(nil, "add workflow", {
      ".github/workflows/a.yml" => "# foo\n",
    })
    oid_delete_workflow = create_commit(oid_add_workflow, "delete workflow", {
      ".github/workflows/a.yml" => nil,
    })
    ref_updates = [
      create_tag_update(
        @repo,
        name: "commit-add",
        before_oid: GitHub::NULL_OID,
        after_oid: oid_add_workflow,
      ),
      create_tag_update(
        @repo,
        name: "commit-delete",
        before_oid: oid_add_workflow,
        after_oid: oid_delete_workflow,
      ),
    ]

    # can't write as an app
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, installation.bot)

    refute_predicate decisions[0], :allowed?
    assert_predicate decisions[1], :allowed?

    # can write as a user
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_predicate decisions[1], :allowed?
    assert_predicate decisions[1], :allowed?
  end

  test "allows updating normal refs" do
    ref_updates = [
      create_branch_update(@repo, name: "master"),
      create_branch_update(@repo, name: "cr-line-endings"),
    ]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_predicate decisions[0], :allowed?
    assert_predicate decisions[1], :allowed?
  end

  test "disallows updating a branch's refs when branch is being renamed" do
    example_repo :simple, @repo
    rename = create(:repository_branch_rename, repository: @repo, old_name: "master")
    ref_updates = [
      create_branch_update(@repo, name: rename.old_name),
      create_branch_update(@repo, name: "cr-line-endings"),
      create_tag_update(@repo, name: "taggo")
    ]

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    refute_predicate decisions[0], :allowed?,
      "should not have allowed update to branch being renamed"
    assert_predicate decisions[1], :allowed?,
      "should have allowed update to branch not being renamed"
    assert_predicate decisions[1], :allowed?,
      "should have allowed update to non-branch"
  end

  test "allows slumlord to update SVN refs" do
    ref_updates = [
      create_ref_update(@repo, name: "refs/__gh__/svn/master"),
      create_ref_update(@repo, name: "refs/__gh__/svn/cr-line-endings"),
    ]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, :slumlord)

    assert_predicate decisions[0], :allowed?
    assert_predicate decisions[1], :allowed?
  end

  test "does not allow slumlord to update non-SVN refs" do
    ref_updates = [
      create_ref_update(@repo, name: "refs/__gh__/svn/master"),
      create_branch_update(@repo, name: "master"),
      create_branch_update(@repo, name: "cr-line-endings"),
    ]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, :slumlord)

    assert_predicate decisions[0], :allowed?

    refute_predicate decisions[1], :allowed?
    assert_equal "non-SVN ref update denied", decisions[1].short_message
    assert_nil decisions[1].long_message

    refute_predicate decisions[2], :allowed?
    assert_equal "non-SVN ref update denied", decisions[2].short_message
    assert_nil decisions[2].long_message
  end

  test "does not allow updating hidden refs" do
    ref_updates = [
      create_ref_update(@repo, name: "refs/__gh__/svn/master"),
      create_ref_update(@repo, name: "refs/__gh__"),
      create_ref_update(@repo, name: "refs/__gh__/foo"),
    ]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    refute_predicate decisions[0], :allowed?
    assert_equal "deny updating a hidden ref", decisions[0].short_message
    assert_nil decisions[0].long_message

    refute_predicate decisions[1], :allowed?
    assert_equal "deny updating a hidden ref", decisions[1].short_message
    assert_nil decisions[1].long_message

    refute_predicate decisions[2], :allowed?
    assert_equal "deny updating a hidden ref", decisions[2].short_message
    assert_nil decisions[2].long_message
  end

  if GitHub.merge_queues_enabled?
    test "does not allow updating merge queue refs when merge queue is enabled" do
      ref_updates = [
        create_ref_update(
          @repo_with_merge_queue,
          name: "refs/gh/queue/1"
        ),
      ]

      decisions = RefUpdatesPolicy.check(@repo_with_merge_queue, ref_updates, @user)

      refute_predicate decisions[0], :allowed?
      assert_equal "refusing to update a read-only ref", decisions[0].short_message
      assert_nil decisions[0].long_message
    end

    test "allows updating merge queue refs when the repo does not have access to merge queue" do
      Repository.any_instance.stubs(:merge_queue_enabled?).returns(false)

      ref_updates = [
        create_ref_update(
          @repo_with_merge_queue,
          name: "refs/gh/queue/1"
        ),
      ]

      decisions = RefUpdatesPolicy.check(@repo_with_merge_queue, ref_updates, @user)

      assert_predicate decisions[0], :allowed?
    end
  end

  test "does not allow updating PR refs" do
    ref_updates = [
      create_ref_update(@repo, name: "refs/pull"),
      create_ref_update(@repo, name: "refs/pull/1"),
    ]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    refute_predicate decisions[0], :allowed?
    assert_equal "deny updating a hidden ref", decisions[0].short_message
    assert_nil decisions[0].long_message

    refute_predicate decisions[1], :allowed?
    assert_equal "deny updating a hidden ref", decisions[1].short_message
    assert_nil decisions[1].long_message
  end

  test "checks protected branch policy" do
    example_repo :simple, @repo
    events = subscribe "protected_branch.rejected_ref_update"
    @repo.protected_branches.create!(name: "cr-line-endings", creator: @user)

    ref_updates = [create_ref_update(
      @repo,
      name: "refs/heads/cr-line-endings",
      before_oid: @repo.heads["cr-line-endings"].target_oid,
      after_oid: GitHub::NULL_OID,
    )]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    refute_predicate decisions[0], :allowed?
    assert_equal "protected branch hook declined", decisions[0].short_message
    assert_equal "error: GH006: Protected branch update failed for refs/heads/cr-line-endings.\n\n- Cannot delete this branch\n", decisions[0].long_message
    assert events.pop, "expected event"
  end

  test "don't include overridable policies in the rejection message" do
    example_repo :simple, @repo

    # create a branch protection that
    # 1. Requires PRs but is overridable by the user
    # 2. Requires a status check that is not overriable
    protected_branch = @repo.protected_branches.create!(name: "cr-line-endings", creator: @user)
    protected_branch.pull_request_reviews_enforcement_level = :everyone
    protected_branch.replace_branch_actor_allowances(:pull_request, user_ids: [@user.id], team_ids: [], integration_ids: [])
    protected_branch.required_status_checks_enforcement_level = :everyone
    protected_branch.replace_status_contexts(["some status"])
    protected_branch.save!

    new_commit = create_commit(@repo.heads["cr-line-endings"].target_oid, "some change", {
      "a.txt" => "testing",
    })

    ref_updates = [create_branch_update(
      @repo,
      name: "cr-line-endings",
      before_oid: @repo.heads["cr-line-endings"].target_oid,
      after_oid: new_commit,
    )]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    refute_predicate decisions[0], :allowed?
    assert_equal "protected branch hook declined", decisions[0].short_message
    assert_equal "error: GH006: Protected branch update failed for refs/heads/cr-line-endings.\n\n- Required status check \"some status\" is expected.\n", decisions[0].long_message
  end

  test "can push ref updates using a deploy key as if the actor was a repo admin" do
    example_repo :simple, @repo
    protected_branch = @repo.protected_branches.create!(name: "cr-line-endings", creator: @user)
    protected_branch.pull_request_reviews_enforcement_level = :non_admins
    protected_branch.replace_branch_actor_allowances(:pull_request, user_ids: [@user.id], team_ids: [], integration_ids: [])
    protected_branch.required_status_checks_enforcement_level = :non_admins
    protected_branch.replace_status_contexts(["some status"])
    protected_branch.save!

    read_deploy_key = create :public_key, repository: @repo, read_only: true
    write_deploy_key = create :public_key, repository: @repo, read_only: false

    new_commit = create_commit(@repo.heads["cr-line-endings"].target_oid, "some change", {
      "a.txt" => "testing",
    })

    ref_updates = [create_branch_update(
      @repo,
      name: "cr-line-endings",
      before_oid: @repo.heads["cr-line-endings"].target_oid,
      after_oid: new_commit,
    )]

    # Using a read_only key should not be able to bypass rules
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, T.unsafe(read_deploy_key))
    refute_predicate decisions[0], :allowed?

    # Using a write key should act as an admin, so repo admin bypass should work
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, T.unsafe(write_deploy_key))
    assert_predicate decisions[0], :allowed?
  end

  test "can allow some updates and deny others in a single call" do
    example_repo :simple, @repo
    @repo.protected_branches.create!(name: "master", creator: @user)

    ref_updates = [
      create_branch_update(@repo, name: "cr-line-endings"),
      create_branch_update(@repo, name: "master", after_oid: GitHub::NULL_OID),
      create_ref_update(@repo, name: "refs/pull/1"),
    ]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_predicate decisions[0], :allowed?
    refute_predicate decisions[1], :allowed?
    refute_predicate decisions[2], :allowed?
  end

  test "handles git_error case" do
    example_repo :simple, @repo
    RuleEngine::Rules::UpdateRule.any_instance.stubs(:evaluate).raises(GitRPC::ObjectMissing)

    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, :update, repository_ruleset: ruleset)

    ref_updates = [create_ref_update(
      @repo,
      name: "refs/heads/cr-line-endings",
      before_oid: @repo.heads["cr-line-endings"].target_oid
    )]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    refute_predicate decisions[0], :allowed?
    assert_equal "protected branch hook declined", decisions[0].short_message
  end

  test "does not allow deleting the default branch" do
    ref_updates = [
      create_branch_update(@repo, name: "master", after_oid: GitHub::NULL_OID),
    ]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_equal "master", @repo.default_branch
    refute_predicate decisions[0], :allowed?
    assert_equal "refusing to delete the current branch: refs/heads/master", decisions[0].short_message
  end

  test "bots cannot delete protected branches" do
    refname = "refs/heads/#{@repo.default_branch}"

    oid_add_readme = create_commit(nil, "update README", {
      "README" => "lorem ipsum\n",
    })
    ref_updates = [
      create_ref_update(
        @repo,
        name: refname,
        before_oid: oid_add_readme,
        after_oid: GitHub::NULL_OID,
      ),
    ]

    app = create :integration, default_permissions: { "checks" => :write }, owner: @user
    bot = app.bot
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, bot)

    refute_predicate decisions[0], :allowed?
    assert_equal "refusing to delete the current branch: #{refname}", decisions[0].short_message
  end

  test "does not allow private emails in commits" do
    @mock_commit = mock("Commit")
    @mock_commit.stubs(:author_email).returns(@user.primary_user_email.email)
    @mock_commit.stubs(:committer_email).returns(@user.primary_user_email.email)

    ref_updates = [
      create_branch_update(@repo, name: "refs/heads/master"),
    ]

    Git::Ref::Update.any_instance.expects(:after_commit).times(3).returns(@mock_commit)

    @user.primary_user_email.toggle_visibility
    @user.update!(warn_private_email: true)

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    refute_predicate decisions[0], :allowed?
  end

  test "blocks annotated tag pushes with private emails" do
    ref_updates = [
      create_tag_update(@repo, name: "taggo"),
    ]

    @mock_tag = mock("Tag")
    @mock_tag.stubs(:author_email).returns(@user.primary_user_email.email)

    @mock_objects = mock("RepositoryObjectsCollection")
    @mock_objects.stubs(:read).returns(@mock_tag)

    Repository.any_instance.stubs(:objects).returns(@mock_objects)

    @user.primary_user_email.toggle_visibility
    @user.update!(warn_private_email: true)

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    refute_predicate decisions[0], :allowed?
  end

  test "does not block delete tag pushes" do
    ref_updates = [
      create_tag_update(@repo, name: "taggo", after_oid: GitHub::NULL_OID),
    ]

    @user.primary_user_email.toggle_visibility
    @user.update!(warn_private_email: true)

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_predicate decisions[0], :allowed?
  end

  test "does not block non-public emails that don't belong to you" do
    @other_user = create(:user)
    @email = @other_user.emails.build email: "otheruseremail@example.com"
    @mock_commit = mock("Commit")
    @mock_commit.stubs(:author_email).returns(@email.to_s)
    @mock_commit.stubs(:committer_email).returns(@email.to_s)

    ref_updates = [
      create_branch_update(@repo, name: "master"),
    ]

    Git::Ref::Update.any_instance.expects(:after_commit).times(3).returns(@mock_commit)

    @user.primary_user_email.toggle_visibility
    @user.update!(warn_private_email: true)

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_predicate decisions[0], :allowed?
  end

  test "denies all pushes if any fail while atomic" do
    @repo.protected_branches.create!(name: "master", creator: @user)

    ref_updates = [
      create_branch_update(@repo, name: "cr-line-endings"),
      create_branch_update(@repo, name: "master", after_oid: GitHub::NULL_OID),
      create_branch_update(@repo, name: "other-branch"),
    ]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user, atomic: true)

    refute_predicate decisions[0], :allowed?
    refute_predicate decisions[1], :allowed?
    refute_predicate decisions[2], :allowed?
    assert_equal "atomic transaction failed", decisions[0].short_message
    refute_equal "atomic transaction failed", decisions[1].short_message
    assert_equal "atomic transaction failed", decisions[2].short_message
  end

  test "allows all pushes if all succeed while atomic" do
    @repo.protected_branches.create!(name: "master", creator: @user)

    ref_updates = [
      create_branch_update(@repo, name: "cr-line-endings"),
      create_branch_update(@repo, name: "random"),
      create_branch_update(@repo, name: "other-branch"),
    ]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user, atomic: true)

    assert_predicate decisions[0], :allowed?
    assert_predicate decisions[1], :allowed?
    assert_predicate decisions[2], :allowed?
  end

  test "it can handle after_commit being nil" do
    ref_updates = [
      create_branch_update(@repo, name: "other"),
    ]

    Git::Ref::Update.any_instance.expects(:after_commit).returns(nil)

    @user.primary_user_email.toggle_visibility
    @user.update!(warn_private_email: true)

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_predicate decisions[0], :allowed?
  end

  if GitHub.merge_queues_enabled?
    test "rejects push to merge queue locked branch" do
      MergeQueueLockedRef.create!(
        repository: @repo_with_merge_queue,
        queue: @repo_with_merge_queue.default_merge_queue,
        ref: "cr-line-endings",
      )

      ref_updates = [create_branch_update(
        @repo_with_merge_queue,
        name: "cr-line-endings",
        before_oid: @repo_with_merge_queue.heads["cr-line-endings"].target_oid,
        after_oid: GitHub::NULL_OID,
      )]

      decisions = RefUpdatesPolicy.check(@repo_with_merge_queue, ref_updates, @user)

      error = <<~LONGMESSAGE
        error: GH006: Protected branch update failed for refs/heads/cr-line-endings.

        - A pull request for this branch has been added to a merge queue. Branches that
          are queued for merging cannot be updated. To modify this branch, dequeue the
          associated pull request.
      LONGMESSAGE

      refute_predicate decisions[0], :allowed?
      assert_equal "protected branch hook declined", decisions[0].short_message
      assert_equal error, decisions[0].long_message
    end

    test "does not reject push to merge queue locked branch if locked ref does not exist" do
      ref_updates = [create_branch_update(
        @repo_with_merge_queue,
        name: "cr-line-endings",
        before_oid: @repo_with_merge_queue.heads["cr-line-endings"].target_oid,
        after_oid: GitHub::NULL_OID,
      )]

      decisions = RefUpdatesPolicy.check(@repo_with_merge_queue, ref_updates, @user)
      assert_predicate decisions[0], :allowed?
    end

    test "does not reject push to merge queue locked branch if the repo does not have access to merge queue" do
      Repository.any_instance.stubs(:merge_queue_enabled?).returns(false)

      MergeQueueLockedRef.create!(
        repository: @repo_with_merge_queue,
        queue: @repo_with_merge_queue.default_merge_queue,
        ref: "cr-line-endings",
      )

      ref_updates = [create_branch_update(
        @repo_with_merge_queue,
        name: "cr-line-endings",
        before_oid: @repo_with_merge_queue.heads["cr-line-endings"].target_oid,
        after_oid: GitHub::NULL_OID,
      )]

      decisions = RefUpdatesPolicy.check(@repo_with_merge_queue, ref_updates, @user)
      assert_predicate decisions[0], :allowed?
    end
  else
    test "does not reject push to merge queue locked branch if merge queues aren't enabled" do
      enable_feature_flag(:merge_queue, @repo_with_merge_queue)

      MergeQueueLockedRef.create!(
        repository: @repo_with_merge_queue,
        queue: @repo_with_merge_queue.default_merge_queue,
        ref: "cr-line-endings",
      )

      ref_updates = [create_branch_update(
        @repo_with_merge_queue,
        name: "cr-line-endings",
        before_oid: @repo_with_merge_queue.heads["cr-line-endings"].target_oid,
        after_oid: GitHub::NULL_OID,
      )]

      decisions = RefUpdatesPolicy.check(@repo_with_merge_queue, ref_updates, @user)
      assert_predicate decisions[0], :allowed?
    end
  end

  test "disallows pushing more refs than limit when limit is set" do
    @repo.set_max_ref_updates(2, @repo.owner)

    ref_updates = [
      create_branch_update(@repo, name: "main"),
      create_branch_update(@repo, name: "develop"),
      create_branch_update(@repo, name: "develop2")
    ]

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_equal decisions.size, 3
    refute_predicate decisions[0], :allowed?
    refute_predicate decisions[1], :allowed?
    refute_predicate decisions[2], :allowed?
    assert_equal "push declined due to repository rule violations", decisions[0].short_message
    assert_equal "push declined due to repository rule violations", decisions[1].short_message
    assert_equal "push declined due to repository rule violations", decisions[2].short_message
    assert_equal "error: GH013: Repository rule violations found for refs/heads/main.\nReview all repository rules at https://github.com/#{@repo.owner.login}/#{@repo}/rules?ref=refs%2Fheads%2Fmain\n\n- Pushes can not update more than 2 branches or tags.\n\n", decisions[0].long_message
    assert_equal "error: GH013: Repository rule violations found for refs/heads/develop.\nReview all repository rules at https://github.com/#{@repo.owner.login}/#{@repo}/rules?ref=refs%2Fheads%2Fdevelop\n\n- Pushes can not update more than 2 branches or tags.\n\n", decisions[1].long_message
    assert_equal "error: GH013: Repository rule violations found for refs/heads/develop2.\nReview all repository rules at https://github.com/#{@repo.owner.login}/#{@repo}/rules?ref=refs%2Fheads%2Fdevelop2\n\n- Pushes can not update more than 2 branches or tags.\n\n", decisions[2].long_message
  end

  test "only show failure messages that are not overriden" do
    # Create a ruleset with a rule that cannot be bypassed
    no_bypass_ruleset = create(
      :repository_ruleset,
      :targets_all_branches,
      source: @repo
    )

    create(
      :repository_rule_configuration,
      rule_type: "branch_name_pattern",
      parameters: {
        operator: "starts_with",
        pattern: "develop",
        negate: true,
      },
      repository_ruleset: no_bypass_ruleset,
    )

    # Create a ruleset with a rule that can be bypassed
    bypass_ruleset = create(
      :repository_ruleset,
      :targets_all_branches,
      :repo_admin_bypass,
      source: @repo
    )

    create(
      :repository_rule_configuration,
      rule_type: "branch_name_pattern",
      parameters: {
        operator: "starts_with",
        pattern: "feature/",
      },
      repository_ruleset: bypass_ruleset,
    )

    ref_updates = [
      create_branch_update(@repo, name: "develop"),
      create_branch_update(@repo, name: "develop2"),
      create_branch_update(@repo, name: "develop3"),
    ]

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_equal decisions.size, 3
    assert decisions.all? { |decision| !decision.allowed? }
    assert decisions.all? { |decision| decision.short_message == "push declined due to repository rule violations" }
    assert decisions.all? { |decision| decision.long_message.include?("Branch name must not start with a matching pattern: develop") }
    refute decisions.all? { |decision| decision.long_message.include?("Branch name must start with a matching pattern: feature/") }
  end

  test "show all failure messages that are not overriden" do
    # Create a ruleset with a rule that cannot be bypassed
    no_bypass_ruleset = create(
      :repository_ruleset,
      :targets_all_branches,
      source: @repo
    )

    create(
      :repository_rule_configuration,
      rule_type: "branch_name_pattern",
      parameters: {
        operator: "starts_with",
        pattern: "develop",
        negate: true,
      },
      repository_ruleset: no_bypass_ruleset,
    )

    # Create a ruleset with a rule that can be bypassed
    bypass_ruleset = create(
      :repository_ruleset,
      :targets_all_branches,
      :repo_admin_bypass,
      source: @repo
    )

    create(
      :repository_rule_configuration,
      rule_type: "branch_name_pattern",
      parameters: {
        operator: "starts_with",
        pattern: "feature/",
      },
      repository_ruleset: bypass_ruleset,
    )

    ref_updates = [
      create_branch_update(@repo, name: "develop"),
      create_branch_update(@repo, name: "develop2"),
      create_branch_update(@repo, name: "develop3"),
    ]

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_equal decisions.size, 3
    assert decisions.all? { |decision| !decision.allowed? }
    assert decisions.all? { |decision| decision.short_message == "push declined due to repository rule violations" }
    assert decisions.all? { |decision| decision.long_message.include?("Branch name must not start with a matching pattern: develop") }
    refute decisions.all? { |decision| decision.long_message.include?("Branch name must start with a matching pattern: feature/") }
  end

  test "don't show duplicate rule failure messages" do
    example_repo :simple, @repo

    new_commit = create_commit(@repo.heads["master"].target_oid, "some change", {
      "a.txt" => "testing",
    })

    pb = @repo.protected_branches.create!(name: "master", creator: @user)
    pb.pull_request_reviews_enforcement_level = :everyone
    pb.save!

    ruleset1 = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(
      :repository_rule_configuration,
      rule_type: "update",
      parameters: {
        update_allows_fetch_and_merge: false
      },
      repository_ruleset: ruleset1
    )

    ruleset2 = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(
      :repository_rule_configuration,
      rule_type: "update",
      parameters: {
        update_allows_fetch_and_merge: false
      },
      repository_ruleset: ruleset2
    )

    ruleset3 = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset3, rule_type: "pull_request", parameters: {
      required_approving_review_count: 1,
      require_code_owner_review: false,
      dismiss_stale_reviews_on_push: false,
      ignore_approvals_from_contributors: false,
      require_last_push_approval: false,
      authorized_dismissal_actors_only: false,
      required_review_thread_resolution: false
    })

    ref_updates = [create_branch_update(
      @repo,
      name: "master",
      before_oid: @repo.heads["master"].target_oid,
      after_oid: new_commit,
    )]

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_equal decisions.size, 1

    decision = decisions.first
    refute decision.allowed?
    assert_equal "push declined due to repository rule violations", decision.short_message
    assert_equal 1, decision.long_message.scan(/Cannot update this protected ref/).count
    assert_equal 1, decision.long_message.scan(/Changes must be made through a pull request/).count
  end

  test "show legacy branch protection failure messages" do
    example_repo :simple, @repo

    new_commit = create_commit(@repo.heads["master"].target_oid, "some change", {
      "a.txt" => "testing",
    })

    pb = @repo.protected_branches.create!(name: "master", creator: @user)
    pb.pull_request_reviews_enforcement_level = :everyone
    pb.save!

    ref_updates = [create_branch_update(
      @repo,
      name: "master",
      before_oid: @repo.heads["master"].target_oid,
      after_oid: new_commit,
    )]

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_equal decisions.size, 1
    assert decisions.all? { |decision| !decision.allowed? }
    assert decisions.all? { |decision| decision.short_message == "protected branch hook declined" }
    assert_equal "error: GH006: Protected branch update failed for refs/heads/master.\n\n- Changes must be made through a pull request.\n", decisions[0].long_message
  end

  test "show overriden rules in successful push" do
    example_repo :simple, @repo

    ruleset = create(:repository_ruleset, :targets_default_branch, :repo_admin_bypass, source: @repo)

    create(
      :repository_rule_configuration,
      rule_type: "update",
      parameters: {
        update_allows_fetch_and_merge: false
      },
      repository_ruleset: ruleset
    )

    new_commit = create_commit(@repo.heads["master"].target_oid, "some change", {
      "a.txt" => "testing",
    })

    ref_updates = [create_branch_update(
      @repo,
      name: "master",
      before_oid: @repo.heads["master"].target_oid,
      after_oid: new_commit,
    )]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_predicate decisions[0], :allowed?
    assert_equal "Bypassed rule violations for refs/heads/master:\n\n- Cannot update this protected ref.\n\n", decisions[0].long_message
  end

  test "show overriden rules in successful push (protected branch)" do
    example_repo :simple, @repo

    pb = @repo.protected_branches.create!(name: "master", creator: @user)
    pb.admin_enforced = false
    pb.enable_lock_branch
    pb.save!

    new_commit = create_commit(@repo.heads["master"].target_oid, "some change", {
      "a.txt" => "testing",
    })

    ref_updates = [create_branch_update(
      @repo,
      name: "master",
      before_oid: @repo.heads["master"].target_oid,
      after_oid: new_commit,
    )]
    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    assert_predicate decisions[0], :allowed?
    assert_equal "Bypassed rule violations for refs/heads/master:\n\n- Cannot change this locked branch\n\n", decisions[0].long_message
  end

  test "includes violations when present" do
    enable_feature_flag(:new_restricted_commits_rule)
    example_repo :simple, @repo

    first_commit = create_commit(@repo.heads["master"].target_oid, "Commit 1", {})
    second_commit = create_commit(first_commit, "Commit 2", {})
    third_commit = create_commit(second_commit, "Commit 3", {})

    ruleset = create(
      :repository_ruleset,
      :targets_all_branches,
      source: @repo
    )

    create(
      :repository_rule_configuration,
      rule_type: "commit_oid",
      parameters: {
        restricted_commits: [{
          oid: first_commit,
        }, {
          oid: second_commit,
        }],
      },
      repository_ruleset: ruleset,
    )

    ref_updates = [create_branch_update(
      @repo,
      name: "master",
      before_oid: @repo.heads["master"].target_oid,
      after_oid: third_commit,
    )]

    decisions = RefUpdatesPolicy.check(@repo, ref_updates, @user)

    refute_predicate decisions.first, :allowed?

    assert_equal "error: GH013: Repository rule violations found for refs/heads/master.\nReview all repository rules at https://github.com/#{@repo.owner.login}/#{@repo}/rules?ref=refs%2Fheads%2Fmaster\n\n- Commits cannot contain rejected OIDs\n  Found 2 violations:\n\n  #{second_commit}\n  #{first_commit}\n\n", decisions.first.long_message
  end

  def create_commit(parent, message, files)
    @repo.rpc.create_tree_changes(parent, {
      "message"   => message,
      "committer" => {
        "email"   => @user.git_author_email,
        "name"    => @user.git_author_name,
        "time"    => @user.time_zone.now.iso8601,
      },
    }, files)
  end
end
