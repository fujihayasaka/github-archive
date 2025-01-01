# typed: true
# frozen_string_literal: true

require "test_helper"

class ProtectedBranchTest < GitHub::TestCase
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner
    create(:merge_queue_integration)

    @user = create(:user)
    @repo = create :repository, owner: @user, from_example: :simple

    @org = create(:business_plus_organization)
    @org_admin = create(:user)
    @org.add_member @org_admin, action: :admin
    @org_repo = create(:repository, owner: @org, from_example: :simple)

    @private_org_repo = create(:private_repository, owner: @org, name: "private", from_example: :simple)

    @org_repo_team = create(:team, organization: @org)
    @org_repo_team_member = create(:user)
    @org_repo_team.add_member(@org_repo_team_member)
    @org_repo_team.add_repository(@org_repo, :admin)

    @app = create(:integration, default_permissions: { "contents" => :write, "administration" => :write })
    @installation = make_integration_installation(integration: @app, repository: @org_repo)
  end

  setup do
    reset_repo_root
    example_repo :simple, @repo
    # cargo culted from repository_restore_test
    # guess we need this for repository restores to work in test env
    Repository::StorageAdapter::RemoteShardedStorageAdapter.any_instance.stubs(:repo_backup_location).returns("#{Rails.root}/test/fixtures/git/examples/simple.git")

    # We don't actually have the repo in backup, so we copy it from the sample
    # repository. We take over the client-side because it's harder to figure out
    # which path is the current one if we take over the client-side.
    GitRPC::Client.any_instance.stubs(:gitbackups_restore).with do |spec|
      GitHub::GitbackupsTestHelper.restore_from_example(spec)
    end
  end

  def authorized_users(protected_branch)
    Authorization.service.actor_ids(actor_type: User, subject: protected_branch)
  end

  def authorized_teams(protected_branch)
    Authorization.service.actor_ids(actor_type: Team, subject: protected_branch)
  end

  def authorized_integration_installations(protected_branch)
    Permissions::Service.actor_ids_granted_permission(
      actor_type: "IntegrationInstallation",
      subject_type: "ProtectedBranch/contents",
      subject_ids: [protected_branch.id],
      action: Ability.actions[:write],
    )
  end

  test "create protected branch for repository's master branch" do
    protected_branch = create(:protected_branch,
      repository: @repo,
      name: "master",
    )
    assert protected_branch.valid?
  end

  test "publishes an event to hydro on creation", skip_enterprise: true do
    protected_branch = create(:protected_branch,
      repository: @repo,
      name: "master",
    )

    assert_hydro_published({
      request_context: nil,
      actor: Hydro::EntitySerializer.user(protected_branch.creator),
      repository: Hydro::EntitySerializer.repository(@repo),
      repository_owner: Hydro::EntitySerializer.user(@user),
      branch_protection_rule: Hydro::EntitySerializer.branch_protection_rule(protected_branch),
      action: :CREATE,
    }, schema: "github.v1.BranchProtectionRuleChange")
  end

  test "publishes an event to hydro on update", skip_enterprise: true do
    protected_branch = create(:protected_branch,
      repository: @repo,
      name: "master",
    )

    actor = create(:user)
    GitHub.context.push actor: actor

    protected_branch.enable_required_linear_history
    protected_branch.save!

    assert_hydro_published({
      request_context: nil,
      actor: Hydro::EntitySerializer.user(actor),
      repository: Hydro::EntitySerializer.repository(@repo),
      repository_owner: Hydro::EntitySerializer.user(@user),
      branch_protection_rule: Hydro::EntitySerializer.branch_protection_rule(protected_branch),
      action: :UPDATE,
    }, schema: "github.v1.BranchProtectionRuleChange")
  end

  test "publishes an event to hydro on destruction", skip_enterprise: true do
    protected_branch = create(:protected_branch,
      repository: @repo,
      name: "master",
    )

    actor = create(:user)
    GitHub.context.push actor: actor

    protected_branch.destroy

    assert_hydro_published({
      request_context: nil,
      actor: Hydro::EntitySerializer.user(actor),
      repository: Hydro::EntitySerializer.repository(@repo),
      repository_owner: Hydro::EntitySerializer.user(@user),
      branch_protection_rule: Hydro::EntitySerializer.branch_protection_rule(protected_branch),
      action: :DESTROY,
    }, schema: "github.v1.BranchProtectionRuleChange")
  end

  test "invalid without repository parent association" do
    protected_branch = build(:protected_branch,
      repository: nil,
    )
    refute protected_branch.valid?

    assert protected_branch.errors[:repository]
  end

  test "invalid without branch name" do
    protected_branch = build(:protected_branch,
      repository: @repo,
      name: nil,
    )
    refute protected_branch.valid?

    assert protected_branch.errors[:name]
  end

  test "valid if branch name is a weird ref name" do
    assert oid = @repo.heads["master"].target_oid
    assert @repo.refs.create("refs/heads/--hook--", oid, @repo.owner)

    protected_branch = build(:protected_branch,
      repository: @repo,
      creator: @repo.owner,
      name: "--hook--",
    )

    assert_predicate protected_branch, :valid?
  end

  test "enqueues AutoMergeSynchronizeOpenPullRequestsJob on update to protected branch" do
    pull = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
    protected_branch = @repo.protect_branch(pull.base_ref_name, creator: @user, required_pull_request_reviews: {
      require_code_owner_reviews: true
    }, enforce_admins: true, entry_point: :test_case)
    @repo.allow_auto_merge(actor: @user)
    create(:auto_merge_request, pull_request: pull.reload, user: @user)

    assert_enqueued_with(job: AutoMergeSynchronizeOpenPullRequestsJob) do
      protected_branch.update!(dismiss_stale_reviews_on_push: true)
    end
  end

  context ".for_repository_with_branch_name" do
    test "returns nil if no protected branch rule matches the given branch name" do
      refute ProtectedBranch.for_repository_with_branch_name(@repo, "master")
    end

    test "returns the first protected branch whose rule matches the given branch name" do
      protected_branch = create(:protected_branch, repository: @repo, name: "master")

      assert_equal protected_branch, ProtectedBranch.for_repository_with_branch_name(@repo, "master")
    end
  end

  context ".for_repository_with_branch_names" do
    test "returns protected branch for given branch name" do
      protected_branch = create(:protected_branch, repository: @repo, name: "master")

      assert_equal ({ "master" => protected_branch }), ProtectedBranch.for_repository_with_branch_names(@repo, ["master"])
    end

    test "returns nil key value for branches without a protected branch rule" do
      assert_equal ({ "master" => nil }), ProtectedBranch.for_repository_with_branch_names(@repo, ["master"])
    end

    test "multi lookup returns right info for all branches" do
      # "master" branch is protected
      protected_branch = create(:protected_branch, repository: @repo, name: "master")
      # "unprotected" is unprotected
      assert oid = @repo.heads["master"].target_oid
      assert @repo.refs.create("refs/heads/unprotected", oid, @repo.owner)

      branch_info = ProtectedBranch.for_repository_with_branch_names(@repo, %w[master unprotected nonexistent])

      assert_equal(3, branch_info.size)
      assert_equal(protected_branch, branch_info["master"])
      assert_nil(branch_info["unprotected_branch"])
      assert_nil(branch_info["nonexistent"])
    end

    test "handles duplicate branch names" do
      # "master" branch is protected
      protected_branch = create(:protected_branch, repository: @repo, name: "master")
      # "unprotected" is unprotected
      assert oid = @repo.heads["master"].target_oid
      assert @repo.refs.create("refs/heads/unprotected", oid, @repo.owner)

      branch_info = ProtectedBranch.for_repository_with_branch_names(@repo, %w[master unprotected nonexistent master unprotected])

      assert_equal(3, branch_info.size)
      assert_equal(protected_branch, branch_info["master"])
      assert_nil(branch_info["unprotected_branch"])
      assert_nil(branch_info["nonexistent"])
    end
  end

  context "derive allow_force_pushes_enforcement_level, allow_deletions_enforcement_level, and lock_branch_enforcement_level from old columns" do
    test "allow_force_pushes_enforcement_level" do
      protected_branch = build(:protected_branch)

      protected_branch.block_force_pushes_enforcement_level_everyone!
      assert_predicate protected_branch, :block_force_pushes_enforcement_level_everyone?
      assert_predicate protected_branch, :allow_force_pushes_enforcement_level_off?

      protected_branch.block_force_pushes_enforcement_level_off!
      assert_predicate protected_branch, :block_force_pushes_enforcement_level_off?
      assert_predicate protected_branch, :allow_force_pushes_enforcement_level_everyone?

      protected_branch.block_force_pushes_enforcement_level_non_admins!
      assert_predicate protected_branch, :block_force_pushes_enforcement_level_non_admins?
      assert_predicate protected_branch, :allow_force_pushes_enforcement_level_off?
    end

    test "allow_deletions_enforcement_level" do
      protected_branch = build(:protected_branch)

      protected_branch.block_deletions_enforcement_level_everyone!
      assert_predicate protected_branch, :block_deletions_enforcement_level_everyone?
      assert_predicate protected_branch, :allow_deletions_enforcement_level_off?

      protected_branch.block_deletions_enforcement_level_off!
      assert_predicate protected_branch, :block_deletions_enforcement_level_off?
      assert_predicate protected_branch, :allow_deletions_enforcement_level_everyone?

      protected_branch.block_deletions_enforcement_level_non_admins!
      assert_predicate protected_branch, :block_deletions_enforcement_level_non_admins?
      assert_predicate protected_branch, :allow_deletions_enforcement_level_off?
    end

    test "lock_branch_enforcement_level" do
      protected_branch = build(:protected_branch)

      assert_predicate protected_branch, :lock_branch_enforcement_level_off?

      protected_branch.lock_branch_enforcement_level_everyone!
      assert_predicate protected_branch, :lock_branch_enforcement_level_everyone?

      protected_branch.lock_branch_enforcement_level_off!
      assert_predicate protected_branch, :lock_branch_enforcement_level_off?

      protected_branch.lock_branch_enforcement_level_non_admins!
      assert_predicate protected_branch, :lock_branch_enforcement_level_non_admins?
    end
  end

  context "#require_code_owner_review?" do
    test "returns the column value if code owners is supported by billing plan" do
      @repo.stubs(:plan_supports?).returns(true)
      @repo.stubs(:plan_supports?).with(:codeowners).returns(true)
      protection_rule = create(:protected_branch, {
        repository: @repo,
        creator: @repo.owner,
        name: "*",
      })

      protection_rule.require_code_owner_review = true
      assert_predicate protection_rule, :require_code_owner_review?

      protection_rule.require_code_owner_review = false
      refute_predicate protection_rule, :require_code_owner_review?
    end

    test "always returns false if code owners not supported by billing plan" do
      protection_rule = create(:protected_branch, {
        repository: @repo,
        creator: @repo.owner,
        name: "*",
      })

      protection_rule.repository.stubs(:plan_supports?).returns(true)
      protection_rule.repository.stubs(:plan_supports?).with(:codeowners).returns(false)

      protection_rule.require_code_owner_review = true
      refute_predicate protection_rule, :require_code_owner_review?

      protection_rule.require_code_owner_review = false
      refute_predicate protection_rule, :require_code_owner_review?
    end
  end

  test "valid if branch name is qualified ref name" do
    protected_branch = build(:protected_branch,
      repository: @repo,
      creator: @repo.owner,
      name: "refs/heads/master",
    )

    assert_predicate protected_branch, :valid?
  end

  test "valid if ref does not exist" do
    protected_branch = build(:protected_branch,
        repository: @repo,
        creator: @repo.owner,
        name: "i-do-not-exist",
    )
    assert_predicate protected_branch, :valid?
  end

  test "valid for free private repos", skip_enterprise: true do
    user = create(:user)
    repo = create(:private_repository, owner: user)
    protected_branch = build(:protected_branch, repository: repo, creator: user, name: "blorp")

    assert_predicate protected_branch, :valid?
  end

  context "#deep_copy_as!" do
    test "returns a new protected branch with the given name and all the settings (including associations) copied" do
      protection_rule = create(:protected_branch, {
        repository: @org_repo,
        creator: @org_admin,
        name: "*",
      })

      protection_rule.enable_required_pull_request_reviews(
        dismissal_restrictions: {
          "teams" => [],
          "users" => [@org_admin.login],
        },
        dismiss_stale_reviews: true,
        require_code_owner_reviews: true,
        required_approving_review_count: 2,
        bypass_pull_request_allowances: {
          "teams" => [],
          "users" => [@org_admin.login],
        }
      )

      protection_rule.enable_blocked_force_pushes
      protection_rule.replace_branch_actor_allowances(:force_push, user_ids: [@org_admin.id], team_ids: [], integration_ids: [])

      protection_rule.update_restrictions(users: [@org_admin.login], teams: [], entry_point: :test_case)

      protected_branch = protection_rule.deep_copy_as!(name: "master", creator: @org_admin, entry_point: :test_case)

      assert_predicate protected_branch, :persisted?
      refute_equal protected_branch.id, protection_rule.id

      assert_equal "master", protected_branch.name

      assert_predicate protected_branch, :required_status_checks_enforcement_level_off?
      assert_equal true, protected_branch.strict_required_status_checks_policy
      assert_equal true, protected_branch.authorized_actors_only
      assert_predicate protected_branch, :pull_request_reviews_enforcement_level_non_admins?
      assert_equal true, protected_branch.authorized_dismissal_actors_only
      assert_equal false, protected_branch.admin_enforced
      assert_equal true, protected_branch.dismiss_stale_reviews_on_push
      assert_equal true, protected_branch.require_code_owner_review
      assert_predicate protected_branch, :signature_requirement_enforcement_level_off?
      assert_predicate protected_branch, :linear_history_requirement_enforcement_level_off?
      assert_equal 2, protected_branch.required_approving_review_count
      assert_predicate protected_branch, :block_force_pushes_enforcement_level_everyone?

      assert_equal [["User", @org_admin.id]], protected_branch.review_dismissal_allowances.map { |allowance| [allowance.actor_type, allowance.actor_id] }
      assert_equal [["User", @org_admin.id]], protected_branch.authorized_actors.map { |actor| [actor.class.name, actor.id] }
      assert_equal [["User", @org_admin.id]], protected_branch.branch_actor_allowances.select { |allowance| allowance.policy == "pull_request" }.map { |allowance| [allowance.actor_type, allowance.actor_id] }
      assert_equal [["User", @org_admin.id]], protected_branch.branch_actor_allowances.select { |allowance| allowance.policy == "force_push" }.map { |allowance| [allowance.actor_type, allowance.actor_id] }
    end
  end

  test "branch name length limits" do
    repo = create(:repository, from_example: :simple)

    # 255 is the max length pre-receive hooks allow for a ref name including refs/heads/
    assert oid = repo.heads["master"].target_oid
    valid_branch_name = "refs/heads/#{"a" * 242}"
    assert repo.refs.create valid_branch_name, oid, repo.owner

    protected_branch = create(:protected_branch,
      repository: repo,
      name: valid_branch_name,
      creator: create(:user),
    )

    assert protected_branch.valid?, "branch errors: #{protected_branch.errors.full_messages}"

    # On Mac OS, you can't create a path longer than 1024 bytes:
    # So we skip creating the actual branch on disc, and
    # use a stub to bypass the git ref validation.  On Linux it's
    # possible this test could work w/o the stub.
    expected_characters = 1024 / 4
    too_long_branch_name = "a" * 1025
    protected_branch = build(:protected_branch,
       repository: repo,
       name: too_long_branch_name,
       creator: create(:user),
    )
    refute protected_branch.valid?
    assert_equal "is too long (maximum is #{expected_characters} characters)", protected_branch.errors[:name].first
  end

  test "invalid if branch name already exists for repository" do
    create(:protected_branch,
      repository: @repo,
      name: "master",
    )

    protected_branch = build(:protected_branch,
      repository: @repo,
      name: "master",
    )
    refute protected_branch.valid?

    assert_equal "already protected: master", protected_branch.errors[:name].first
  end

  test "invalid when no creator" do
    protected_branch = build(:protected_branch,
      repository: @repo,
      creator: nil,
    )
    refute protected_branch.valid?
    assert_equal "can't be blank", protected_branch.errors[:creator_id].first
  end

  test "cannot create with Organization as creator" do
    protected_branch = build(:protected_branch,
      repository: @repo,
      creator: create(:organization),
    )
    refute protected_branch.valid?
    assert_equal "must be a User", protected_branch.errors[:creator_id].first
  end

  test "cannot set Organization as creator" do
    protected_branch = create(:protected_branch,
      repository: @repo,
      creator: create(:user),
    )
    assert_predicate protected_branch, :valid?
    protected_branch.creator = create(:organization)
    refute_predicate protected_branch, :valid?
    assert_equal "must be a User", protected_branch.errors[:creator_id].first
  end

  test "can save if creator is converted from User to Organization" do
    protected_branch = create(:protected_branch,
      repository: @repo,
      creator: create(:user),
    )
    assert_predicate protected_branch, :valid?

    perform_enqueued_jobs(only: [TransformUserIntoOrgJob]) do
      Organization.transform(protected_branch.creator, create(:user))
    end

    # Use find instead of reload to ensure nothing is cached.
    protected_branch = ProtectedBranch.find(protected_branch.id)
    assert_kind_of Organization, protected_branch.creator
    assert_predicate protected_branch, :valid?

    protected_branch.updated_at = Time.now
    protected_branch.save!
  end

  test "setting required reviews enforcement level" do
    protected_branch = ProtectedBranch.new
    protected_branch.pull_request_reviews_enforcement_level = :everyone
    assert_predicate protected_branch, :pull_request_reviews_enforcement_level_everyone?
  end

  test "setting required signatures enforcement level" do
    protected_branch = ProtectedBranch.new
    protected_branch.signature_requirement_enforcement_level = :everyone
    assert_predicate protected_branch, :signature_requirement_enforcement_level_everyone?
  end

  test "setting required linear commit history enforcement level" do
    protected_branch = ProtectedBranch.new
    protected_branch.linear_history_requirement_enforcement_level = :everyone
    assert_predicate protected_branch, :linear_history_requirement_enforcement_level_everyone?
  end

  test "prevents linear history enforcement when the only accepted merge strategy is merge" do
    protected_branch = create(:protected_branch, repository: @repo, creator: @user, name: "master")
    @repo.update_merge_settings(@user, merge_allowed: true, squash_allowed: false, rebase_allowed: false)

    protected_branch.enable_required_linear_history

    refute_predicate protected_branch, :valid?
    assert_equal "cannot enforce linear history without a non-merge strategy enabled",
      protected_branch.errors[:linear_history_requirement_enforcement_level].first
  end

  test "setting force push blocking" do
    protected_branch = ProtectedBranch.new
    protected_branch.block_force_pushes_enforcement_level = :everyone
    assert_predicate protected_branch, :block_force_pushes_enforcement_level_everyone?
  end

  test "setting deletion blocking" do
    protected_branch = ProtectedBranch.new
    protected_branch.block_deletions_enforcement_level = :everyone
    assert_predicate protected_branch, :block_deletions_enforcement_level_everyone?
  end

  test "setting lock branch policy" do
    protected_branch = ProtectedBranch.new
    protected_branch.lock_branch_enforcement_level = :everyone
    assert_predicate protected_branch, :lock_branch_enforcement_level_everyone?

    protected_branch.lock_branch_enforcement_level = :off
    assert_predicate protected_branch, :lock_branch_enforcement_level_off?

    protected_branch.lock_branch_enforcement_level = :non_admins
    assert_predicate protected_branch, :lock_branch_enforcement_level_non_admins?
  end

  test "set sync fork policy when branch is locked" do
    protected_branch = ProtectedBranch.new
    # default to false
    refute_predicate protected_branch, :lock_allows_fetch_and_merge?

    protected_branch.lock_allows_fetch_and_merge = true
    assert_predicate protected_branch, :lock_allows_fetch_and_merge?

    protected_branch.lock_allows_fetch_and_merge = false
    refute_predicate protected_branch, :lock_allows_fetch_and_merge?
  end

  context "#replace_status_contexts" do
    test "updates the protected branch's required_status_checks" do
      protected_branch = create(:protected_branch,
        repository: @repo,
      )

      protected_branch.required_status_checks.create! context: "context1"
      context2 = protected_branch.required_status_checks.create! context: "context2"

      assert_equal %w( context1 context2 ), protected_branch.required_status_checks.map(&:context).sort

      protected_branch.replace_status_contexts %w( context2 context3 )
      protected_branch.reload

      assert_equal %w( context2 context3 ), protected_branch.required_status_checks.map(&:context).sort
      assert_equal context2.id, protected_branch.required_status_checks.find { |s| s.context == "context2" }.id

      protected_branch.replace_status_contexts(nil)
      protected_branch.reload

      assert protected_branch.required_status_checks.map(&:context).empty?
    end

    test "destroys non-required contexts" do
      protected_branch = create(:protected_branch,
        repository: @repo,
      )

      protected_branch.required_status_checks.create! context: "context1"
      protected_branch.required_status_checks.create! context: "context2"

      assert_difference("RequiredStatusCheck.count", -1) do
        protected_branch.replace_status_contexts(%w(context1))
      end
    end

    test "associates newly created contexts with an appropriate integration" do
      github_app = create :integration
      create(
        :status,
        sha: @repo.heads["master"].target_oid,
        repository: @repo,
        context: "test",
        creator: github_app.bot
      )
      protected_branch = create(:protected_branch, repository: @repo)

      protected_branch.replace_status_contexts %w( test )

      required_status_check = protected_branch.required_status_checks.first
      assert_predicate required_status_check, :present?
      assert_equal "test", required_status_check.context
      assert_equal github_app, required_status_check.integration
    end

    test "does not change the integration of existing contexts" do
      github_app = create :integration
      create(
        :status,
        sha: @repo.heads["master"].target_oid,
        repository: @repo,
        context: "test",
        creator: github_app.bot
      )
      protected_branch = create(:protected_branch, repository: @repo)
      protected_branch.required_status_checks.create!(
        context: "test",
        integration: nil,
      )

      protected_branch.replace_status_contexts %w( test )

      required_status_check = protected_branch.required_status_checks.first
      assert_predicate required_status_check, :present?
      assert_equal "test", required_status_check.context
      assert_nil required_status_check.integration
    end
  end

  context "#replace_statuses" do
    test "creates new required status checks" do
      integration = create(:integration)
      protected_branch = create(:protected_branch,
        repository: @repo,
      )

      protected_branch.replace_statuses([
        { context: "test", integration: integration },
      ])

      assert_equal 1, protected_branch.required_status_checks.count

      status_check = protected_branch.required_status_checks.first
      assert_equal "test", status_check.context
      assert_equal integration, status_check.integration
    end

    test "sets a new status check's integration automatically if none is given" do
      integration = create(:integration)
      protected_branch = create(:protected_branch, repository: @repo)
      create(
        :status,
        sha: @repo.heads["master"].target_oid,
        repository: @repo,
        context: "test",
        creator: integration.bot,
      )

      protected_branch.replace_statuses([
        { context: "test" }
      ])

      assert_equal 1, protected_branch.required_status_checks.count

      status_check = protected_branch.required_status_checks.first
      assert_equal "test", status_check.context
      assert_equal integration, status_check.integration
    end

    test "updates existing status checks" do
      old_integration = create(:integration)
      new_integration = create(:integration)
      protected_branch = create(:protected_branch,
        repository: @repo,
      )
      existing_check = protected_branch.required_status_checks.create!(
        context: "test",
        integration: old_integration,
      )

      protected_branch.replace_statuses([
        { context: "test", integration: new_integration },
      ])

      assert_equal 1, protected_branch.required_status_checks.count

      status_check = protected_branch.required_status_checks.first
      assert_equal existing_check.id, status_check.id
      assert_equal "test", status_check.context
      assert_equal new_integration, status_check.integration
    end

    test "doesn't change an existing status check's app if none is given" do
      configured_integration = create(:integration)
      recently_used_integration = create(:integration)
      protected_branch = create(:protected_branch,
        repository: @repo,
      )
      existing_check = protected_branch.required_status_checks.create!(
        context: "test",
        integration: configured_integration,
      )
      create(
        :status,
        sha: @repo.heads["master"].target_oid,
        repository: @repo,
        context: "test",
        creator: recently_used_integration.bot,
      )

      protected_branch.replace_statuses([
        { context: "test" },
      ])

      assert_equal 1, protected_branch.required_status_checks.count

      status_check = protected_branch.required_status_checks.first
      assert_equal existing_check.id, status_check.id
      assert_equal "test", status_check.context
      assert_equal configured_integration, status_check.integration
    end

    test "doesn't set an app on an existing status check if none is given" do
      recently_used_integration = create(:integration)
      protected_branch = create(:protected_branch,
        repository: @repo,
      )
      existing_check = protected_branch.required_status_checks.create!(
        context: "test",
        integration: nil,
      )
      create(
        :status,
        sha: @repo.heads["master"].target_oid,
        repository: @repo,
        context: "test",
        creator: recently_used_integration.bot,
      )

      protected_branch.replace_statuses([
        { context: "test" },
      ])

      assert_equal 1, protected_branch.required_status_checks.count

      status_check = protected_branch.required_status_checks.first
      assert_equal existing_check.id, status_check.id
      assert_equal "test", status_check.context
      assert_nil status_check.integration
    end

    test "destroys redundant status checks" do
      protected_branch = create(:protected_branch,
        repository: @repo,
      )
      existing_check = protected_branch.required_status_checks.create!(
        context: "old",
      )

      protected_branch.replace_statuses([
        { context: "new", integration: nil },
      ])

      assert_equal 1, protected_branch.required_status_checks.count

      status_check = protected_branch.required_status_checks.first
      assert_equal "new", status_check.context
      assert_nil RequiredStatusCheck.find_by(id: existing_check.id)
    end

    test "supports specifying any app on a new status check" do
      integration = create(:integration)
      protected_branch = create(:protected_branch, repository: @repo)
      create(
        :status,
        sha: @repo.heads["master"].target_oid,
        repository: @repo,
        context: "test",
        creator: integration.bot,
      )

      protected_branch.replace_statuses([
        { context: "test", source: :any }
      ])

      assert_equal 1, protected_branch.required_status_checks.count

      status_check = protected_branch.required_status_checks.first
      assert_equal "test", status_check.context
      assert_nil status_check.integration
    end

    test "supports specifying any app on an existing status check" do
      configured_integration = create(:integration)
      recently_used_integration = create(:integration)
      protected_branch = create(:protected_branch,
        repository: @repo,
      )
      existing_check = protected_branch.required_status_checks.create!(
        context: "test",
        integration: configured_integration,
      )
      create(
        :status,
        sha: @repo.heads["master"].target_oid,
        repository: @repo,
        context: "test",
        creator: recently_used_integration.bot,
      )

      protected_branch.replace_statuses([
        { context: "test", source: :any },
      ])

      assert_equal 1, protected_branch.required_status_checks.count

      status_check = protected_branch.required_status_checks.first
      assert_equal existing_check.id, status_check.id
      assert_equal "test", status_check.context
      assert_nil status_check.integration
    end

  end

  test "replace required deployments" do
    protected_branch = create(:protected_branch,
      repository: @repo,
    )

    sha = @repo.default_branch_ref.target_oid
    @repo.deployments.create!(environment: "environment1", creator: @repo.owner, sha: sha)
    @repo.deployments.create!(environment: "environment2", creator: @repo.owner, sha: sha)

    environment1 = protected_branch.required_deployments.create! environment: "environment1"
    environment2 = protected_branch.required_deployments.create! environment: "environment2"
    environment3 = protected_branch.required_deployments.create! environment: "environment3"

    assert_equal %w( environment1 environment2 environment3 ), protected_branch.required_deployments.map(&:environment).sort

    protected_branch.replace_required_deployment_environments %w( environment2 environment3 )
    protected_branch.reload

    assert_equal %w( environment2 environment3 ), protected_branch.required_deployments.map(&:environment).sort
    assert_equal environment2.id, protected_branch.required_deployments.find { |s| s.environment == "environment2" }.id
    assert_equal environment3.id, protected_branch.required_deployments.find { |s| s.environment == "environment3" }.id

    protected_branch.replace_required_deployment_environments(nil)
    protected_branch.reload

    assert protected_branch.required_deployments.map(&:environment).empty?
  end

  test "replace required deployments ignores non-existent environments" do
    protected_branch = create(:protected_branch,
      repository: @repo,
    )

    sha = @repo.default_branch_ref.target_oid
    @repo.deployments.create!(environment: "environment1", creator: @repo.owner, sha: sha)
    environment1 = protected_branch.required_deployments.create! environment: "environment1"

    protected_branch.replace_required_deployment_environments %w( environment1 bogus )
    protected_branch.reload

    assert_equal %w( environment1 ), protected_branch.required_deployments.map(&:environment).sort
  end

  test "replace_required_deployment_environments destroys non-required deployment environments" do
    protected_branch = create(:protected_branch,
      repository: @repo,
    )

    environment1 = protected_branch.required_deployments.create! environment: "environment1"
    environment2 = protected_branch.required_deployments.create! environment: "environment2"

    assert_difference("RequiredDeployment.count", -1) do
      protected_branch.replace_required_deployment_environments(%w(environment1))
    end
  end

  test "enable_blocked_force_pushes" do
    protected_branch = create(:protected_branch, admin_enforced: false, block_force_pushes_enforcement_level: :off)
    protected_branch.enable_blocked_force_pushes
    protected_branch.save!

    # enforcement level should be set to :everyone even though admin_enforced? is false
    assert_predicate protected_branch, :block_force_pushes_enforcement_level_everyone?
    assert_predicate protected_branch, :block_force_pushes_enabled?
  end

  test "clear_blocked_force_pushes" do
    protected_branch = create(:protected_branch, block_force_pushes_enforcement_level: :everyone)
    protected_branch.clear_blocked_force_pushes
    protected_branch.save!

    assert_predicate protected_branch, :block_force_pushes_enforcement_level_off?
    refute_predicate protected_branch, :block_force_pushes_enabled?
  end

  test "returns true for teams and users that can bypass force push" do
    teammate = create(:user)
    team = create(:team, organization: @org)
    team.add_member(teammate)
    team.add_member(teammate)
    team.add_repository @org_repo, :admin
    @org_repo.add_member(@user, action: :write)
    protected_branch = create(:protected_branch, repository: @org_repo, block_force_pushes_enforcement_level: :everyone)
    refute protected_branch.can_override_force_push_policy?(actor: teammate)
    refute protected_branch.can_override_force_push_policy?(actor: @user)

    protected_branch.replace_branch_actor_allowances(:force_push, user_ids: [@user.id], team_ids: [team.id], integration_ids: [])
    assert protected_branch.can_override_force_push_policy?(actor: teammate)
    assert protected_branch.can_override_force_push_policy?(actor: @user)
  end

  test "enable_blocked_deletions" do
    protected_branch = create(:protected_branch, admin_enforced: false, block_deletions_enforcement_level: :off)
    protected_branch.enable_blocked_deletions
    protected_branch.save!

    # enforcement level should be set to :everyone even though admin_enforced? is false
    assert_predicate protected_branch, :block_deletions_enforcement_level_everyone?
    assert_predicate protected_branch, :block_deletions_enabled?
  end

  test "clear_blocked_deletions" do
    protected_branch = create(:protected_branch, block_deletions_enforcement_level: :everyone)
    protected_branch.clear_blocked_deletions
    protected_branch.save!

    assert_predicate protected_branch, :block_deletions_enforcement_level_off?
    refute_predicate protected_branch, :block_deletions_enabled?
  end

  test "enable_lock_branch" do
    protected_branch = create(:protected_branch, repository: @repo, admin_enforced: false, lock_branch_enforcement_level: :off)
    protected_branch.enable_lock_branch
    protected_branch.save!

    # enforcement level should be set to :non_admins
    assert_predicate protected_branch, :lock_branch_enforcement_level_non_admins?
    assert_predicate protected_branch, :lock_branch_enabled?
    refute_predicate protected_branch, :lock_allows_fetch_and_merge?
  end

  test "clear_lock_branch" do
    protected_branch = create(
      :protected_branch,
      repository: @repo,
      lock_branch_enforcement_level: :everyone,
      lock_allows_fetch_and_merge: true
    )
    refute_predicate protected_branch, :lock_branch_enforcement_level_off?
    assert_predicate protected_branch, :lock_branch_enabled?
    assert_predicate protected_branch, :lock_allows_fetch_and_merge?

    protected_branch.clear_lock_branch
    protected_branch.save!

    assert_predicate protected_branch, :lock_branch_enforcement_level_off?
    refute_predicate protected_branch, :lock_branch_enabled?
    # it will also disable the sync fork policy
    refute_predicate protected_branch, :lock_allows_fetch_and_merge?
  end

  test "clear_required_deployment_environments" do
    protected_branch = create(:protected_branch, block_deletions_enforcement_level: :everyone)
    protected_branch.replace_required_deployment_environments(%w[env1 env2])
    protected_branch.enable_required_deployments

    protected_branch.clear_required_deployment_environments
    protected_branch.save!

    refute_predicate protected_branch, :required_deployments_enabled?
    assert_equal [], protected_branch.required_deployments
  end

  context "#replace_authorized_actors" do
    test "raises error on personal repos" do
      protected_branch = create(:protected_branch, repository: @repo)
      assert_raises ProtectedBranch::OnlyOrgsHaveAuthorizedActors do
        protected_branch.replace_authorized_actors(user_ids: [@repo.owner.id], team_ids: [], entry_point: :test_case)
      end
      assert_empty protected_branch.authorized_actors
    end

    test "works with teams" do
      team = create(:team, organization: @org)
      team.add_repository @org_repo, :admin

      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [@org_repo_team.id], entry_point: :test_case)
      assert_equal [@org_repo_team], protected_branch.authorized_actors
    end

    test "works with member of team" do
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [@org_repo_team_member.id], team_ids: [], entry_point: :test_case)
      assert_equal [@org_repo_team_member], protected_branch.authorized_actors
    end

    test "does not work for users who do not have access to the repo" do
      non_member = create(:user)
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [non_member.id], team_ids: [], entry_point: :test_case)
      assert_empty protected_branch.authorized_actors
    end

    test "does not work for teams that are not part of the org" do
      team = create(:team)
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [team.id], entry_point: :test_case)
      assert_empty protected_branch.authorized_actors
    end

    test "does not work for teams that do not have access to the repo" do
      team = create(:team, organization: @org)
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [team.id], entry_point: :test_case)
      assert_empty protected_branch.authorized_actors
    end

    test "does not work for teams that do not have write access to the repo" do
      team = create(:team, organization: @org)
      team.add_repository @org_repo, :read
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [team.id], entry_point: :test_case)
      assert_empty protected_branch.authorized_actors
    end

    test "doesn't work for integrations that don't have write access to the repo" do
      app = create :integration
      installation = make_integration_installation(integration: app, repository: @org_repo,
                                                   permissions: { "contents" => :read })
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [],
                                                          integration_ids: [app.id], entry_point: :test_case)
      assert_empty protected_branch.authorized_actors
    end

    test "does not work for integration installations that do not have write access to the repo" do
      app = create :integration
      installation = make_integration_installation(integration: app, repository: @org_repo,
                                                   permissions: { "contents" => :read })
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [],
                                                          integration_ids: [app.id], entry_point: :test_case)
      assert_empty protected_branch.authorized_actors
    end

    test "does not work when a non-user is specified as a user" do
      org = create(:organization)
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [org.id], team_ids: [], entry_point: :test_case)
      assert_empty protected_branch.authorized_actors
    end

    test "does not work when a non-user is specified as a team" do
      org = create(:organization)
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [org.id], integration_ids: [], entry_point: :test_case)
      assert_empty protected_branch.authorized_actors
    end

    test "raises an error when too many actors are specified" do
      protected_branch = create(:protected_branch, repository: @org_repo)
      assert_raises ProtectedBranch::TooManyPermittedActors do
        protected_branch.replace_authorized_actors(user_ids: [], team_ids: 1.upto(101).to_a, integration_ids: [], entry_point: :test_case)
      end

      assert_raises ProtectedBranch::TooManyPermittedActors do
        protected_branch.replace_authorized_actors(user_ids: 1.upto(101).to_a, team_ids: [], integration_ids: [], entry_point: :test_case)
      end

      assert_raises ProtectedBranch::TooManyPermittedActors do
        protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], integration_ids: 1.upto(101).to_a, entry_point: :test_case)
      end

      assert_raises ProtectedBranch::TooManyPermittedActors do
        protected_branch.replace_authorized_actors(user_ids: 1.upto(34).to_a, team_ids: 1.upto(34).to_a,
                                                            integration_ids: 1.upto(34).to_a, entry_point: :test_case)
      end
    end

    test "rolls back cleared abilities when clearing permissions fail" do
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [@org_repo_team.id],
                                                          integration_ids: [@app.id], entry_point: :test_case)

      Permissions::Service.stubs(:revoke_permissions_granted_on_subject).raises(ActiveRecord::StatementInvalid)

      assert_raises ActiveRecord::StatementInvalid do
        protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], integration_ids: [], entry_point: :test_case)
      end

      refute_empty authorized_users(protected_branch), "Authorized User has been deleted (but should NOT be)"
      refute_empty authorized_teams(protected_branch), "Authorized Team has been deleted (but should NOT be)"
      refute_empty authorized_integration_installations(protected_branch), "Authorized IntegrationInstallation has been deleted (but should NOT be)"
    end
  end

  context "#add_integrations_to_restrictions then #remove_integrations_from_restrictions" do
    test "adds and removes integrations from restrictons" do
      other_app = create :integration
      other_installation = make_integration_installation(integration: other_app, repository: @org_repo, permissions: { "contents" => :write })
      protected_branch = create(:protected_branch, repository: @org_repo)

      protected_branch.remove_integrations_from_restrictions([other_installation.integration.slug], entry_point: :test_case)
      protected_branch.add_integrations_to_restrictions([@installation.integration.slug], entry_point: :test_case)
      protected_branch.add_integrations_to_restrictions([other_installation.integration.slug], entry_point: :test_case)

      assert_same_elements [@installation, other_installation], protected_branch.authorized_integration_installations,
        "IntegrationInstallations not authorized"
      assert_same_elements [@installation.id, other_installation.id], protected_branch.authorized_integration_installation_ids
      assert_same_elements [@app.id, other_app.id], protected_branch.authorized_integration_ids
      assert_same_elements [@app, other_app], protected_branch.authorized_integrations

      protected_branch.remove_integrations_from_restrictions([other_installation.integration.slug], entry_point: :test_case)

      assert_equal [@installation], protected_branch.authorized_integration_installations
      "Other IntegrationInstallations still authorized"
      assert_equal [@installation.id], protected_branch.authorized_integration_installation_ids
      assert_equal [@app.id], protected_branch.authorized_integration_ids
      assert_equal [@app], protected_branch.authorized_integrations
    end
  end

  context "instrumentation" do
    test "includes org info in instrumentation event payload for org repos on create" do
      events = subscribe "protected_branch.create"
      protected_branch = create(:protected_branch, repository: @org_repo,
        creator: @user)

      expected_payload = {
        name: "master",
        authorized_actor_names: [],
        required_status_checks_enforcement_level: 0,
        strict_required_status_checks_policy: true,
        dismiss_stale_reviews_on_push: false,
        require_code_owner_review: false,
        require_last_push_approval: false,
        ignore_approvals_from_contributors: false,
        pull_request_reviews_enforcement_level: 0,
        required_approving_review_count: 1,
        signature_requirement_enforcement_level: 0,
        linear_history_requirement_enforcement_level: 0,
        admin_enforced: false,
        allow_force_pushes_enforcement_level: 0,
        allow_deletions_enforcement_level: 0,
        required_deployments_enforcement_level: 0,
        required_review_thread_resolution_enforcement_level: 0,
        merge_queue_enforcement_level: 0,
        enforcement_level: "off",
        lock_branch_enforcement_level: 0,
        lock_allows_fetch_and_merge: false,
        create_protected: false,
        protected_branch_id: protected_branch.id,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.name,
        org_id: @org.id,
        user: @user.login,
        user_id: @user.id,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "includes org info in instrumentation event payload for org repos on deletion" do
      events = subscribe "protected_branch.destroy"
      protected_branch = create(:protected_branch,
        repository: @org_repo,
        creator: @user,
      )

      protected_branch.destroy

      expected_payload = {
        name: "master",
        authorized_actor_names: [],
        required_status_checks_enforcement_level: 0,
        strict_required_status_checks_policy: true,
        dismiss_stale_reviews_on_push: false,
        require_code_owner_review: false,
        require_last_push_approval: false,
        ignore_approvals_from_contributors: false,
        pull_request_reviews_enforcement_level: 0,
        required_approving_review_count: 1,
        signature_requirement_enforcement_level: 0,
        linear_history_requirement_enforcement_level: 0,
        admin_enforced: false,
        allow_force_pushes_enforcement_level: 0,
        allow_deletions_enforcement_level: 0,
        required_deployments_enforcement_level: 0,
        required_review_thread_resolution_enforcement_level: 0,
        merge_queue_enforcement_level: 0,
        enforcement_level: "off",
        lock_branch_enforcement_level: 0,
        lock_allows_fetch_and_merge: false,
        create_protected: false,
        protected_branch_id: protected_branch.id,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.name,
        org_id: @org.id,
      }

      assert event = events.pop, "expected event"
      assert_equal "protected_branch.destroy", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments create" do
      events = subscribe "protected_branch.create"
      protected_branch = create(:protected_branch, repository: @repo,
        creator: @user)

      expected_payload = {
        name: "master",
        authorized_actor_names: [],
        required_status_checks_enforcement_level: 0,
        strict_required_status_checks_policy: true,
        dismiss_stale_reviews_on_push: false,
        require_code_owner_review: false,
        require_last_push_approval: false,
        ignore_approvals_from_contributors: false,
        pull_request_reviews_enforcement_level: 0,
        required_approving_review_count: 1,
        signature_requirement_enforcement_level: 0,
        linear_history_requirement_enforcement_level: 0,
        admin_enforced: false,
        allow_force_pushes_enforcement_level: 0,
        allow_deletions_enforcement_level: 0,
        required_deployments_enforcement_level: 0,
        required_review_thread_resolution_enforcement_level: 0,
        merge_queue_enforcement_level: 0,
        enforcement_level: "off",
        lock_branch_enforcement_level: 0,
        lock_allows_fetch_and_merge: false,
        create_protected: false,
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        user: @user.login,
        user_id: @user.id,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to strict/loose policy flag" do
      events = subscribe "protected_branch.update_strict_required_status_checks_policy"
      protected_branch = create(:protected_branch, repository: @repo,
        creator: @user, strict_required_status_checks_policy: true)

      protected_branch.strict_required_status_checks_policy = false
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        strict_required_status_checks_policy: false,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to required status checks enforcement level" do
      events = subscribe "protected_branch.update_required_status_checks_enforcement_level"
      protected_branch = create(:protected_branch, repository: @repo,
        creator: @user, required_status_checks_enforcement_level: :everyone)

      protected_branch.required_status_checks_enforcement_level_off!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        required_status_checks_enforcement_level: 0,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to dismiss stale reviews on push" do
      events = subscribe "protected_branch.dismiss_stale_reviews"
      protected_branch = create(:protected_branch, repository: @repo,
        creator: @user, pull_request_reviews_enforcement_level: :everyone)

      protected_branch.dismiss_stale_reviews_on_push = true
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        dismiss_stale_reviews_on_push: true,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to require code owners" do
      events = subscribe "protected_branch.update_require_code_owner_review"
      protected_branch = create(:protected_branch, repository: @repo,
        creator: @user, require_code_owner_review: true)

      protected_branch.require_code_owner_review = false
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        require_code_owner_review: false,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to pull request review enforcement levels" do
      events = subscribe "protected_branch.update_pull_request_reviews_enforcement_level"
      protected_branch = create(:protected_branch, repository: @repo,
        creator: @user, pull_request_reviews_enforcement_level: :everyone)

      protected_branch.pull_request_reviews_enforcement_level = :off
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        pull_request_reviews_enforcement_level: 0,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to linear history requirement enforcement levels" do
      events = subscribe "protected_branch.update_linear_history_requirement_enforcement_level"
      protected_branch = create(:protected_branch, repository: @repo, creator: @user,
          linear_history_requirement_enforcement_level: :everyone)

      protected_branch.linear_history_requirement_enforcement_level = :off
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        linear_history_requirement_enforcement_level: 0,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to allow force pushes" do
      events = subscribe "protected_branch.update_allow_force_pushes_enforcement_level"
      protected_branch = create(:protected_branch, repository: @repo, creator: @user,
          block_force_pushes_enforcement_level: :everyone)

      protected_branch.block_force_pushes_enforcement_level = :off
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        allow_force_pushes_enforcement_level: 2,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to allow deletions" do
      events = subscribe "protected_branch.update_allow_deletions_enforcement_level"
      protected_branch = create(:protected_branch, repository: @repo, creator: @user,
          block_deletions_enforcement_level: :everyone)

      protected_branch.block_deletions_enforcement_level = :off
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        allow_deletions_enforcement_level: 2,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to require deployments" do
      events = subscribe "protected_branch.update_required_deployments_enforcement_level"
      protected_branch = create(:protected_branch, repository: @repo, creator: @user,
          block_deletions_enforcement_level: :everyone)

      protected_branch.enable_required_deployments
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        required_deployments_enforcement_level: 1,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to required approving review count" do
      events = subscribe "protected_branch.update_required_approving_review_count"
      protected_branch = create(:protected_branch, repository: @repo,
        creator: @user, pull_request_reviews_enforcement_level: :everyone)

      protected_branch.required_approving_review_count = 3
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        required_approving_review_count: 3,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to admin enforced" do
      events = subscribe "protected_branch.update_admin_enforced"
      protected_branch = create(:protected_branch, repository: @repo,
        creator: @user, admin_enforced: true)

      protected_branch.admin_enforced = false
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        admin_enforced: false,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end


    test "instruments updates to branch name pattern change" do
      events = subscribe "protected_branch.update_name"
      protected_branch = create(:protected_branch, repository: @repo,
        creator: @user, name: "master")

      protected_branch.update(name: "main")
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "main",
        old_name: "master"
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments deletion" do
      events = subscribe "protected_branch.destroy"
      protected_branch = create(:protected_branch,
        repository: @repo,
        creator: @user,
      )

      protected_branch.destroy

      expected_payload = {
        name: "master",
        authorized_actor_names: [],
        required_status_checks_enforcement_level: 0,
        strict_required_status_checks_policy: true,
        dismiss_stale_reviews_on_push: false,
        require_code_owner_review: false,
        require_last_push_approval: false,
        ignore_approvals_from_contributors: false,
        pull_request_reviews_enforcement_level: 0,
        required_approving_review_count: 1,
        signature_requirement_enforcement_level: 0,
        linear_history_requirement_enforcement_level: 0,
        admin_enforced: false,
        allow_force_pushes_enforcement_level: 0,
        allow_deletions_enforcement_level: 0,
        required_deployments_enforcement_level: 0,
        required_review_thread_resolution_enforcement_level: 0,
        merge_queue_enforcement_level: 0,
        enforcement_level: "off",
        lock_branch_enforcement_level: 0,
        lock_allows_fetch_and_merge: false,
        create_protected: false,
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
      }

      assert event = events.pop, "expected event"
      assert_equal "protected_branch.destroy", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments additions and removals of authorized actors" do
      org_admin = create(:user)
      @org.add_member org_admin, action: :admin

      cindy = create(:user)
      @org.add_member(cindy)

      team_cindy = create(:team, organization: @org)
      team_cindy.add_repository @org_repo, :push
      team_cindy.add_member(cindy)

      bob = create(:user)
      @org.add_member(bob)

      team_bob = create(:team, organization: @org)
      team_bob.add_repository @org_repo, :push
      team_bob.add_member(bob)

      events = subscribe "protected_branch.authorized_users_teams"
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")

      protected_branch.replace_authorized_actors(
        user_ids: [org_admin.id, bob.id],
        team_ids: [team_cindy.id],
        integration_ids: [@app.id],
        entry_point: :test_case,
      )

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id,
        name: protected_branch.name,
        authorized_actors: [org_admin.login, bob.login, team_cindy.name, @app.slug],
        authorized_actors_only: true,
      }

      assert_equal 1, events.length, events.inspect
      assert event = events.pop, "expected event"
      assert_equal "protected_branch.authorized_users_teams", event.name

      expected_payload[:authorized_actors].sort!
      event.payload[:authorized_actors].sort!
      assert_same_hash expected_payload, event.payload

      protected_branch.replace_authorized_actors(
        user_ids: [org_admin.id, cindy.id],
        team_ids: [team_bob.id],
        entry_point: :test_case,
      )

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id,
        name: protected_branch.name,
        authorized_actors: [org_admin.login, cindy.login, team_bob.name],
        authorized_actors_only: true,
      }

      assert event = events.pop, "expected event"
      assert_equal "protected_branch.authorized_users_teams", event.name

      expected_payload[:authorized_actors].sort!
      event.payload[:authorized_actors].sort!
      assert_same_hash expected_payload, event.payload
    end

    test "instruments additions and removals of dismissal_restricted_users_teams" do
      org_admin = create(:user)
      @org.add_member org_admin, action: :admin

      cindy = create(:user)
      @org.add_member(cindy)

      team_cindy = create(:team, organization: @org)
      team_cindy.add_repository @org_repo, :push
      team_cindy.add_member(cindy)

      bob = create(:user)
      @org.add_member(bob)

      team_bob = create(:team, organization: @org)
      team_bob.add_repository @org_repo, :push
      team_bob.add_member(bob)

      events = subscribe "protected_branch.dismissal_restricted_users_teams"
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")
      protected_branch.replace_dismissal_restricted_actors(user_ids: [org_admin.id, bob.id],
        team_ids: [team_cindy.id],
        integration_ids: [@app.id]
      )

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id,
        name: protected_branch.name,
        authorized_actors: [org_admin.to_s, bob.to_s, team_cindy.to_s, @app.slug],
        authorized_actors_only: true,
      }

      assert event = events.pop, "expected event"
      assert_equal "protected_branch.dismissal_restricted_users_teams", event.name
      assert_equal expected_payload, event.payload

      protected_branch.replace_dismissal_restricted_actors(user_ids: [org_admin.id, cindy.id], team_ids: [team_bob.id])

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id,
        name: protected_branch.name,
        authorized_actors: [org_admin.to_s, cindy.to_s, team_bob.to_s],
        authorized_actors_only: true,
      }

      assert event = events.pop, "expected event"
      assert_equal "protected_branch.dismissal_restricted_users_teams", event.name
      assert_equal expected_payload, event.payload

      # Clearing restrictions should emit the event with expected new values
      protected_branch.clear_dismissal_restrictions

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id,
        name: protected_branch.name,
        authorized_actors: [],
        authorized_actors_only: false,
      }

      assert event = events.pop, "expected event"
      assert_equal "protected_branch.dismissal_restricted_users_teams", event.name
      assert_equal expected_payload, event.payload

      # Clearing restrictions that makes no changes should not emit an event
      protected_branch.clear_dismissal_restrictions

      refute events.pop, "expected no event"
    end

    test "instruments turning off authorized actors for admins only" do
      events = subscribe "protected_branch.authorized_users_teams"
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], entry_point: :test_case)
      protected_branch.save

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id,
        name: protected_branch.name,
        authorized_actors: [],
        authorized_actors_only: true,
      }

      assert event = events.pop, "expected event"
      assert_equal "protected_branch.authorized_users_teams", event.name
      assert_equal expected_payload, event.payload

      protected_branch.authorized_actors_only = false
      protected_branch.save

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id,
        name: protected_branch.name,
        authorized_actors: [],
        authorized_actors_only: false,
      }

      assert event = events.pop, "expected event"
      assert_equal "protected_branch.authorized_users_teams", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to lock branch enforcement level" do
      events = subscribe "protected_branch.update_lock_branch_enforcement_level"
      protected_branch = create(:protected_branch, repository: @repo, creator: @user)

      protected_branch.enable_lock_branch
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        enforcement_level: "non-admins",
        lock_branch_enforcement_level: 1
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments updates to lock allows fetch and merge" do
      events = subscribe "protected_branch.update_lock_allows_fetch_and_merge"
      protected_branch = create(
        :protected_branch,
        repository: @repo,
        creator: @user,
        lock_branch_enforcement_level: :everyone
      )

      protected_branch.lock_allows_fetch_and_merge = true
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        lock_allows_fetch_and_merge: true
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments turning off lock branch enforcement level and lock allows fetch and merge" do
      enforcement_events = subscribe "protected_branch.update_lock_branch_enforcement_level"
      fetch_and_merge_events = subscribe "protected_branch.update_lock_allows_fetch_and_merge"
      protected_branch = create(
        :protected_branch,
        repository: @repo,
        creator: @user,
        lock_branch_enforcement_level: :everyone,
        lock_allows_fetch_and_merge: true
      )

      protected_branch.clear_lock_branch
      protected_branch.save!

      enforcement_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        enforcement_level: "off",
        lock_branch_enforcement_level: 0
      }

      fetch_and_merge_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        lock_allows_fetch_and_merge: false
      }

      assert event = enforcement_events.pop, "expected event"
      assert_equal enforcement_payload, event.payload
      assert event = fetch_and_merge_events.pop, "expected event"
      assert_equal fetch_and_merge_payload, event.payload
    end

    test "instruments updates to merge queue enforcement level" do
      GitHub.flipper[:merge_queue].enable(@repo)

      events = subscribe "protected_branch.update_merge_queue_enforcement_level"
      protected_branch = create(:protected_branch, repository: @repo)

      protected_branch.enable_merge_queue
      protected_branch.save!

      expected_payload = {
        protected_branch_id: protected_branch.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        name: "master",
        merge_queue_enforcement_level: 1,
      }

      assert event = events.pop, "expected update_merge_queue_enforcement_level event"
      assert_equal expected_payload, event.payload
    end if GitHub.merge_queues_enabled?

    test "instruments updating merge queue settings in Hydro" do
      protected_branch = create(:protected_branch, admin_enforced: true)
      repo = protected_branch.repository
      repo.enable_feature(:merge_queue)
      protected_branch.enable_merge_queue
      protected_branch.save!
      queue = protected_branch.reload_merge_queue
      refute_nil queue
      message = {
        event: :UPDATE,
        repository: Hydro::EntitySerializer.repository(repo),
        queue: Hydro::EntitySerializer.merge_queue(queue),
        entries: [],
        group_entries: [],
        current_merge_group: nil,
        groups: [],
        candidate_groups: [],
      }
      reset_hydro

      protected_branch.merge_queue_settings_hash = {
        max_entries_to_merge: 5,
        check_run_retries_limit: 1,
      }
      protected_branch.save!

      # If the two calls to `protected_branch.save!` happened to span a second boundary, the
      # test was failing. This avoids the flakiness.
      message[:queue][:updated_at] = protected_branch.reload_merge_queue[:updated_at]

      message[:protected_branch] = Hydro::EntitySerializer.protected_branch(protected_branch)
      assert_hydro_published(message, schema: "github.merge_queue.v1.MergeQueueEvent")
    end if GitHub.merge_queues_enabled?

    test "instruments disabling the merge queue in Hydro" do
      @repo.enable_feature(:merge_queue)
      protected_branch = create(:protected_branch, repository: @repo, admin_enforced: true)
      protected_branch.enable_merge_queue
      protected_branch.save!
      queue = protected_branch.reload_merge_queue
      refute_nil queue
      message = {
        event: :DESTROY,
        repository: Hydro::EntitySerializer.repository(@repo),
        queue: Hydro::EntitySerializer.merge_queue(queue),
        entries: [],
        group_entries: [],
        current_merge_group: nil,
        groups: [],
        candidate_groups: [],
      }

      assert_difference(-> { MergeQueue.count }, -1) do
        protected_branch.update!(merge_queue_enforcement_level: :off)
      end

      assert_nil protected_branch.reload_merge_queue
      message[:protected_branch] = Hydro::EntitySerializer.protected_branch(protected_branch)
      assert_hydro_published(message, schema: "github.merge_queue.v1.MergeQueueEvent")
      refute MergeQueue.exists?(queue.id)
    end if GitHub.merge_queues_enabled?
  end

  context "#possible_required_status_contexts_and_integrations" do
    test "avoid IS NULL SQL check for required status checks" do
      callback = lambda do |_name, _start, _ending, _transaction_id, payload|
        sql = payload[:sql]
        if sql =~ /`protected_branch_id` IS NULL/
          raise "We should never perform this unnecessary query: #{sql}"
        end
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        protected_branch = build(:protected_branch, repository: @repo, name: "master")
        protected_branch.possible_required_status_contexts_and_integrations
      end
    end

    test "returns empty Hash when repo has no statuses" do
      protected_branch = build(:protected_branch,
        repository: @repo,
        name: "master",
      )

      assert_equal Hash.new, protected_branch.possible_required_status_contexts_and_integrations
    end

    test "includes contexts from the last week" do
      protected_branch = create(:protected_branch,
        repository: @repo,
        name: "master",
      )
      github_app = create :integration
      create :status, sha: @repo.heads["master"].target_oid, repository: @repo, context: "yesterday", created_at: 1.day.ago, creator: github_app.bot
      create :status, sha: @repo.heads["cr-line-endings"].target_oid, repository: @repo, context: "two-days-ago", created_at: 2.days.ago
      create :status, sha: @repo.heads["cr-line-endings"].commit.parent_oids.first, repository: @repo, context: "six-days-ago", created_at: 6.days.ago
      create :status, sha: @repo.heads["master"].target_oid, repository: @repo, context: "nine-days-ago", created_at: 9.days.ago
      assert_equal(
        { "yesterday" => Set[github_app], "two-days-ago" => Set[], "six-days-ago" => Set[] },
        protected_branch.possible_required_status_contexts_and_integrations,
      )
    end

    test "includes check runs from the last week" do
      protected_branch = create(:protected_branch, repository: @repo, name: "master")

      github_app   = create :integration, default_permissions: { "checks" => :write }
      installation = make_integration_installation integration: github_app, repository: @repo
      check_suite  = create(:check_suite, repository: @repo, github_app: github_app, head_sha: @repo.heads["master"].target_oid)
      check_run1   = create(:check_run, name: "yesterday", check_suite: check_suite, status: :completed, completed_at: 1.day.ago, conclusion: :success)
      check_run2   = create(:check_run, name: "six-days-ago", check_suite: check_suite, status: :completed, completed_at: 6.days.ago, conclusion: :timed_out)
      check_run3   = create(:check_run, name: "eight-days-ago", check_suite: check_suite, status: :completed, completed_at: 8.days.ago, conclusion: :action_required)
      check_run0   = create(:check_run, name: "xxxxxx", display_name: "with_display_name", check_suite: check_suite, status: :completed, conclusion: :success)

      assert_equal(
        { "with_display_name" => Set[github_app], "yesterday" => Set[github_app], "six-days-ago" => Set[github_app] },
        protected_branch.possible_required_status_contexts_and_integrations,
      )
    end

    test "deduplicates statuses" do
      protected_branch = create(:protected_branch,
        repository: @repo,
        name: "master",
        required_status_checks_enforcement_level: :everyone,
      )
      check_suite = create(:check_suite, repository: @repo, head_sha: @repo.heads["master"].target_oid)
      create(:check_run, name: "test", check_suite: check_suite, status: :completed, completed_at: 1.day.ago, conclusion: :success)
      create :status, sha: @repo.heads["master"].target_oid, repository: @repo, context: "test"

      assert_equal(
        { "test" => Set[check_suite.github_app] },
        protected_branch.possible_required_status_contexts_and_integrations,
      )
    end

    test "returns less results based on percentage of time" do
      GitHub.flipper[:possible_required_status_limit].enable(@repo)
      GitHub.flipper[:possible_required_status_limit_value].enable_percentage_of_time(1.01)

      protected_branch = build(:protected_branch,
        repository: @repo,
        name: "master",
      )

      github_app = create :integration

      15.times do |i|
        create :status, sha: @repo.heads["master"].target_oid, repository: @repo, context: i.to_s, created_at: 1.day.ago, creator: github_app.bot
      end

      assert_equal 9, protected_branch.possible_required_status_contexts_and_integrations.size
    end
  end

  context "# instrumenting branch protection allowances" do
    test "instruments updates to allow force pushes" do
      org_admin = create(:user)
      @org.add_member org_admin, action: :admin

      cindy = create(:user)
      @org.add_member(cindy)

      team_cindy = create(:team, organization: @org)
      team_cindy.add_repository @org_repo, :push
      team_cindy.add_member(cindy)

      bob = create(:user)
      @org.add_member(bob)

      team_bob = create(:team, organization: @org)
      team_bob.add_repository @org_repo, :push
      team_bob.add_member(bob)

      events = subscribe "protected_branch.branch_allowances"
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")
      protected_branch.replace_branch_actor_allowances(:force_push, user_ids: [org_admin.id, bob.id], team_ids: [team_cindy.id], integration_ids: [@app.id])

      expected_payload = {
        name: protected_branch.name,
        authorized_actors: [org_admin.to_s, bob.to_s, team_cindy.to_s, @app.slug],
        policy: :force_push,
        protected_branch_id: protected_branch.id,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id,
      }

      assert event = events.pop, "expected event"
      assert_equal "protected_branch.branch_allowances", event.name

      expected_payload[:authorized_actors].sort!
      event.payload[:authorized_actors].sort!
      assert_same_hash expected_payload, event.payload
    end
  end

  context "#possible_required_deployment_environments" do
    test "includes de-duplicated deployment environments" do
      protected_branch = build(:protected_branch, repository: @repo, name: "master")

      sha = @repo.default_branch_ref.target_oid
      @repo.deployments.create!(sha: sha, environment: "production", creator: @repo.user)
      @repo.deployments.create!(sha: sha, environment: "production", creator: @repo.user)
      @repo.deployments.create!(sha: sha, environment: "staging", creator: @repo.user)

      assert_same_elements %w[production staging], protected_branch.possible_required_deployment_environments

      assert_same_elements %w[production staging], protected_branch.possible_required_deployment_environments
    end

    test "returns less results based on percentage of time" do
      GitHub.flipper[:possible_required_deployments_limit].enable(@repo)
      GitHub.flipper[:possible_required_deployments_limit_value].enable_percentage_of_time(1.01)

      protected_branch = build(:protected_branch,
        repository: @repo,
        name: "master",
      )

      sha = @repo.default_branch_ref.target_oid
      15.times do |i|
        @repo.deployments.create!(sha: sha, environment: i.to_s, creator: @repo.user)
      end

      assert_equal 10, protected_branch.possible_required_deployment_environments.size
    end
  end

  context "#authorized_actors" do
    test "is empty by default" do
      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      assert_equal [], protected_branch.authorized_actors
    end

    test "is empty if authorized_actors_only is false" do
      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      assert_equal [], protected_branch.authorized_actors
      protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)

      refute_empty protected_branch.authorized_actors
      protected_branch.authorized_actors_only = false
      protected_branch.save
      assert_empty protected_branch.authorized_actors
    end
  end

  context "#authorized?" do
    test "Admins are always authorized" do
      repo_admin = create(:user)
      @org_repo.add_member(repo_admin, action: :admin)

      org_admin = create(:user)
      @org.add_member(org_admin, action: :admin)

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"

      assert protected_branch.authorized?(@org_repo_team_member), "With no authorized users specified, member of team with admin permission isn't authorized."
      assert protected_branch.authorized?(repo_admin), "With no authorized users specified, repo admin isn't authorized."
      assert protected_branch.authorized?(org_admin), "With no authorized users specified, org admin isn't authorized."

      user = create(:user)
      @org_repo.add_member(user, action: :write)
      protected_branch.replace_authorized_actors(user_ids: [user.id], team_ids: [], entry_point: :test_case)

      assert protected_branch.authorized?(@org_repo_team_member), "Member of team with admin permission isn't authorized."
      assert protected_branch.authorized?(repo_admin), "Repo admin isn't authorized."
      assert protected_branch.authorized?(org_admin), "Org admin isn't authorized."
      assert protected_branch.authorized?(user), "Repo collaborator with write access on the authorized user list is not authorized with push restrictions, but should be."
    end

    test "Maintainers are always authorized" do
      repo_maintainer = create(:user)
      @org_repo.add_member repo_maintainer, action: :maintain

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"

      assert protected_branch.authorized?(repo_maintainer), "Repo maintainer is not authorized with no push restrictions, but should be."

      user = create(:user)
      @org_repo.add_member(user, action: :write)
      protected_branch.replace_authorized_actors(user_ids: [user.id], team_ids: [], entry_point: :test_case)

      assert protected_branch.authorized?(repo_maintainer), "Repo maintainer is not authorized with push restrictions, but should be."
      assert protected_branch.authorized?(user), "Repo collaborator with write access on the authorized user list is not authorized with push restrictions, but should be."
    end

    test "Integration installations with administration write are always authorized" do
      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [@org.admins.first.id], team_ids: [], entry_point: :test_case)

      assert protected_branch.authorized?(@installation.bot), "Bot with repository administration is not authorized with no push restrictions, but should be."
    end

    test "Integration installations not installed on correct target are not authorized" do
      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [@org.admins.first.id], team_ids: [], entry_point: :test_case)

      user_with_installation = create(:user)
      repo_with_installation = create :repository, owner: user_with_installation

      installation = make_integration_installation(
        target: user_with_installation,
        permissions: {
          "administration" => :write
        }
      )
      refute protected_branch.authorized?(installation.bot), "Bot with repository administration not installed on repo is authorized, but shouldn't be."
    end

    test "Users, teams and integrations can be authorized" do
      authorized_team_member = create(:user)
      authorized_team = create(:team, organization: @org)
      authorized_team.add_member authorized_team_member
      authorized_team.add_repository @org_repo, :push

      unauthorized_team_member = create(:user)
      unauthorized_team = create(:team, organization: @org)
      unauthorized_team.add_member unauthorized_team_member
      unauthorized_team.add_repository @org_repo, :push

      authorized_user = create(:user)
      @org_repo.add_member(authorized_user, action: :write)

      unauthorized_user = create(:user)
      @org_repo.add_member(unauthorized_user, action: :write)

      other_app = create(:integration)
      unauthorized_integration_installation = make_integration_installation(
        integration: other_app,
        repository: @org_repo,
        permissions: { "contents" => :write },
      )

      unauthorized_bot = unauthorized_integration_installation.bot

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [authorized_user.id], team_ids: [authorized_team.id],
                                                          integration_ids: [@app.id], entry_point: :test_case)

      assert protected_branch.authorized?(authorized_team_member), "Member of an authorized team isn't authorized."
      assert protected_branch.authorized?(authorized_user), "Authorized user isn't authorized."
      assert protected_branch.authorized?(@installation.bot), "Authorized bot isn't authorized."

      refute protected_branch.authorized?(unauthorized_team_member), "Member of an unauthorized team is authorized."
      refute protected_branch.authorized?(unauthorized_user), "Unauthorized user is authorized."
      refute protected_branch.authorized?(unauthorized_bot), "Unauthorized bot is authorized."
    end

    test "scoped integration installations with authorized parent installations are also authorized" do
      authorized_scoped_installation = make_scoped_integration_installation(
        parent: @installation, repositories: [@org_repo],
      )
      authorized_scoped_bot = authorized_scoped_installation.bot

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], integration_ids: [@app.id], entry_point: :test_case)

      assert protected_branch.authorized?(authorized_scoped_bot), "Authorized scoped bot isn't authorized."
    end

    test "scoped integration installations without repository write are not authorized" do
      scoped_installation = make_scoped_integration_installation(
        parent: @installation, repositories: [@org_repo], permissions: { "contents" => :read },
      )
      scoped_bot = scoped_installation.bot

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], integration_ids: [@app.id], entry_point: :test_case)

      refute protected_branch.authorized?(scoped_bot), "Unauthorized bot is authorized."
    end

    test "nested team members get authorization" do
      parent_team = create(:team, organization: @org, privacy: :closed)
      parent_team.add_repository @org_repo, :admin
      parent_team_member = create(:user)
      parent_team.add_member(parent_team_member)

      child_team = create(:team, organization: @org, parent_team_id: parent_team.id, privacy: :closed)
      child_team_member = create(:user)
      child_team.add_member(child_team_member)

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [parent_team.id], entry_point: :test_case)

      assert protected_branch.authorized?(child_team_member)
    end

    test "can added a nested team to authorized_teams" do
      parent_team = create(:team, organization: @org, privacy: :closed)
      parent_team.add_repository @org_repo, :admin
      child_team = create(:team, organization: @org, parent_team_id: parent_team.id, privacy: :closed)

      protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [child_team.id], entry_point: :test_case)

      assert_equal [child_team], protected_branch.authorized_teams
    end

    test "nested team members get authorization on private repos" do
      parent_team = create(:team, organization: @org, privacy: :closed)
      parent_team.add_repository @private_org_repo, :admin

      child_team = create(:team, organization: @org, parent_team_id: parent_team.id, privacy: :closed)
      child_team_member = create(:user)
      child_team.add_member(child_team_member)

      protected_branch = create :protected_branch, repository: @private_org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [child_team.id], entry_point: :test_case)

      assert protected_branch.authorized?(child_team_member)
    end

    test "can add a nested team to private repo's authorized_teams" do
      parent_team = create(:team, organization: @org, privacy: :closed)
      parent_team.add_repository @private_org_repo, :admin
      child_team = create(:team, organization: @org, parent_team_id: parent_team.id, privacy: :closed)

      protected_branch = create :protected_branch, repository: @private_org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [child_team.id], entry_point: :test_case)

      assert_equal [child_team], protected_branch.authorized_teams
    end

    test "Users that lose access to a repo are not authorized" do
      user = create(:user)
      @org_repo.add_member user, action: :write

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors user_ids: [user.id], team_ids: [], entry_point: :test_case

      @org_repo.remove_member user

      refute protected_branch.authorized?(user), "User removed from the org is still authorized."
      assert_empty protected_branch.authorized_users
      assert_empty protected_branch.authorized_actors
    end

    test "Teams that lose write access to a repo are not authorized" do
      team = create(:team, organization: @org, privacy: :closed)
      team.add_repository(@org_repo, :push)

      team_member = create(:user)
      team.add_member(team_member)

      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")
      protected_branch.replace_authorized_actors user_ids: [], team_ids: [team.id], entry_point: :test_case

      assert protected_branch.authorized?(team_member), "Team member should be authorized (but is not)."
      assert_equal [team], protected_branch.authorized_teams
      assert_equal [team], protected_branch.authorized_actors

      # Reload repository.protected_branches relation
      @org_repo.reload

      team.remove_repository @org_repo
      team.add_repository @org_repo, :read

      refute protected_branch.authorized?(team_member), "Team member should not be authorized (but is)."
      assert_empty protected_branch.authorized_teams
      assert_empty protected_branch.authorized_actors
    end

    test "IntegrationInstallations with contents write permission are not authorized when push restrictions are enabled" do
      installation = make_integration_installation(repository: @org_repo, permissions: { "contents" => :write })
      bot = installation.bot

      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")

      assert protected_branch.authorized?(bot), "IntegrationInstallation should be authorized (but is *NOT*)."

      protected_branch.replace_authorized_actors user_ids: [@org.admins.first.id], team_ids: [], entry_point: :test_case

      refute protected_branch.authorized?(bot), "IntegrationInstallation should *NOT* be authorized (but is)."
    end

    test "IntegrationInstallations that are uninstalled are not authorized" do
      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors user_ids: [], team_ids: [], integration_ids: [@app.id], entry_point: :test_case

      assert protected_branch.authorized?(@installation.bot), "Bot's integration installation should be authorized but isn't"
      assert_equal [@installation.id], protected_branch.authorized_integration_installation_ids
      assert_equal [@installation], protected_branch.authorized_integration_installations

      perform_enqueued_jobs only: [DestroyDependentRecordsJob] do
        @installation.uninstall(actor: @org_repo.owner)
      end

      protected_branch = ProtectedBranch.find(protected_branch.id)
      refute protected_branch.authorized?(@installation.bot), "Bot's integration installation removed from the repo is still authorized."
      assert_empty protected_branch.authorized_integration_installation_ids
      assert_empty protected_branch.authorized_integration_installations
    end

    test "IntegrationInstallations that are removed from the repository are not authorized" do
      other_org_repo = create(:repository, owner: @org)
      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors user_ids: [], team_ids: [], integration_ids: [@app.id], entry_point: :test_case

      assert protected_branch.authorized?(@installation.bot), "Bot's integration installation should be authorized but isn't"
      assert_equal [@installation.id], protected_branch.authorized_integration_installation_ids
      assert_equal [@installation], protected_branch.authorized_integration_installations

      @installation.edit(
        editor: @org_repo.owner,
        repositories: [other_org_repo],
        entry_point: :test_case,
      )

      protected_branch = ProtectedBranch.find(protected_branch.id)
      refute protected_branch.authorized?(@installation.bot), "Bot's integration installation removed from the repo is still authorized."
      assert_empty protected_branch.authorized_integration_installation_ids
      assert_empty protected_branch.authorized_integration_installations
    end
  end

  context "#has_authorized_actors" do
    test "always returns false for personal repos" do
      protected_branch = create(:protected_branch, repository: @repo)
      protected_branch.update_column(:authorized_actors_only, true)
      assert protected_branch.authorized_actors_only
      refute protected_branch.has_authorized_actors?
    end
  end

  context "#authorized_actors_only" do
    context "when authorized_actors_only is set to false" do
      test "does not immediately clear the abilities, does so in the after_save callback" do
        protected_branch = create(:protected_branch, repository: @org_repo)
        protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [@org_repo_team.id],
                                                            integration_ids: [@app.id], entry_point: :test_case)

        assert protected_branch.authorized_actors_only
        protected_branch.authorized_actors_only = false

        refute_empty authorized_users(protected_branch), "Authorized User has been deleted (but should NOT be)"
        refute_empty authorized_teams(protected_branch), "Authorized Team has been deleted (but should NOT be)"
        refute_empty authorized_integration_installations(protected_branch), "Authorized IntegrationInstallation has been deleted (but should NOT be)"

        assert assert protected_branch.save

        assert_empty authorized_users(protected_branch), "User is authorized (but should NOT be)"
        assert_empty authorized_teams(protected_branch), "Team is authorized (but should NOT be)"
        assert_empty authorized_integration_installations(protected_branch), "IntegrationInstallation is authorized (but should NOT be)"
      end

      test "rolls back cleared abilities when clearing permissions fail" do
        protected_branch = create(:protected_branch, repository: @org_repo)
        protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [@org_repo_team.id],
                                                            integration_ids: [@app.id], entry_point: :test_case)

        Permissions::Service.stubs(:revoke_permissions_granted_on_subject).raises(ActiveRecord::StatementInvalid)

        assert protected_branch.authorized_actors_only
        protected_branch.authorized_actors_only = false

        assert_raises ActiveRecord::StatementInvalid do
          protected_branch.save
        end

        refute_empty authorized_users(protected_branch), "Authorized User has been deleted (but should NOT be)"
        refute_empty authorized_teams(protected_branch), "Authorized Team has been deleted (but should NOT be)"
        refute_empty authorized_integration_installations(protected_branch), "Authorized IntegrationInstallation has been deleted (but should NOT be)"
      end

      test "Merge queue bot is authorized" do
        protected_branch = create :protected_branch, repository: @org_repo, name: "master"
        protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [@org_repo_team.id],
          integration_ids: [@app.id])
        protected_branch.merge_queue_enforcement_level_everyone!

        assert protected_branch.authorized?(GitHub.merge_queue_bot), "Merge queue bot is not authorized, but should be."
      end
    end

    context "when authorized_actors_only set to true" do
      test "an error is raised" do
        protected_branch = create(:protected_branch, repository: @org_repo)
        refute protected_branch.authorized_actors_only
        assert_raises NotImplementedError do
          protected_branch.authorized_actors_only = true
        end
      end
    end
  end

  context "archive and restore" do
    test "archives protected branches" do
      prot_branch = create :protected_branch, repository: @repo, name: "master"
      assert_equal 1, @repo.protected_branches.count
      only = [DestroyDependentRecordsJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) do
        @repo.remove(@user)
        # protected branches are not destroyed until the repo is purged, so do that now
        @repo.purge(synchronous: true)
      end

      refute ProtectedBranch.exists?(prot_branch.id)
    end

    test "restores protected branches" do
      prot_branch = create :protected_branch, repository: @repo, name: "master"
      prot_branch.replace_status_contexts(%w[master foo])

      assert_equal 1, @repo.protected_branches.count
      assert_equal 2, prot_branch.required_status_checks.count

      only = [DestroyDependentRecordsJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) do
        @repo.remove(@user)
      end
      refute Repository.find_by(id: @repo.id, active: true)

      only = [AddToSearchIndexJob]
      restored_repo = perform_enqueued_jobs(only: only) do
        Repository.restore(@repo.id)
      end
      assert_equal 1, restored_repo.protected_branches.count

      restored_prot_branch = restored_repo.protected_branches.first
      assert_equal 2, restored_prot_branch.required_status_checks.count

      assert_equal prot_branch, restored_prot_branch
    end
  end

  context "#can_override_status_checks?" do
    test "returns true when required_status_checks_enforcement_level is off" do
      branch = create(:protected_branch, repository: @repo, name: "master", required_status_checks_enforcement_level: :off)
      branch.replace_status_contexts(%w[master foo])
      assert branch.can_override_status_checks?(actor: @user)
    end

    test "returns true for admins when required_status_checks_enforcement_level is non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", required_status_checks_enforcement_level: :non_admins)
      branch.replace_status_contexts(%w[master foo])
      assert branch.can_override_status_checks?(actor: @user), "Admin user can't override status checks"
    end

    test "returns true for bots with administration permission when required_status_checks_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @org_repo, name: "master", required_status_checks_enforcement_level: :non_admins)
      branch.replace_status_contexts(%w[master foo])
      assert branch.can_override_status_checks?(actor: @installation.bot), "Admin bot can't override status checks"
    end

    test "returns false for non-admins when required_status_checks_enforcement_level is non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", required_status_checks_enforcement_level: :non_admins)
      branch.replace_status_contexts(%w[master foo])
      refute branch.can_override_status_checks?(actor: create(:user))
    end

    test "returns false for admins when required_status_checks_enforcement_level is everyone" do
      branch = create(:protected_branch, repository: @repo, name: "master", required_status_checks_enforcement_level: :everyone)
      branch.replace_status_contexts(%w[master foo])
      refute branch.can_override_status_checks?(actor: @user)
    end
  end

  context "#can_override_review_policy?" do
    test "returns true when pull_request_reviews_enforcement_level==off" do
      branch = create(:protected_branch, repository: @repo, name: "master", pull_request_reviews_enforcement_level: :off)
      assert branch.can_override_review_policy?(actor: @user)
    end

    test "returns true for admins when pull_request_reviews_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", pull_request_reviews_enforcement_level: :non_admins)
      assert branch.can_override_review_policy?(actor: @user)
    end

    test "returns true for bots with administration permission when pull_request_reviews_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @org_repo, name: "master", pull_request_reviews_enforcement_level: :non_admins)
      assert branch.can_override_review_policy?(actor: @installation.bot), "Admin bot can't override review policy"
    end

    test "returns false for non-admins when pull_request_reviews_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", pull_request_reviews_enforcement_level: :non_admins)
      refute branch.can_override_review_policy?(actor: create(:user))
    end

    test "returns false for admins when pull_request_reviews_enforcement_level==everyone" do
      branch = create(:protected_branch, repository: @repo, name: "master", pull_request_reviews_enforcement_level: :everyone)
      refute branch.can_override_review_policy?(actor: @user)
    end

    test "returns true for teams and users that can bypass pull requests" do
      teammate = create(:user)
      team = create(:team, organization: @org)
      team.add_member(teammate)
      team.add_repository @org_repo, :admin
      @org_repo.add_member(@user, action: :write)
      protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
      refute protected_branch.can_override_review_policy?(actor: teammate)
      refute protected_branch.can_override_review_policy?(actor: @user)

      protected_branch.replace_branch_actor_allowances(:pull_request, user_ids: [@user.id], team_ids: [team.id], integration_ids: [])
      assert protected_branch.can_override_review_policy?(actor: teammate)
      assert protected_branch.can_override_review_policy?(actor: @user)
    end
  end

  context "#can_override_required_signatures?" do
    test "returns true when signature_requirement_enforcement_level==off" do
      branch = create(:protected_branch, repository: @repo, name: "master", signature_requirement_enforcement_level: :off)
      assert branch.can_override_required_signatures?(actor: @user)
    end

    test "returns true for admins when signature_requirement_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", signature_requirement_enforcement_level: :non_admins)
      assert branch.can_override_required_signatures?(actor: @user)
    end

    test "returns true for bots with administration permission when signature_requirement_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @org_repo, name: "master", signature_requirement_enforcement_level: :non_admins)
      assert branch.can_override_required_signatures?(actor: @installation.bot), "Admin bot can't override required signatures"
    end

    test "returns false for non-admins when signature_requirement_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", signature_requirement_enforcement_level: :non_admins)
      refute branch.can_override_required_signatures?(actor: create(:user))
    end

    test "returns false for admins when signature_requirement_enforcement_level==everyone" do
      branch = create(:protected_branch, repository: @repo, name: "master", signature_requirement_enforcement_level: :everyone)
      refute branch.can_override_required_signatures?(actor: @user)
    end
  end

  context "#can_override_required_linear_history?" do
    test "returns true when merge commit blocking is off" do
      branch = create(:protected_branch, repository: @repo, name: "master", linear_history_requirement_enforcement_level: :off)
      assert branch.can_override_required_linear_history?(actor: @user)
    end

    test "returns true for admins when enforcement level is non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", linear_history_requirement_enforcement_level: :non_admins)
      assert branch.can_override_required_linear_history?(actor: @user)
    end

    test "returns true for bots with administration permission when enforcement level is non_admins" do
      branch = create(:protected_branch, repository: @org_repo, name: "master", linear_history_requirement_enforcement_level: :non_admins)
      assert branch.can_override_required_linear_history?(actor: @installation.bot), "Admin bot can't override required linear history"
    end

    test "returns false for non-admins when enforcement level is non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", linear_history_requirement_enforcement_level: :non_admins)
      refute branch.can_override_required_linear_history?(actor: create(:user))
    end

    test "returns false for admins when enforcement level is everyone" do
      branch = create(:protected_branch, repository: @repo, name: "master", linear_history_requirement_enforcement_level: :everyone)
      refute branch.can_override_required_linear_history?(actor: @user)
    end
  end

  context "#strict_required_status_checks_policy" do
    test "returns value when feature is enabled" do
      branch = create(:protected_branch, repository: @repo, name: "master", required_status_checks_enforcement_level: :everyone,
          strict_required_status_checks_policy: false)

      refute_predicate branch, :strict_required_status_checks_policy?

      branch.update_column(:strict_required_status_checks_policy, true)

      assert_predicate branch, :strict_required_status_checks_policy?
    end
  end

  context "#review_dismissable_by?" do
    test "returns true for teams and users that can dismiss" do
      teammate = create(:user)
      team = create(:team, organization: @org)
      team.add_member(teammate)
      team.add_repository @org_repo, :admin
      @org_repo.add_member(@user, action: :write)
      protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
      refute protected_branch.review_dismissable_by?(teammate)
      refute protected_branch.review_dismissable_by?(@user)

      protected_branch.replace_dismissal_restricted_actors(user_ids: [@user.id], team_ids: [team.id])
      assert protected_branch.review_dismissable_by?(teammate)
      assert protected_branch.review_dismissable_by?(@user)
    end

    test "returns true for admins if admins not enforced" do
      protected_branch = create(:protected_branch, repository: @org_repo)
      assert protected_branch.review_dismissable_by?(@org_admin), "Admin user can't dimiss review"
      assert protected_branch.review_dismissable_by?(@installation.bot), "Admin bot can't dimiss review"

      protected_branch.pull_request_reviews_enforcement_level = :everyone
      protected_branch.save!

      assert protected_branch.admin_enforced?
      refute protected_branch.review_dismissable_by?(@org_admin), "Admin user can dimiss review"
      refute protected_branch.review_dismissable_by?(@installation.bot), "Admin bot can dimiss review"
    end

    test "returns true for members of a team" do
      team = create(:team, organization: @org)
      team.add_repository @org_repo, :admin
      team_member = create(:user)
      team.add_member(team_member)

      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_dismissal_restricted_actors(user_ids: [], team_ids: [team.id])

      assert protected_branch.review_dismissable_by?(team_member)
    end

    test "returns false for members of a team with only read access" do
      team = create(:team, organization: @org)
      team.add_repository @org_repo, :read
      team_member = create(:user)
      team.add_member(team_member)

      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_dismissal_restricted_actors(user_ids: [], team_ids: [team.id])

      refute protected_branch.review_dismissable_by?(team_member)
      refute_nil protected_branch.review_dismissable_by?(team_member)
    end

    test "returns true for members of parent and child teams when parent team has access" do
      parent_team = create(:team, organization: @org, privacy: :closed)
      parent_team.add_repository @org_repo, :push
      parent_team_member = create(:user)
      parent_team.add_member(parent_team_member)

      child_team = create(:team, organization: @org, parent_team_id: parent_team.id, privacy: :closed)
      child_team_member = create(:user)
      child_team.add_member(child_team_member)

      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_dismissal_restricted_actors(user_ids: [], team_ids: [parent_team.id])

      assert protected_branch.review_dismissable_by?(parent_team_member)
      assert protected_branch.review_dismissable_by?(child_team_member)
    end

    test "calling dismissal_restricted_users/teams/integration_installations returns a list of users, teams, or apps" do
      teammate = create(:user)
      team = create(:team, organization: @org)
      team.add_member(teammate)
      team.add_repository @org_repo, :admin
      @org_repo.add_member(@user, action: :write)
      protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
      refute protected_branch.review_dismissable_by?(teammate)
      refute_nil protected_branch.review_dismissable_by?(teammate)
      refute protected_branch.review_dismissable_by?(@user)
      refute_nil protected_branch.review_dismissable_by?(@user)
      refute protected_branch.review_dismissable_by?(@installation.bot)
      refute_nil protected_branch.review_dismissable_by?(@installation.bot)

      protected_branch.replace_dismissal_restricted_actors(user_ids: [@user.id], team_ids: [team.id], integration_ids: [@installation.integration.id])

      assert_equal [@user], protected_branch.dismissal_restricted_users
      assert_equal [team], protected_branch.dismissal_restricted_teams
      assert_equal [@installation], protected_branch.dismissal_restricted_integration_installations
    end

    test "can added a nested team to dismissal_restricted_teams" do
      parent_team = create(:team, organization: @org, privacy: :closed)
      parent_team.add_repository @org_repo, :admin
      child_team = create(:team, organization: @org, parent_team_id: parent_team.id, privacy: :closed)

      protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
      protected_branch.replace_dismissal_restricted_actors(user_ids: [], team_ids: [child_team.id])

      assert_equal [child_team], protected_branch.dismissal_restricted_teams
    end
  end

  context "#branch_actor_allowances" do
    test "calling branch_actor_allowance_users/teams/integration_installations returns a list of users, teams, or apps" do
      teammate = create(:user)
      team = create(:team, organization: @org)
      team.add_member(teammate)
      team.add_repository @org_repo, :admin
      @org_repo.add_member(@user, action: :write)
      protected_branch = create(:protected_branch, repository: @org_repo)
      refute protected_branch.has_branch_actor_allowance?(:pull_request, actor: teammate)
      refute_nil protected_branch.has_branch_actor_allowance?(:pull_request, actor: teammate)
      refute protected_branch.has_branch_actor_allowance?(:pull_request, actor: @user)
      refute_nil protected_branch.has_branch_actor_allowance?(:pull_request, actor: @user)
      refute protected_branch.has_branch_actor_allowance?(:pull_request, actor: @installation.bot)
      refute_nil protected_branch.has_branch_actor_allowance?(:pull_request, actor: @installation.bot)

      protected_branch.replace_branch_actor_allowances(:pull_request, user_ids: [@user.id], team_ids: [team.id], integration_ids: [@installation.integration.id])

      assert_equal [@user], protected_branch.branch_actor_allowance_users(:pull_request)
      assert_equal [team], protected_branch.branch_actor_allowance_teams(:pull_request)
      assert_equal [@installation], protected_branch.branch_actor_allowance_integration_installations(:pull_request)
    end
  end

  context "admin_enforced=" do
    test "setting admin_enforced true sets levels" do
      protected_branch = build :protected_branch, repository: @repo
      protected_branch.pull_request_reviews_enforcement_level_non_admins!
      protected_branch.required_status_checks_enforcement_level_non_admins!
      protected_branch.signature_requirement_enforcement_level_non_admins!
      protected_branch.linear_history_requirement_enforcement_level_non_admins!
      protected_branch.merge_queue_enforcement_level_non_admins!
      protected_branch.lock_branch_enforcement_level_non_admins!
      assert protected_branch.pull_request_reviews_enabled?
      assert protected_branch.required_status_checks_enabled?
      assert protected_branch.required_signatures_enabled?
      assert protected_branch.required_linear_history_enabled?
      assert protected_branch.merge_queue_enabled?
      assert protected_branch.lock_branch_enabled?

      protected_branch.admin_enforced = true

      assert_predicate protected_branch, :pull_request_reviews_enforcement_level_everyone?
      assert_predicate protected_branch, :required_status_checks_enforcement_level_everyone?
      assert_predicate protected_branch, :signature_requirement_enforcement_level_everyone?
      assert_predicate protected_branch, :linear_history_requirement_enforcement_level_everyone?
      assert_predicate protected_branch, :merge_queue_enforcement_level_everyone?
      assert_predicate protected_branch, :lock_branch_enforcement_level_everyone?
      assert protected_branch.admin_enforced
    end

    test "setting admin_enforced true only sets levels if enabled" do
      protected_branch = build :protected_branch, repository: @repo
      protected_branch.pull_request_reviews_enforcement_level_non_admins!
      protected_branch.required_status_checks_enforcement_level_off!
      protected_branch.signature_requirement_enforcement_level_off!
      protected_branch.linear_history_requirement_enforcement_level_off!
      protected_branch.merge_queue_enforcement_level_off!
      protected_branch.lock_branch_enforcement_level_off!
      assert_predicate protected_branch, :pull_request_reviews_enabled?
      refute_predicate protected_branch, :required_status_checks_enabled?
      refute_predicate protected_branch, :required_signatures_enabled?
      refute_predicate protected_branch, :required_linear_history_enabled?
      refute_predicate protected_branch, :merge_queue_enabled?
      refute_predicate protected_branch, :lock_branch_enabled?

      protected_branch.admin_enforced = true

      assert_predicate protected_branch, :pull_request_reviews_enforcement_level_everyone?
      assert_predicate protected_branch, :required_status_checks_enforcement_level_off?
      assert_predicate protected_branch, :signature_requirement_enforcement_level_off?
      assert_predicate protected_branch, :linear_history_requirement_enforcement_level_off?
      assert_predicate protected_branch, :merge_queue_enforcement_level_off?
      assert_predicate protected_branch, :lock_branch_enforcement_level_off?

      assert protected_branch.admin_enforced
    end

    test "setting admin_enforced false sets levels" do
      protected_branch = build :protected_branch, repository: @repo
      protected_branch.pull_request_reviews_enforcement_level_everyone!
      protected_branch.required_status_checks_enforcement_level_everyone!
      protected_branch.signature_requirement_enforcement_level_everyone!
      protected_branch.linear_history_requirement_enforcement_level_everyone!
      protected_branch.merge_queue_enforcement_level_everyone!
      protected_branch.lock_branch_enforcement_level_everyone!
      assert_predicate protected_branch, :pull_request_reviews_enabled?
      assert_predicate protected_branch, :required_status_checks_enabled?
      assert_predicate protected_branch, :required_signatures_enabled?
      assert_predicate protected_branch, :required_linear_history_enabled?
      assert_predicate protected_branch, :merge_queue_enabled?
      assert_predicate protected_branch, :lock_branch_enabled?

      protected_branch.admin_enforced = false

      assert_predicate protected_branch, :pull_request_reviews_enforcement_level_non_admins?
      assert_predicate protected_branch, :required_status_checks_enforcement_level_non_admins?
      assert_predicate protected_branch, :signature_requirement_enforcement_level_non_admins?
      assert_predicate protected_branch, :linear_history_requirement_enforcement_level_non_admins?
      assert_predicate protected_branch, :merge_queue_enforcement_level_non_admins?
      assert_predicate protected_branch, :lock_branch_enforcement_level_non_admins?
      refute protected_branch.admin_enforced
    end

    test "blocked force pushes and branch deletions are unchanged" do
      protected_branch = build(:protected_branch,
        block_force_pushes_enforcement_level: :everyone,
        block_deletions_enforcement_level: :everyone,
        admin_enforced: true)

      assert_predicate protected_branch, :block_force_pushes_enabled?
      assert_predicate protected_branch, :block_deletions_enabled?

      protected_branch.admin_enforced = false
      assert_predicate protected_branch, :block_force_pushes_enforcement_level_everyone?
      assert_predicate protected_branch, :block_deletions_enforcement_level_everyone?
      assert_predicate protected_branch, :block_force_pushes_enabled?
      assert_predicate protected_branch, :block_deletions_enabled?

      protected_branch.admin_enforced = true
      assert_predicate protected_branch, :block_force_pushes_enforcement_level_everyone?
      assert_predicate protected_branch, :block_deletions_enforcement_level_everyone?
      assert_predicate protected_branch, :block_force_pushes_enabled?
      assert_predicate protected_branch, :block_deletions_enabled?
    end
  end

  context "clear_required_pull_request_reviews" do
    test "clears dismissal restrictions" do
      @org_repo.add_member(@user, action: :write)
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master", pull_request_reviews_enforcement_level: :everyone)
      protected_branch.replace_dismissal_restricted_actors(user_ids: [@user.id], team_ids: [])

      assert protected_branch.pull_request_reviews_enabled?
      assert protected_branch.authorized_dismissal_actors_only?
      assert_equal [@user], protected_branch.dismissal_restricted_users

      protected_branch.clear_required_pull_request_reviews

      refute protected_branch.pull_request_reviews_enabled?
      refute protected_branch.authorized_dismissal_actors_only?
      assert_equal [], protected_branch.dismissal_restricted_users
    end

    test "clears dismiss stale reviews on push" do
      protected_branch = create(:protected_branch, repository: @repo, name: "master", pull_request_reviews_enforcement_level: :non_admins, dismiss_stale_reviews_on_push: true)

      assert protected_branch.pull_request_reviews_enabled?
      assert protected_branch.dismiss_stale_reviews_on_push?

      protected_branch.clear_required_pull_request_reviews

      refute protected_branch.pull_request_reviews_enabled?
      refute protected_branch.dismiss_stale_reviews_on_push?
    end

    test "clears code owner required" do
      protected_branch = create(:protected_branch, repository: @repo, name: "master", pull_request_reviews_enforcement_level: :non_admins, require_code_owner_review: true)

      assert protected_branch.pull_request_reviews_enabled?
      assert protected_branch.require_code_owner_review?

      protected_branch.clear_required_pull_request_reviews

      refute protected_branch.pull_request_reviews_enabled?
      refute protected_branch.require_code_owner_review?
    end

    test "clear require last push approval" do
      protected_branch = create(:protected_branch, repository: @repo, name: "master", pull_request_reviews_enforcement_level: :non_admins, require_last_push_approval: true)

      assert protected_branch.pull_request_reviews_enabled?
      assert protected_branch.require_last_push_approval?

      protected_branch.clear_required_pull_request_reviews

      refute protected_branch.pull_request_reviews_enabled?
      refute protected_branch.require_last_push_approval?
    end

    test "clears required approving reviews count" do
      protected_branch = create(:protected_branch, repository: @repo, name: "master", pull_request_reviews_enforcement_level: :non_admins, required_approving_review_count: 3)

      assert protected_branch.pull_request_reviews_enabled?
      assert_equal 3, protected_branch.required_approving_review_count

      protected_branch.clear_required_pull_request_reviews

      refute protected_branch.pull_request_reviews_enabled?
      assert_equal 1, protected_branch.required_approving_review_count
    end
  end

  context "#update_restrictions" do
    context "when passing nothing" do
      test "should keep users as-is" do
        user = create(:user)
        @org_repo.add_member(user, action: :write)
        protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
        protected_branch.replace_authorized_actors(user_ids: [user.id], team_ids: [], entry_point: :test_case)
        assert_equal [user], protected_branch.authorized_users

        protected_branch.update_restrictions(entry_point: :test_case)
        assert_equal [user], protected_branch.authorized_users
      end

      test "should keep teams as-is" do
        team = create(:team, organization: @org, privacy: :closed)
        team.add_repository @org_repo, :push
        protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
        protected_branch.replace_authorized_actors(user_ids: [], team_ids: [team.id], entry_point: :test_case)
        assert_equal [team], protected_branch.authorized_teams

        protected_branch.update_restrictions(entry_point: :test_case)
        assert_equal [team], protected_branch.authorized_teams
      end

      test "should keep integration installations as-is" do
        protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
        protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], integration_ids: [@app.id], entry_point: :test_case)
        assert_equal [@installation], protected_branch.authorized_integration_installations

        protected_branch.update_restrictions(entry_point: :test_case)
        assert_equal [@installation], protected_branch.authorized_integration_installations
      end
    end

    context "when passing users" do
      test "should look up users by login and replace existing users, skipping users with no access" do
        user = create(:user)
        @org_repo.add_member(user, action: :write)
        other_user = create(:user)
        protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
        assert_equal [], protected_branch.authorized_users

        protected_branch.update_restrictions(users: [user.login, other_user.login], entry_point: :test_case)
        assert_equal [user], protected_branch.authorized_users
      end
    end

    context "when passing teams" do
      test "should look up teams by slug and replace existing teams, skipping not authorized teams" do
        team = create(:team, organization: @org, privacy: :closed)
        team.add_repository @org_repo, :push
        other_team = create(:team, organization: @org, privacy: :closed)

        protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
        assert_equal [], protected_branch.authorized_teams

        protected_branch.update_restrictions(teams: [team.slug, other_team.slug], entry_point: :test_case)
        assert_equal [team], protected_branch.authorized_teams
      end

      test "should look up nested teams by slug and authorize them" do
        team = create(:team, organization: @org, privacy: :closed)
        team.add_repository @org_repo, :push
        child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: team.id)

        protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
        assert_equal [], protected_branch.authorized_teams

        protected_branch.update_restrictions(teams: [child_team.slug], entry_point: :test_case)
        assert_equal [child_team], protected_branch.authorized_teams
      end
    end

    context "when passing integration installations" do
      test "should look up integrations by slug and replace existing integrations, skipping not authorized integrations" do
        protected_branch = create(:protected_branch, repository: @org_repo)
        protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], integration_ids: [@app.id], entry_point: :test_case)
        assert_equal [@installation], protected_branch.authorized_integration_installations

        authorized_app = create(:integration)
        authorized_app_installation = make_integration_installation(integration: authorized_app, repository: @org_repo, permissions: { "contents" => :write })
        other_app = create(:integration)
        other_app_installation = make_integration_installation(integration: other_app, repository: @org_repo, permissions: { "contents" => :read })

        protected_branch.update_restrictions(integrations: [authorized_app.slug, other_app.slug], entry_point: :test_case)
        assert_equal [authorized_app_installation], protected_branch.authorized_integration_installations
      end
    end
  end

  context "merge queue" do
    if GitHub.merge_queues_enabled?
      test "invalid without merge queue enforcement level" do
        protected_branch = build(:protected_branch)
        assert_predicate protected_branch, :valid?

        protected_branch.merge_queue_enforcement_level = nil

        refute_predicate protected_branch, :valid?
        assert protected_branch.errors[:merge_queue_enforcement_level]
      end

      test "invalid when merge queue enabled and not a qualified branch name" do
        protected_branch = build(:protected_branch)
        assert_predicate protected_branch, :valid?

        protected_branch.merge_queue_enforcement_level_everyone!
        protected_branch.name = "dev*"

        refute_predicate protected_branch, :valid?
        assert protected_branch.errors[:merge_queue_enforcement_level]
      end

      test "invalid when enabling linear_history_required and merge queue uses 'merge' strategy" do
        protected_branch = build(:protected_branch)
        assert_predicate protected_branch, :valid?

        protected_branch.merge_queue_enforcement_level_everyone!

        protected_branch.enable_required_linear_history

        refute_predicate protected_branch, :valid?
        assert protected_branch.errors[:linear_history_requirement_enforcement_level]
      end

      test "valid when merge queue off and not a qualified branch name" do
        protected_branch = build(:protected_branch)
        assert_predicate protected_branch, :valid?

        protected_branch.merge_queue_enforcement_level_off!
        protected_branch.name = "dev*"

        assert_predicate protected_branch, :valid?
      end

      test "destroys the merge queue if the protected branch rule is destroyed" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo)
        protected_branch.enable_merge_queue
        protected_branch.save!

        assert @repo.merge_queue_for(branch: protected_branch.name)
        assert_difference -> { MergeQueue.count }, -1 do
          protected_branch.destroy
        end

        refute @repo.merge_queue_for(branch: protected_branch.name)
      end

      test "prevents updating the branch name when the merge queue is enabled" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo)
        protected_branch.enable_merge_queue
        protected_branch.save!

        assert_equal protected_branch.name, protected_branch.merge_queue.branch

        refute protected_branch.update(name: "dev")
        refute_predicate protected_branch, :valid?
        assert_includes protected_branch.errors[:name], "cannot be updated when the merge queue is enabled"
      end

      test "can update the branch name when the merge queue is off" do
        protected_branch = create(:protected_branch)
        assert_predicate protected_branch, :valid?

        protected_branch.merge_queue_enforcement_level_off!

        assert protected_branch.update(name: "dev")
        assert_predicate protected_branch, :valid?
      end
    end
  end

  context "#enable_merge_queue" do
    if GitHub.merge_queues_enabled?
      test "does nothing if repository is not feature flagged" do
        # MQ is unconditionally enabled for GHES repos
        skip if GitHub.enterprise?

        GitHub.flipper[:merge_queue].disable(@repo)

        protected_branch = create(:protected_branch, repository: @repo)
        assert_predicate protected_branch, :merge_queue_enforcement_level_off?

        protected_branch.enable_merge_queue
        protected_branch.save!

        assert_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        refute @repo.merge_queue_for(branch: protected_branch.name)
        refute protected_branch.merge_queue
      end

      test "does nothing if branch protection name is not a qualified branch name" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo, name: "dev*")
        assert_predicate protected_branch, :merge_queue_enforcement_level_off?

        protected_branch.enable_merge_queue
        protected_branch.save

        assert_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        refute @repo.merge_queue_for(branch: protected_branch.name)
        refute protected_branch.merge_queue
      end

      test "error when enabling if a MQ exists on a ruleset" do
        GitHub.flipper[:merge_queue].enable(@repo)
        GitHub.flipper[:block_duplicate_protected_branch_merge_queue].enable

        ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
        create(:repository_rule_configuration, :merge_queue, repository_ruleset: ruleset)
        ruleset.save
        assert @repo.merge_queue_for(branch: @repo.default_branch)

        protected_branch = create(:protected_branch, repository: @repo, admin_enforced: true)
        assert_predicate protected_branch, :merge_queue_enforcement_level_off?

        protected_branch.enable_merge_queue
        protected_branch.save

        assert protected_branch.errors[:merge_queue]
        refute protected_branch.merge_queue
      end

      test "enables and creates the merge queue for everyone if name is a qualified branch name" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo, admin_enforced: true)
        assert_predicate protected_branch, :merge_queue_enforcement_level_off?

        protected_branch.enable_merge_queue
        protected_branch.save!

        assert_predicate protected_branch.reload, :merge_queue_enforcement_level_everyone?
        assert @repo.merge_queue_for(branch: protected_branch.name)
        assert protected_branch.merge_queue
      end

      test "enables and creates the merge queue for non-admins if name is a qualified branch name" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo, admin_enforced: false)
        assert_predicate protected_branch, :merge_queue_enforcement_level_off?

        protected_branch.enable_merge_queue
        protected_branch.save!

        assert_predicate protected_branch.reload, :merge_queue_enforcement_level_non_admins?
        assert @repo.merge_queue_for(branch: protected_branch.name)
        assert protected_branch.merge_queue
      end

      test "enabling the merge queue more than once still works" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo)
        assert_predicate protected_branch, :merge_queue_enforcement_level_off?

        protected_branch.enable_merge_queue
        protected_branch.save!

        refute_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        assert @repo.merge_queue_for(branch: protected_branch.name)
        assert protected_branch.merge_queue

        protected_branch.enable_merge_queue
        protected_branch.save!

        refute_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        assert @repo.merge_queue_for(branch: protected_branch.name)
        assert protected_branch.merge_queue
      end

      test "sets the merge queue settings attributes from the settings hash" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo)
        assert_predicate protected_branch, :merge_queue_enforcement_level_off?

        settings_hash = {
          max_entries_to_merge: 5,
          check_run_retries_limit: 1,
        }

        protected_branch.enable_merge_queue
        protected_branch.merge_queue_settings_hash = settings_hash
        protected_branch.save!

        refute_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        merge_queue = protected_branch.merge_queue
        assert_equal 5, merge_queue.max_entries_to_merge
        assert_equal 1, merge_queue.check_run_retries_limit
      end

      context "coexisting support with required deployments" do
        test "it has a validation error when attempting to create a merge queue with a required deployment when not using deploy-then-merge" do
          @repo.enable_feature(:merge_queue)
          @repo.disable_feature(:merge_queue_deploy_then_merge)

          protected_branch = build(:protected_branch, repository: @repo)
          protected_branch.enable_merge_queue
          protected_branch.enable_required_deployments
          protected_branch.replace_required_deployment_environments(%w[production])
          refute protected_branch.save

          assert_includes protected_branch.errors.full_messages,
            "Required deployments enforcement level cannot be enabled when the merge queue is enabled"
        end

        test "it does not have the validation error if the repo is opted in to deploy then merge" do
          @repo.enable_feature(:merge_queue)
          @repo.enable_feature(:merge_queue_deploy_then_merge)

          protected_branch = build(:protected_branch, repository: @repo)
          protected_branch.enable_merge_queue
          protected_branch.enable_required_deployments
          protected_branch.replace_required_deployment_environments(%w[production])
          assert protected_branch.save
        end

        test "it does not have the validation error if the repo is owned by github" do
          Repository.any_instance.stubs(:github_owned?).returns(true)

          @repo.enable_feature(:merge_queue)
          @repo.disable_feature(:merge_queue_deploy_then_merge)

          protected_branch = build(:protected_branch, repository: @repo)
          protected_branch.enable_merge_queue
          protected_branch.enable_required_deployments
          protected_branch.replace_required_deployment_environments(%w[production])
          assert protected_branch.save
        end
      end

      test "instruments a Hydro event for merge queue creation" do
        @repo.enable_feature(:merge_queue)
        protected_branch = create(:protected_branch, repository: @repo, admin_enforced: true)
        protected_branch.enable_merge_queue
        hydro_schema = "github.merge_queue.v1.MergeQueueEvent"
        refute_hydro_messages(schema: hydro_schema)

        protected_branch.save!

        message = {
          event: :CREATE,
          repository: Hydro::EntitySerializer.repository(@repo),
          protected_branch: Hydro::EntitySerializer.protected_branch(protected_branch),
          queue: Hydro::EntitySerializer.merge_queue(protected_branch.merge_queue),
          entries: [],
          group_entries: [],
          current_merge_group: nil,
          groups: [],
          candidate_groups: [],
        }
        assert_hydro_published(message, schema: hydro_schema)
        assert_hydro_messages(count: 1, schema: hydro_schema)
      end
    else
      test "ignores merge queue for enterprise" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo, admin_enforced: true)
        assert_predicate protected_branch, :merge_queue_enforcement_level_off?

        protected_branch.enable_merge_queue
        protected_branch.save!

        assert_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        refute @repo.merge_queue_for(branch: protected_branch.name)
        refute protected_branch.merge_queue
      end
    end
  end

  context "#clear_merge_queue" do
    if GitHub.merge_queues_enabled?
      test "disables and destroys the merge queue" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo)
        protected_branch.enable_merge_queue
        protected_branch.save!

        refute_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        assert @repo.merge_queue_for(branch: protected_branch.name)
        assert protected_branch.merge_queue

        protected_branch.clear_merge_queue
        protected_branch.save!

        assert_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        refute @repo.merge_queue_for(branch: protected_branch.name)
        refute protected_branch.reload.merge_queue
      end

      test "disabling the merge queue more than once still works" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo)
        protected_branch.clear_merge_queue
        protected_branch.save!

        assert_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        refute @repo.merge_queue_for(branch: protected_branch.name)
        refute protected_branch.reload.merge_queue

        protected_branch.clear_merge_queue
        protected_branch.save!

        assert_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        refute @repo.merge_queue_for(branch: protected_branch.name)
        refute protected_branch.reload.merge_queue
      end
    else
      test "ignores merge queue for enterprise" do
        GitHub.flipper[:merge_queue].enable(@repo)

        protected_branch = create(:protected_branch, repository: @repo, admin_enforced: true)
        assert_predicate protected_branch, :merge_queue_enforcement_level_off?

        protected_branch.clear_merge_queue
        protected_branch.save!

        assert_predicate protected_branch.reload, :merge_queue_enforcement_level_off?
        refute @repo.merge_queue_for(branch: protected_branch.name)
        refute protected_branch.merge_queue
      end
    end
  end

  context "#merge_queue_enabled?" do
    test "returns true if merge queue enforcement level is everyone" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :everyone)
      assert_predicate protected_branch, :merge_queue_enabled?
    end

    test "returns true if merge queue enforcement level is non-admins" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :non_admins)
      assert_predicate protected_branch, :merge_queue_enabled?
    end

    test "returns false if merge queue enforcement level is off" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :off)
      refute_predicate protected_branch, :merge_queue_enabled?
    end
  end

  context "#ignore_approvals_from_contributors?" do
    test "always false when the associated repo is not flagged" do
      GitHub.flipper[:disqualify_pr_pushers_from_approving].disable(@repo)
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :off)

      protected_branch.ignore_approvals_from_contributors = true
      refute_predicate protected_branch, :ignore_approvals_from_contributors?

      protected_branch.ignore_approvals_from_contributors = false
      refute_predicate protected_branch, :ignore_approvals_from_contributors?
    end

    test "behaves normally when feature flag is on" do
      GitHub.flipper[:disqualify_pr_pushers_from_approving].enable(@repo)

      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :off)

      protected_branch.ignore_approvals_from_contributors = true
      assert_predicate protected_branch, :ignore_approvals_from_contributors?

      protected_branch.ignore_approvals_from_contributors = false
      refute_predicate protected_branch, :ignore_approvals_from_contributors?
    end
  end

  context "#require_last_push_approval?" do
    test "behaves normally without feature flag" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :off)

      protected_branch.require_last_push_approval = true
      assert_predicate protected_branch, :require_last_push_approval?

      protected_branch.require_last_push_approval = false
      refute_predicate protected_branch, :require_last_push_approval?
    end
  end

  context "#sync_create_protected" do
    test "should clear create_protected if and only if authorized_actors_only is false" do
      protected_branch = create(:protected_branch, repository: @org_repo)

      @org_repo.add_member(@user, action: :write)
      protected_branch.replace_authorized_actors(user_ids: [@user.id], team_ids: [], entry_point: :test_case)
      protected_branch.enable_create_protected

      assert protected_branch.create_protected
      assert_equal [@user], protected_branch.authorized_users

      protected_branch.save!

      assert protected_branch.create_protected, "create_protected should not be cleared since push restrictions are enabled"
      assert_equal [@user], protected_branch.authorized_users

      protected_branch.clear_restrictions
      protected_branch.save!

      refute protected_branch.create_protected, "create_protected should be cleared since push restrictions were removed"
      assert_equal [], protected_branch.authorized_users
    end
  end

  context "#create_protected?" do
    test "blocks or permits branch creation" do
      protected_branch = build(:protected_branch, repository: @repo)

      protected_branch.create_protected = true
      assert protected_branch.create_protected?

      protected_branch.create_protected = false
      refute protected_branch.create_protected?
    end
  end

  context "#enable_required_pull_request_reviews" do
    test "sets pull_request_reviews_enforcement_level" do
      protected_branch = build(
        :protected_branch,
        repository: @repo,
        pull_request_reviews_enforcement_level: :off,
        admin_enforced: false,
      )

      protected_branch.enable_required_pull_request_reviews

      assert_equal "non_admins", protected_branch.pull_request_reviews_enforcement_level
      # by default, other attributes are disabled
      refute protected_branch.require_last_push_approval?
    end

    test "sets last push approval requirement" do
      protected_branch = build(
        :protected_branch,
        repository: @repo,
        pull_request_reviews_enforcement_level: :off,
        admin_enforced: false,
      )

      protected_branch.enable_required_pull_request_reviews(require_last_push_approval: true)

      assert protected_branch.require_last_push_approval?
    end

    test "respects the admin_enforced flag" do
      protected_branch = build(
        :protected_branch,
        repository: @repo,
        pull_request_reviews_enforcement_level: :off,
        admin_enforced: true,
      )

      protected_branch.enable_required_pull_request_reviews

      assert_equal "everyone", protected_branch.pull_request_reviews_enforcement_level
    end
  end

  test "is deleted with repository" do
    protected_branch = create(:protected_branch,
      repository: @repo,
      name: "master",
    )
    other_protected_branch = create(:protected_branch,
      repository: @org_repo,
      name: "master",
    )

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [protected_branch]
      config.expect_not_destroyed = [other_protected_branch]
    end
  end
end
