# typed: true
# frozen_string_literal: true

require "test_helper"

class BranchRuleEvaluatorTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
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

    @org_repo_app_installation = make_integration_installation(
      repository: @org_repo,
      permissions: { "administration" => :write, "contents" => :write },
    )
    @org_repo_admin_app_installation = make_integration_installation(
      repository: @org_repo,
      permissions: { "administration" => :write, "contents" => :write },
    )

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  def branch_policy_evalautor_from(protected_branch)
    protected_branch.save!
    protected_branch.reload
    BranchRuleEvaluator.new(protected_branch.repository, "refs/heads/#{protected_branch.name}")
  end

  def branch_policy_evalautor_for_branch(repository, branch_name)
    BranchRuleEvaluator.for_repository_with_branch_name(repository, branch_name)
  end

  context "for_repository_with_branch_name" do
    test "returns nil when protected branch exists but the repository plan does not support it" do
      free_org = create(:organization, plan: GitHub::Plan.free)
      repo = create(:private_repository, owner: free_org)
      branch = create(:protected_branch, repository: repo, name: "master", required_status_checks_enforcement_level: :off)
      policy_evaluator = branch_policy_evalautor_for_branch(repo, "master")

      assert_nil policy_evaluator
    end
  end

  context "#commit_authorized?" do
    test "returns true when required_status_checks_enforcement_level is off" do
      branch = create(:protected_branch, repository: @repo, name: "master", required_status_checks_enforcement_level: :off)
      branch.replace_status_contexts(%w[master foo])
      policy_evaluator = branch_policy_evalautor_from(branch)
      assert policy_evaluator.commit_authorized?(@user)
    end

    test "returns false if branch requires status checks" do
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")
      protected_branch.required_status_checks_enforcement_level = :everyone
      protected_branch.replace_status_contexts(["master"])
      protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.commit_authorized?(@org_admin)
    end

    test "returns false if branch requires status checks and admin is authorized" do
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")
      protected_branch.required_status_checks_enforcement_level = :everyone
      protected_branch.replace_status_contexts(["master"])

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.commit_authorized?(@org_admin)
    end

    test "returns true for admins when required_status_checks_enforcement_level is non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", required_status_checks_enforcement_level: :non_admins)
      branch.replace_status_contexts(%w[master foo])
      policy_evaluator = branch_policy_evalautor_from(branch)
      assert policy_evaluator.commit_authorized?(@user), "Admin user requires status checks or reviews"
    end

    test "returns true for bots with administration permission when required_status_checks_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @org_repo, name: "master", required_status_checks_enforcement_level: :non_admins)
      branch.replace_status_contexts(%w[master foo])
      policy_evaluator = branch_policy_evalautor_from(branch)
      assert policy_evaluator.commit_authorized?(@org_repo_admin_app_installation.bot), "Admin bot requires status checks or reviews"
    end

    test "returns false for non-admins when required_status_checks_enforcement_level is non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", required_status_checks_enforcement_level: :non_admins)
      branch.replace_status_contexts(%w[master foo])
      policy_evaluator = branch_policy_evalautor_from(branch)
      refute policy_evaluator.commit_authorized?(create(:user))
    end

    test "returns false if branch requires reviews" do
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")
      protected_branch.pull_request_reviews_enforcement_level = :everyone
      protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.commit_authorized?(@org_admin)
    end

    test "returns false for users when branch is locked for non-admins" do
      member = create(:user)
      @repo.add_member member, action: :write

      branch = create(:protected_branch, repository: @repo, name: "master", lock_branch_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(branch)
      refute policy_evaluator.commit_authorized?(member)
    end

    test "returns true for admins when branch is locked for non-admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", lock_branch_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(branch)
      assert policy_evaluator.commit_authorized?(@user)
    end

    test "returns false if the branch is locked for everyone" do
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master", lock_branch_enforcement_level: :everyone)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.commit_authorized?(@org_admin)
    end

    test "returns false for unauthorized users" do
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")
      protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)
      rando = create(:user)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.authorized?(rando)
      refute policy_evaluator.commit_authorized?(rando)
    end

    test "returns true for authorized users when branch doesn't require status checks or reviews, and the branch is not locked" do
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")
      protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.commit_authorized?(@org_admin)
    end

    test "returns false if an update rule is configured" do
      member = create(:user)
      @repo.add_member member, action: :write
      @repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      rule_configuration = create(
        :repository_rule_configuration,
        rule_type: "update" ,
        parameters: {
          update_allows_fetch_and_merge: true
        },
        repository_ruleset: ruleset
      )

      policy_evaluator = branch_policy_evalautor_for_branch(@repo, "master")
      refute policy_evaluator.commit_authorized?(member)
    end

    test "returns false if branch locked and fork syncing is enabled" do
      # only fetch and merge is allowed
      member = create(:user)
      @repo.add_member member, action: :write

      branch = create(:protected_branch, repository: @repo, name: "master", lock_branch_enforcement_level: :non_admins, lock_allows_fetch_and_merge: true)
      policy_evaluator = branch_policy_evalautor_from(branch)
      refute policy_evaluator.commit_authorized?(member)
      # repo admin can still commit
      assert policy_evaluator.commit_authorized?(@repo.owner)
    end

    test "returns false for admin if branch locked for everyone and fork syncing is enabled" do
      # only fetch and merge is allowed
      branch = create(:protected_branch, repository: @repo, name: "master", lock_branch_enforcement_level: :everyone, lock_allows_fetch_and_merge: true)
      policy_evaluator = branch_policy_evalautor_from(branch)
      refute policy_evaluator.commit_authorized?(@repo.owner)
    end
  end

  context "#authorized?" do
    test "Admins are always authorized" do
      repo_admin = create(:user)
      @org_repo.add_member(repo_admin, action: :admin)

      org_admin = create(:user)
      @org.add_member(org_admin, action: :admin)

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(@org_repo_team_member), "With no authorized users specified, member of team with admin permission isn't authorized."
      assert policy_evaluator.authorized?(repo_admin), "With no authorized users specified, repo admin isn't authorized."
      assert policy_evaluator.authorized?(org_admin), "With no authorized users specified, org admin isn't authorized."

      user = create(:user)
      @org_repo.add_member(user, action: :write)
      protected_branch.replace_authorized_actors(user_ids: [user.id], team_ids: [], entry_point: :test_case)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(@org_repo_team_member), "Member of team with admin permission isn't authorized."
      assert policy_evaluator.authorized?(repo_admin), "Repo admin isn't authorized."
      assert policy_evaluator.authorized?(org_admin), "Org admin isn't authorized."
      assert policy_evaluator.authorized?(user), "Repo collaborator with write access on the authorized user list is not authorized with push restrictions, but should be."
    end

    test "Maintainers are always authorized" do
      repo_maintainer = create(:user)
      @org_repo.add_member repo_maintainer, action: :maintain

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(repo_maintainer), "Repo maintainer is not authorized with no push restrictions, but should be."

      user = create(:user)
      @org_repo.add_member(user, action: :write)
      protected_branch.replace_authorized_actors(user_ids: [user.id], team_ids: [], entry_point: :test_case)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(repo_maintainer), "Repo maintainer is not authorized with push restrictions, but should be."
      assert policy_evaluator.authorized?(user), "Repo collaborator with write access on the authorized user list is not authorized with push restrictions, but should be."
    end

    test "Integration installations with administration write are always authorized" do
      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [@org.admins.first.id], team_ids: [], entry_point: :test_case)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(@org_repo_admin_app_installation.bot), "Bot with repository administration is not authorized with no push restrictions, but should be."
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
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.authorized?(installation.bot), "Bot with repository administration not installed on repo is authorized, but shouldn't be."
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
                                                          integration_ids: [@org_repo_admin_app_installation.integration_id], entry_point: :test_case)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(authorized_team_member), "Member of an authorized team isn't authorized."
      assert policy_evaluator.authorized?(authorized_user), "Authorized user isn't authorized."
      assert policy_evaluator.authorized?(@org_repo_app_installation.bot), "Authorized bot isn't authorized."

      refute policy_evaluator.authorized?(unauthorized_team_member), "Member of an unauthorized team is authorized."
      refute policy_evaluator.authorized?(unauthorized_user), "Unauthorized user is authorized."
      refute policy_evaluator.authorized?(unauthorized_bot), "Unauthorized bot is authorized."
    end

    test "scoped integration installations with authorized parent installations are also authorized" do
      authorized_scoped_installation = make_scoped_integration_installation(
        parent: @org_repo_app_installation, repositories: [@org_repo],
      )
      authorized_scoped_bot = authorized_scoped_installation.bot

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], integration_ids: [@org_repo_admin_app_installation.integration_id], entry_point: :test_case)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(authorized_scoped_bot), "Authorized scoped bot isn't authorized."
    end

    test "scoped integration installations without repository write are not authorized" do
      scoped_installation = make_scoped_integration_installation(
        parent: @org_repo_app_installation, repositories: [@org_repo], permissions: { "contents" => :read },
      )
      scoped_bot = scoped_installation.bot

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], integration_ids: [@org_repo_app_installation.integration_id], entry_point: :test_case)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.authorized?(scoped_bot), "Unauthorized bot is authorized."
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

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(child_team_member)
    end

    test "nested team members get authorization on private repos" do
      parent_team = create(:team, organization: @org, privacy: :closed)
      parent_team.add_repository @private_org_repo, :admin

      child_team = create(:team, organization: @org, parent_team_id: parent_team.id, privacy: :closed)
      child_team_member = create(:user)
      child_team.add_member(child_team_member)

      protected_branch = create :protected_branch, repository: @private_org_repo, name: "master"
      protected_branch.replace_authorized_actors(user_ids: [], team_ids: [child_team.id], entry_point: :test_case)

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(child_team_member)
    end

    test "Users that lose access to a repo are not authorized" do
      user = create(:user)
      @org_repo.add_member user, action: :write

      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors user_ids: [user.id], team_ids: [], entry_point: :test_case

      @org_repo.remove_member user

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.authorized?(user), "User removed from the org is still authorized."
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

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(team_member), "Team member should be authorized (but is not)."
      assert_equal [team], protected_branch.authorized_teams
      assert_equal [team], protected_branch.authorized_actors

      # Reload repository.protected_branches relation
      @org_repo.reload

      team.remove_repository @org_repo
      team.add_repository @org_repo, :read

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.authorized?(team_member), "Team member should not be authorized (but is)."
      assert_empty protected_branch.authorized_teams
      assert_empty protected_branch.authorized_actors
    end

    test "IntegrationInstallations with contents write permission are not authorized when push restrictions are enabled" do
      installation = make_integration_installation(repository: @org_repo, permissions: { "contents" => :write })
      bot = installation.bot

      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(bot), "IntegrationInstallation should be authorized (but is *NOT*)."

      protected_branch.replace_authorized_actors user_ids: [@org.admins.first.id], team_ids: [], entry_point: :test_case

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.authorized?(bot), "IntegrationInstallation should *NOT* be authorized (but is)."
    end

    test "protected branch destroy emits entry_point" do
      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      entry_point = :test_case

      Permissions::QueryRouter.expects(:delete_app_permissions_on_subject).with(protected_branch, entry_point: entry_point)
      protected_branch.destroy_with_args(entry_point: entry_point)
    end

    test "IntegrationInstallations that are uninstalled are not authorized" do
      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors user_ids: [], team_ids: [], integration_ids: [@org_repo_app_installation.integration_id], entry_point: :test_case

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(@org_repo_app_installation.bot), "Bot's integration installation should be authorized but isn't"
      assert_equal [@org_repo_app_installation.id], protected_branch.authorized_integration_installation_ids
      assert_equal [@org_repo_app_installation], protected_branch.authorized_integration_installations

      perform_enqueued_jobs only: [DestroyDependentRecordsJob] do
        @org_repo_app_installation.uninstall(actor: @org_repo.owner)
      end

      protected_branch = ProtectedBranch.find(protected_branch.id)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.authorized?(@org_repo_app_installation.bot), "Bot's integration installation removed from the repo is still authorized."
      assert_empty protected_branch.authorized_integration_installation_ids
      assert_empty protected_branch.authorized_integration_installations
    end

    test "IntegrationInstallations that are removed from the repository are not authorized" do
      other_org_repo = create(:repository, owner: @org)
      protected_branch = create :protected_branch, repository: @org_repo, name: "master"
      protected_branch.replace_authorized_actors user_ids: [], team_ids: [], integration_ids: [@org_repo_app_installation.integration_id], entry_point: :test_case

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.authorized?(@org_repo_app_installation.bot), "Bot's integration installation should be authorized but isn't"
      assert_equal [@org_repo_app_installation.id], protected_branch.authorized_integration_installation_ids
      assert_equal [@org_repo_app_installation], protected_branch.authorized_integration_installations

      @org_repo_app_installation.edit(
        editor: @org_repo.owner,
        repositories: [other_org_repo],
        entry_point: :test_case
      )

      protected_branch = ProtectedBranch.find(protected_branch.id)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.authorized?(@org_repo_app_installation.bot), "Bot's integration installation removed from the repo is still authorized."
      assert_empty protected_branch.authorized_integration_installation_ids
      assert_empty protected_branch.authorized_integration_installations
    end
  end

  context "#can_override_required_signatures?" do
    test "returns true when signature_requirement_enforcement_level==off" do
      branch = create(:protected_branch, repository: @repo, name: "master", signature_requirement_enforcement_level: :off)
      policy_evaluator = branch_policy_evalautor_from(branch)
      assert policy_evaluator.can_override_required_signatures?(actor: @user)
    end

    test "returns true for admins when signature_requirement_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", signature_requirement_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(branch)
      assert policy_evaluator.can_override_required_signatures?(actor: @user)
    end

    test "returns true for bots with administration permission when signature_requirement_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @org_repo, name: "master", signature_requirement_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(branch)
      assert policy_evaluator.can_override_required_signatures?(actor: @org_repo_admin_app_installation.bot), "Admin bot can't override required signatures"
    end

    test "returns false for non-admins when signature_requirement_enforcement_level==non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", signature_requirement_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(branch)
      refute policy_evaluator.can_override_required_signatures?(actor: create(:user))
    end

    test "returns false for admins when signature_requirement_enforcement_level==everyone" do
      branch = create(:protected_branch, repository: @repo, name: "master", signature_requirement_enforcement_level: :everyone)
      policy_evaluator = branch_policy_evalautor_from(branch)
      refute policy_evaluator.can_override_required_signatures?(actor: @user)
    end
  end

  context "#can_override_required_linear_history?" do
    test "returns true when merge commit blocking is off" do
      branch = create(:protected_branch, repository: @repo, name: "master", linear_history_requirement_enforcement_level: :off)
      policy_evaluator = branch_policy_evalautor_from(branch)
      assert policy_evaluator.can_override_required_linear_history?(actor: @user)
    end

    test "returns true for admins when enforcement level is non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", linear_history_requirement_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(branch)
      assert policy_evaluator.can_override_required_linear_history?(actor: @user)
    end

    test "returns true for bots with administration permission when enforcement level is non_admins" do
      branch = create(:protected_branch, repository: @org_repo, name: "master", linear_history_requirement_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(branch)
      assert policy_evaluator.can_override_required_linear_history?(actor: @org_repo_admin_app_installation.bot), "Admin bot can't override required linear history"
    end

    test "returns false for non-admins when enforcement level is non_admins" do
      branch = create(:protected_branch, repository: @repo, name: "master", linear_history_requirement_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(branch)
      refute policy_evaluator.can_override_required_linear_history?(actor: create(:user))
    end

    test "returns false for admins when enforcement level is everyone" do
      branch = create(:protected_branch, repository: @repo, name: "master", linear_history_requirement_enforcement_level: :everyone)
      policy_evaluator = branch_policy_evalautor_from(branch)
      refute policy_evaluator.can_override_required_linear_history?(actor: @user)
    end
  end

  context "#strict_required_status_checks_policy" do
    test "returns value when feature is enabled" do
      branch = create(:protected_branch, repository: @repo, name: "master", required_status_checks_enforcement_level: :everyone,
          strict_required_status_checks_policy: false)

      policy_evaluator = branch_policy_evalautor_from(branch)
      refute_predicate policy_evaluator, :strict_required_status_checks_policy?

      branch.update!(strict_required_status_checks_policy: true)

      policy_evaluator = branch_policy_evalautor_from(branch)
      assert_predicate policy_evaluator, :strict_required_status_checks_policy?
    end
  end

  context "#review_dismissable_by?" do
    test "returns true for teams and users that can dismiss" do
      teammate = create(:user)
      other_user = create(:user)
      team = create(:team, organization: @org)
      team.add_member(teammate)
      team.add_repository @org_repo, :admin
      @org_repo.add_member(@user, action: :write)
      @org_repo.add_member(other_user, action: :write)
      protected_branch = create(:protected_branch, repository: @org_repo, pull_request_reviews_enforcement_level: :everyone)
      protected_branch.replace_dismissal_restricted_actors(user_ids: [@user.id], team_ids: [team.id])
      policy_evaluator = branch_policy_evalautor_from(protected_branch)

      refute policy_evaluator.review_dismissable_by?(other_user)
      assert policy_evaluator.review_dismissable_by?(teammate)
      assert policy_evaluator.review_dismissable_by?(@user)
    end

    test "returns true for admins if not restricted" do
      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.pull_request_reviews_enforcement_level = :everyone
      protected_branch.save!

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert protected_branch.admin_enforced?
      assert policy_evaluator.review_dismissable_by?(@org_admin), "Admin user can dimiss review"
      assert policy_evaluator.review_dismissable_by?(@org_repo_admin_app_installation.bot), "Admin bot can dimiss review"
    end

    test "returns true for members of a team" do
      team = create(:team, organization: @org)
      team.add_repository @org_repo, :admin
      team_member = create(:user)
      team.add_member(team_member)

      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_dismissal_restricted_actors(user_ids: [], team_ids: [team.id])

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.review_dismissable_by?(team_member)
    end

    test "returns false for members of a team with only read access" do
      team = create(:team, organization: @org)
      team.add_repository @org_repo, :read
      team_member = create(:user)
      team.add_member(team_member)

      protected_branch = create(:protected_branch, repository: @org_repo)
      protected_branch.replace_dismissal_restricted_actors(user_ids: [], team_ids: [team.id])

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.review_dismissable_by?(team_member)
      refute_nil policy_evaluator.review_dismissable_by?(team_member)
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

      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.review_dismissable_by?(parent_team_member)
      assert policy_evaluator.review_dismissable_by?(child_team_member)
    end
  end

  context "#can_merge_as_admin?" do
    test "returns true if the merge queue is not enabled and the user is an admin with admin not enforced" do
      protected_branch = build(
        :protected_branch,
        repository: @repo,
        merge_queue_enforcement_level: :off,
        admin_enforced: false
      )
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.can_merge_as_admin?(actor: @user)
    end

    test "returns false if the merge queue is not enabled and the user is an admin with admin enforced" do
      protected_branch = build(
        :protected_branch,
        repository: @repo,
        merge_queue_enforcement_level: :off,
        admin_enforced: true
      )
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.can_merge_as_admin?(actor: @user)
    end

    test "returns false if the merge queue is not enabled and the user is a non-admin with admin not enforced" do
      protected_branch = build(
        :protected_branch,
        repository: @repo,
        merge_queue_enforcement_level: :off,
        admin_enforced: false
      )
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.can_merge_as_admin?(actor: create(:user))
    end

    test "returns false when merge queue enforcement level is everyone" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :everyone)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.can_merge_as_admin?(actor: @user)
    end

    test "returns true for admins when merge queue enforcement level is non-admins" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.can_merge_as_admin?(actor: @user)
    end

    test "returns false for non-admins when merge queue enforcement level is non-admins" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.can_merge_as_admin?(actor: create(:user))
    end

    test "returns false when a ruleset doesn't allow bypass" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      ruleset.rule_configurations << create(:repository_rule_configuration)

      policy_evaluator = branch_policy_evalautor_for_branch(@repo, @repo.default_branch)
      refute policy_evaluator.can_merge_as_admin?(actor: @user)
    end

    test "returns true when a ruleset does allow repo admin bypass" do
      ruleset = create(:repository_ruleset, :targets_default_branch, :repo_admin_bypass, source: @repo)
      ruleset.rule_configurations << create(:repository_rule_configuration)

      policy_evaluator = branch_policy_evalautor_for_branch(@repo, @repo.default_branch)
      assert policy_evaluator.can_merge_as_admin?(actor: @user)
    end

    test "returns false when a ruleset does allow repo admin bypass but a protected_branch does not allow admin_override" do
      protected_branch = create(:protected_branch, repository: @repo, admin_enforced: true)
      ruleset = create(:repository_ruleset, :targets_default_branch, :repo_admin_bypass, source: @repo)
      ruleset.rule_configurations << create(:repository_rule_configuration)

      policy_evaluator = branch_policy_evalautor_for_branch(@repo, @repo.default_branch)
      refute policy_evaluator.can_merge_as_admin?(actor: @user)
    end
  end

  context "#merge_queue_enforced_for?" do
    test "returns false when merge queue enforcement level is off" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :off)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.merge_queue_enforced_for?(actor: @user)
    end

    test "returns true when merge queue enforcement level is everyone" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :everyone)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.merge_queue_enforced_for?(actor: @user)
    end

    test "returns false for admins when merge queue enforcement level is non-admins" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute policy_evaluator.merge_queue_enforced_for?(actor: @user)
    end

    test "returns true for non-admins when merge queue enforcement level is non-admins" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert policy_evaluator.merge_queue_enforced_for?(actor: create(:user))
    end
  end

  context "#merge_queue_enabled?" do
    test "returns true if merge queue enforcement level is everyone" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :everyone)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert_predicate policy_evaluator, :merge_queue_enabled?
    end

    test "returns true if merge queue enforcement level is non-admins" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :non_admins)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert_predicate policy_evaluator, :merge_queue_enabled?
    end

    test "returns false if merge queue enforcement level is off" do
      protected_branch = build(:protected_branch, repository: @repo, merge_queue_enforcement_level: :off)
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute_predicate policy_evaluator, :merge_queue_enabled?
    end
  end

  context "#ignore_approvals_from_contributors?" do
    test "always false when the associated repo is not flagged" do
      GitHub.flipper[:disqualify_pr_pushers_from_approving].disable(@repo)
      protected_branch = build(:protected_branch, repository: @repo, pull_request_reviews_enforcement_level: :everyone)

      protected_branch.ignore_approvals_from_contributors = true
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute_predicate policy_evaluator, :ignore_approvals_from_contributors?

      protected_branch.ignore_approvals_from_contributors = false
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute_predicate policy_evaluator, :ignore_approvals_from_contributors?
    end

    test "behaves normally when feature flag is on" do
      GitHub.flipper[:disqualify_pr_pushers_from_approving].enable(@repo)

      protected_branch = build(:protected_branch, repository: @repo, pull_request_reviews_enforcement_level: :everyone)

      protected_branch.ignore_approvals_from_contributors = true
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert_predicate policy_evaluator, :ignore_approvals_from_contributors?

      protected_branch.ignore_approvals_from_contributors = false
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute_predicate policy_evaluator, :ignore_approvals_from_contributors?
    end
  end

  context "#require_last_push_approval?" do
    test "behaves normally without feature flag" do
      protected_branch = build(:protected_branch, repository: @repo, pull_request_reviews_enforcement_level: :everyone)

      protected_branch.require_last_push_approval = true
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      assert_predicate policy_evaluator, :require_last_push_approval?

      protected_branch.require_last_push_approval = false
      policy_evaluator = branch_policy_evalautor_from(protected_branch)
      refute_predicate policy_evaluator, :require_last_push_approval?
    end
  end

  context "default merge method" do
    test "defers to the repository if linear history is not required" do
      @repo.set_sticky_merge_method(@user, "rebase")
      branch = create(:protected_branch, {
        repository: @repo,
        creator: @user,
        name: "master",
        linear_history_requirement_enforcement_level: :off,
      })
      policy_evaluator = branch_policy_evalautor_from(branch)

      assert_equal :rebase, policy_evaluator.default_merge_method_for(@user)
    end

    test "defers to the repository if a non-merge method is already preferred" do
      @repo.set_sticky_merge_method(@user, "squash")
      branch = create(:protected_branch, {
        repository: @repo,
        creator: @user,
        name: "master",
        linear_history_requirement_enforcement_level: :everyone,
      })
      policy_evaluator = branch_policy_evalautor_from(branch)

      assert_equal :squash, policy_evaluator.default_merge_method_for(@user)
    end

    test "prefers a squash merge" do
      branch = create(:protected_branch, {
        repository: @repo,
        creator: @user,
        name: "master",
        linear_history_requirement_enforcement_level: :everyone,
      })
      policy_evaluator = branch_policy_evalautor_from(branch)

      assert_equal :squash, policy_evaluator.default_merge_method_for(@user)
    end

    test "falls back to a rebase" do
      @repo.update_merge_settings(@user,
        merge_allowed: false,
        squash_allowed: false,
        rebase_allowed: true,
        delete_branch_allowed: true,
      )
      branch = create(:protected_branch,
        repository: @repo,
        creator: @user,
        name: "master",
        linear_history_requirement_enforcement_level: :everyone,
      )
      policy_evaluator = branch_policy_evalautor_from(branch)

      assert_equal :rebase, policy_evaluator.default_merge_method_for(@user)
    end
  end

  context "rulesets" do
    test "loads ruleset rules" do
      @repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      rule_configuration = create(
        :repository_rule_configuration,
        rule_type: "pull_request" ,
        parameters: {
          required_approving_review_count: 1,
          require_code_owner_review: false,
          dismiss_stale_reviews_on_push: false,
          ignore_approvals_from_contributors: false,
          require_last_push_approval: false,
          authorized_dismissal_actors_only: false,
          required_review_thread_resolution: false
        },
        repository_ruleset: ruleset
      )

      policy_evaluator = branch_policy_evalautor_for_branch(@repo, "master")

      assert policy_evaluator
      assert policy_evaluator.pull_request_required?
    end

    test "does not consider evalaute rulesets" do
      @org_repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @org_repo, enforcement: "evaluate")
      rule_configuration = create(:repository_rule_configuration, :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)

      policy_evaluator = branch_policy_evalautor_for_branch(@org_repo, "master")

      assert policy_evaluator
      refute policy_evaluator.pull_request_required?
    end
  end

  context "#commit_authorized_status" do
    test "allows update when the only rules that apply do not block update" do
      @repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      create(:repository_rule_configuration, rule_type: "creation", repository_ruleset: ruleset)

      policy_evaluator = branch_policy_evalautor_for_branch(@repo, "master")

      assert policy_evaluator
      assert_equal :allowed, policy_evaluator.commit_authorized_status(@user)
    end

    test "blocks update when update rule is not-bypassable" do
      @repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      create(:repository_rule_configuration, rule_type: "update", repository_ruleset: ruleset, parameters: {
        update_allows_fetch_and_merge: true
      })

      policy_evaluator = branch_policy_evalautor_for_branch(@repo, "master")

      assert policy_evaluator
      assert_equal :blocked, policy_evaluator.commit_authorized_status(@user)
    end

    test "does not block update when update rule is in evaluate mode" do
      @org_repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @org_repo, enforcement: "evaluate")
      create(:repository_rule_configuration, rule_type: "update", repository_ruleset: ruleset, parameters: {
        update_allows_fetch_and_merge: true
      })

      policy_evaluator = branch_policy_evalautor_for_branch(@org_repo, "master")

      assert policy_evaluator
      assert_equal :allowed, policy_evaluator.commit_authorized_status(@user)
    end

    test "blocks update when update rule is bypassable" do
      @repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, :targets_default_branch, :repo_admin_bypass, source: @repo)
      create(:repository_rule_configuration, rule_type: "update", repository_ruleset: ruleset, parameters: {
        update_allows_fetch_and_merge: true
      })

      policy_evaluator = branch_policy_evalautor_for_branch(@repo, "master")

      assert policy_evaluator
      assert_equal :can_bypass, policy_evaluator.commit_authorized_status(@user)
    end

    test "blocks update when one rule is bypassable and one is not" do
      @repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, :targets_default_branch, :repo_admin_bypass, source: @repo)
      create(:repository_rule_configuration, rule_type: "update", repository_ruleset: ruleset, parameters: {
        update_allows_fetch_and_merge: true
      })

      ruleset2 = create(:repository_ruleset, :targets_default_branch, source: @repo)
      create(:repository_rule_configuration, rule_type: "required_status_checks", repository_ruleset: ruleset2, parameters: {
        strict_required_status_checks_policy: true,
        required_status_checks: [
          {
            context: "test"
          }
        ]
      })

      policy_evaluator = branch_policy_evalautor_for_branch(@repo, "master")

      assert policy_evaluator
      assert_equal :blocked, policy_evaluator.commit_authorized_status(@user)
    end

    test "blocks update when workflows rule is not-bypassable" do
      @private_org_repo.protected_branches.destroy_all

      @org_repo.heads["master"].append_commit({ message: "add workflow", committer: @org_admin }, @org_admin) do |files|
        files.add(".github/workflows/test.yml", "some content")
      end

      ruleset = create(:repository_ruleset, :targets_all_repos, :targets_default_branch, source: @org)
      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: @org_repo.id,
          path: ".github/workflows/test.yml",
          ref: "refs/heads/master"
        }]
      })

      rule_evaluator = branch_policy_evalautor_for_branch(@org_repo, "master")

      assert rule_evaluator
      assert_equal :blocked, rule_evaluator.commit_authorized_status(@org_admin)
    end

    test "blocks update when workflows rule is bypassable" do
      @private_org_repo.protected_branches.destroy_all

      @org_repo.heads["master"].append_commit({ message: "add workflow", committer: @org_admin }, @org_admin) do |files|
        files.add(".github/workflows/test.yml", "some content")
      end

      ruleset = create(:repository_ruleset, :targets_all_repos, :targets_default_branch, :repo_admin_bypass, source: @org)
      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: @org_repo.id,
          path: ".github/workflows/test.yml",
          ref: "refs/heads/master"
        }]
      })

      rule_evaluator = branch_policy_evalautor_for_branch(@org_repo, "master")

      assert rule_evaluator
      assert_equal :can_bypass, rule_evaluator.commit_authorized_status(@org_admin)
    end

    test "allows when creating a branch and a rule does not apply to create" do
      @repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
      create(:repository_rule_configuration, rule_type: "update", repository_ruleset: ruleset, parameters: {
        update_allows_fetch_and_merge: true
      })

      policy_evaluator = branch_policy_evalautor_for_branch(@repo, "somenewbranch")

      assert policy_evaluator
      assert_equal :allowed, policy_evaluator.commit_authorized_status(@user)
    end
  end

  context "branch protection disabled" do
    test "does not consider disabled branch protections" do
      protected_branch = create(:protected_branch, repository: @org_repo, name: "master")
      protected_branch.pull_request_reviews_enforcement_level = :everyone

      BranchProtectionsConfig.new(@org_repo).disable_branch_protection(actor: @org_admin)

      rule_evaluator = branch_policy_evalautor_for_branch(@org_repo, "master")
      assert_nil rule_evaluator
    end
  end
end
