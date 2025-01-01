# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/launch/dynamic_workflow_helper"

class RepositoryActionsDependencyTest < GitHub::TestCase
  include Launch::DynamicWorkflowHelper

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end
  context "#actions_app_installed?" do
    test "returns false if launch_github_app does not exist" do
      GitHub.stubs(:launch_github_app).returns(nil)

      refute GitHub.launch_github_app
      refute create(:repository).actions_app_installed?
    end

    test "returns false if Actions is not installed on the repository" do
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      assert GitHub.launch_github_app
      refute create(:repository).actions_app_installed?
    end

    test "returns true if Actions is installed on the repository" do
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)
      repo = create(:repository, from_example: :simple)
      repo.enable_actions_app(entry_point: :test_case)

      assert GitHub.launch_github_app
      assert repo.actions_app_installed?
    end
  end

  context "#run_dynamic_workflow" do
    test "runs a dynamic workflow" do
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)
      disable_feature_flag(:launch_twirp_run_dynamic_workflow_lab)

      repo = create(:repository)

      mock_run_dynamic_workflow(repo:)

      repo.run_dynamic_workflow(
        actor: repo.owner,
        workflow: "on: push",
        ref: "refs/heads/main",
        inputs: {},
        workflow_name: "blank",
        slug: "test",
        integration_name: "actions",
        entry_point: :test_case,
      )
    end

    test "runs a dynamic workflow - Twirp Lab for the Dependabot integration" do
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)
      enable_feature_flag(:launch_twirp_run_dynamic_workflow_lab)

      repo = create(:repository)

      mock_run_dynamic_workflow(repo:, integration_name: "dependabot", use_lab: true)

      repo.run_dynamic_workflow(
        actor: repo.owner,
        workflow: "on: push",
        ref: "refs/heads/main",
        inputs: {},
        workflow_name: "blank",
        slug: "test",
        integration_name: "dependabot",
        entry_point: :test_case,
      )
    end

    test "does not install the Actions App when an installation does not exist" do
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)
      disable_feature_flag(:launch_twirp_run_dynamic_workflow_lab)

      owner = create(:user)
      repo = create(:repository, owner: owner)
      refute_predicate repo, :actions_app_installed?

      mock_run_dynamic_workflow(repo:)

      repo.run_dynamic_workflow(
        actor: owner,
        workflow: "on: push",
        ref: "refs/heads/main",
        inputs: {},
        workflow_name: "blank",
        slug: "test",
        integration_name: "actions",
        entry_point: :test_case,
      )

      refute_predicate repo, :actions_app_installed?
    end
  end
end

class ActionDetectionTest < GitHub::TestCase
  include RepositoryActionTestHelpers

  fixtures do
    @action_repo = create :repository, from_example: :javascript_action
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  context "#async_actions_plan_owner" do
    test "actions plan owner is the org for org owned repos", skip_with_all_emus: true do
      repo = create(:repository, :org_owned)
      plan_owner = repo.async_actions_plan_owner.sync

      assert_equal plan_owner.owner, repo.owner
      assert_predicate plan_owner.owner, :organization?
    end

    test "actions plan owner is the business if available for org owned repos" do
      org = create(:enterprise_linked_organization)
      repo = create(:repository, owner: org)

      plan_owner = repo.async_actions_plan_owner.sync

      assert_equal plan_owner.owner, repo.owner.business
    end

    test "does not return network owner for private forks", skip_with_all_emus: true do
      # Context: https://github.com/github/security/issues/3970
      private_repo = create(:private_repository, :org_owned)
      org = private_repo.owner
      private_repo.allow_private_repository_forking(actor: org.admin)

      org.allow_private_repository_forking(actor: org.admin)

      org_member = create(:user)
      org.add_member(org_member)

      private_fork = create(:fork_repository, forker: org_member, fork_repo: private_repo)

      plan_owner = private_fork.async_actions_plan_owner.sync

      refute_equal plan_owner.owner, private_repo.owner
      assert_equal plan_owner.owner, private_fork.owner
      assert_predicate plan_owner.owner, :user?
    end
  end

  test "identifies repositories with a action.yml" do
    assert_equal 0, @action_repo.actions.count

    @action_repo.update_default_branch("refs/heads/master")
    @action_repo.update_repository_actions

    assert_equal 2, @action_repo.actions.count

    action = @action_repo.actions.first

    assert_equal action.path, "action.yml"
    assert_equal action.name, "Hello World"
    assert_equal action.description, "Greet the world and record the time"
    assert_equal action.icon_name, "mic"
    assert_equal action.color, "28a745"
  end

  test "updates an existing action if it has changed" do
    action = create(:repository_action, path: "action.yml", repository: @action_repo)

    @action_repo.update_repository_actions

    # These are the values inside action.yml in the example repo.
    assert_equal action.reload.path, "action.yml"
    assert_equal action.name, "Hello World"
    assert_equal action.description, "Greet the world and record the time"
    assert_equal action.icon_name, "mic"
    assert_equal action.color, "28a745"
  end

  test "does not update existing Action if it is Listed", skip_with_all_emus: true do
    action = create(:repository_action, :listed)

    update_action_yml_file(user: action.owner, repo: action.repository, name: "Here is my new name",
                             color: "purple", description: "My new description", icon: "My new icon")

    action.repository.update_repository_actions

    refute_equal action.reload.name, "Here is my new name"
    refute_equal action.reload.description, "My new description"
  end

  test "does not update existing Action if it is Delisted", skip_with_all_emus: true do
    action = create(:repository_action, :listed)

    action.delisted!

    update_action_yml_file(user: action.owner, repo: action.repository, name: "Here is my new name",
                             color: "purple", description: "My new description", icon: "My new icon")

    action.repository.update_repository_actions

    refute_equal action.reload.name, "Here is my new name"
    refute_equal action.reload.description, "My new description"
  end

  test "handles repositories with multiple action.ymls"  do
    assert_equal 0, @action_repo.actions.count

    @action_repo.update_default_branch("refs/heads/sub_dir")
    @action_repo.update_repository_actions

    assert_equal 2, @action_repo.actions.count

    action = @action_repo.actions.find_by(path: "action.yml")
    other_action = @action_repo.actions.find_by(path: "another_action/action.yml")

    assert_equal action.name, "Hello World"
    assert_equal action.description, "Greet the world and record the time"
    assert_equal action.icon_name, "mic"
    assert_equal action.color, "28a745"

    assert_equal other_action.name, "Goodnight Moon"
    assert_equal other_action.description, "Wish the moon a pleasant evening and record the time"
    assert_equal other_action.icon_name, "log-out"
    assert_equal other_action.color, "1b1f23"
  end

  context "#action_ever_listed?" do
    test "returns true for repo with an action currently listed in the marketplace", skip_with_all_emus: true do
      action = create(:repository_action, :listed)
      repo = action.repository

      assert repo.action_ever_listed?
    end

    test "returns true for repo with an action previously listed in the marketplace" do
      action = create(:repository_action, :delisted)
      repo = action.repository

      assert repo.action_ever_listed?
    end

    test "returns false for repo with never listed action" do
      action = create(:repository_action, :unlisted)
      repo = action.repository

      refute repo.action_ever_listed?
    end
  end

  context "#global_relay_id" do
    test "returns the global_relay_id of an existing repository" do
      global_relay_id = Repository::ActionsDependency.global_relay_id(@action_repo.id)

      assert_equal @action_repo.global_relay_id, global_relay_id
    end

    test "returns the global_relay_id even after deleting the repository" do
      repo = create(:repository)
      repo.remove(User.ghost, synchronous: true)

      assert_nil Repositories::Public.find_active(repo.id)

      global_relay_id = Repository::ActionsDependency.global_relay_id(repo.id)

      assert_equal repo.global_relay_id, global_relay_id
    end

    test "returns a global_relay_id for a repository that has been purged" do
      repo = create(:repository)
      expected_global_relay_id = repo.global_relay_id
      repo.destroy!

      assert_nil Repository.find_by_id(repo.id)

      global_relay_id = Repository::ActionsDependency.global_relay_id(repo.id)
      assert_equal expected_global_relay_id, global_relay_id
    end

    test "returns a global_relay_id for a repository that has been purged on GHES", enterprise_only: true do
      repo = create(:repository)
      expected_global_relay_id = repo.global_relay_id
      repo.destroy!

      assert_nil Repository.find_by_id(repo.id)

      global_relay_id = Repository::ActionsDependency.global_relay_id(repo.id)
      assert_equal expected_global_relay_id, global_relay_id
    end

    unless GitHub.enterprise?
      test "returns the next_global_id of an existing repository legacy gid" do
        repo = create(:repository, created_at: DateTime.parse("2019-01-01"))
        next_global_id = Repository::ActionsDependency.global_relay_id(repo.id)

        assert_equal repo.next_global_id, next_global_id
      end

      test "returns the next_global_id even after deleting the repository legacy gid" do
        repo = create(:repository, created_at: DateTime.parse("2019-01-01"))
        repo.remove(User.ghost, synchronous: true)

        assert_nil Repositories::Public.find_active(repo.id)

        next_global_id = Repository::ActionsDependency.global_relay_id(repo.id)

        assert_equal repo.next_global_id, next_global_id
      end

      test "returns a next_global_id for a repository that has been purged legacy gid" do
        repo = create(:repository, created_at: DateTime.parse("2019-01-01"))
        expected_next_global_id = repo.next_global_id
        repo.destroy!

        assert_nil Repository.find_by_id(repo.id)

        next_global_id = Repository::ActionsDependency.global_relay_id(repo.id)
        assert_equal expected_next_global_id, next_global_id
      end

      test "returns a global_relay_id for a repository that has been purged on GHES legacy gid", enterprise_only: true do
        repo = create(:repository, created_at: DateTime.parse("2019-01-01"))
        expected_global_relay_id = repo.global_relay_id
        repo.destroy!

        assert_nil Repository.find_by_id(repo.id)

        global_relay_id = Repository::ActionsDependency.global_relay_id(repo.id)
        assert_equal expected_global_relay_id, global_relay_id
      end
    end
  end
end

class YamlParsingTest < GitHub::TestCase
  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  test "successfully parses valid Action metadata" do
    file_contents = <<~YAML
      name: 'Hello World'
      description: 'Greet the world and record the time'
      inputs:
        greeting:
          description: 'The greeting we choose - will print "{greeting}, World!" on stdout'
          required: true
          default: 'Hello'
      outputs:
        time:
          description: 'The time we did the greeting'
      branding:
        icon: 'mic'
        color: 'green'
      runs:
        using: 'docker'
        image: 'Dockerfile'
        args: ['${{ inputs.greeting }}']
    YAML

    repo = Repository.new
    tree_entry = TreeEntry.new(repo, { "data" => file_contents, "path" => "action.yml" })
    config_hash = repo.get_action_config_from_metadata_file(tree_entry)

    assert_equal true, config_hash[:is_action]
    assert_equal "Hello World", config_hash[:name]
    assert_equal "Greet the world and record the time", config_hash[:description]
    assert_equal "mic", config_hash[:icon_name]
    assert_equal "green", config_hash[:color]
  end

  test "successfully parses valid YAML that's not Actions metadata" do
    file_contents = <<~YAML
      this is valid yaml
    YAML

    repo = Repository.new
    tree_entry = TreeEntry.new(repo, { "data" => file_contents, "path" => "action.yml" })
    config_hash = repo.get_action_config_from_metadata_file(tree_entry)

    assert_equal false, config_hash[:is_action]
    assert_nil config_hash[:name]
    assert_nil config_hash[:description]
    assert_nil config_hash[:icon_name]
    assert_nil config_hash[:color]
  end

  test "handles invalid YAML" do
    file_contents = <<~YAML
      :this is not valid yaml
    YAML

    repo = Repository.new
    tree_entry = TreeEntry.new(repo, { "data" => file_contents, "path" => "action.yml" })
    config_hash = repo.get_action_config_from_metadata_file(tree_entry)

    assert_equal false, config_hash[:is_action]
    assert_nil config_hash[:name]
    assert_nil config_hash[:description]
    assert_nil config_hash[:icon_name]
    assert_nil config_hash[:color]
  end
end

class RepositoryActionAtRootTest < GitHub::TestCase
  include RepositoryActionTestHelpers

  fixtures do
    @repo = create(:repository)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  context "new_action_at_root ff off" do
    test "returns YAML Action at root" do
      disable_feature_flag(:new_action_at_root, @repo)
      action = create(:repository_action, repository: @repo, path: "action.yml")

      assert_equal action, @repo.action_at_root
    end

    test "returns YAML Action at root using .yaml extension" do
      disable_feature_flag(:new_action_at_root, @repo)
      action = create(:repository_action, repository: @repo, path: "action.yaml")

      assert_equal action, @repo.action_at_root
    end

    test ".yml takes precedence over .yaml" do
      disable_feature_flag(:new_action_at_root, @repo)
      yml_action = create(:repository_action, repository: @repo, path: "action.yml")
      yaml_action = create(:repository_action, repository: @repo, path: "action.yaml")

      assert_equal yml_action, @repo.action_at_root
    end

    test "does not return Action not at root" do
      disable_feature_flag(:new_action_at_root, @repo)
      action = create(:repository_action, repository: @repo, path: "subdirectory/action.yml")

      assert_nil @repo.action_at_root
    end
  end


  context "new_action_at_root ff on" do
    test "returns YML Action at root using .yml extension" do
      repo = create(:repository, from_example: :javascript_action)
      enable_feature_flag(:new_action_at_root, repo)
      repo.update_default_branch("refs/heads/master")
      action = create(:repository_action, repository: repo, path: "action.yml")
      update_action_yml_file(user: repo.owner, repo: repo, name: "Here is my new name",
        color: "purple", description: "My new description", icon: "My new icon")

      assert_equal action, repo.action_at_root
    end

    test "returns YAML Action at root using .yaml extension" do
      repo = create(:repository, from_example: :javascript_action)
      enable_feature_flag(:new_action_at_root, repo)
      repo.update_default_branch("refs/heads/master")
      action = create(:repository_action, repository: repo, path: "action.yaml")
      update_action_yml_file(user: repo.owner, repo: repo, name: "Here is my new name",
        color: "purple", description: "My new description", icon: "My new icon", path: "action.yaml")
      assert_equal action, repo.action_at_root
    end

    test "does not return Action not at root" do
      repo = create(:repository, from_example: :javascript_action)
      enable_feature_flag(:new_action_at_root, repo)
      repo.update_default_branch("refs/heads/master")
      action = create(:repository_action, repository: repo, path: "subdirectory/action.yml")
      update_action_yml_file(user: repo.owner, repo: repo, name: "Here is my new name",
        color: "purple", description: "My new description", icon: "My new icon", path: "subdirectory/action.yaml")
      assert_nil repo.action_at_root
    end


    test "returns correct Repository action for YAML/YML paths depending on which file exists on the default branchs" do
      repo = create(:repository, from_example: :javascript_action)
      enable_feature_flag(:new_action_at_root, repo)
      repo.update_default_branch("refs/heads/master")
      update_action_yml_file(user: repo.owner, repo: repo, name: "Here is my new name",
        color: "purple", description: "My new description", icon: "My new icon")

      # list the marketplace action onto the repo and remove the previous one
      yml_repo_action = create(:repository_action, :listed,  repository: repo, path: "action.yml")
      assert_equal yml_repo_action, repo.action_at_root
      # delete the action.yml file from the branch and update it with an action.yaml file
      ref = repo.heads.find(repo.default_branch)
      ref.append_commit({ committer: repo.owner, message: "deleting action.yml" }, repo.owner) do |changes|
        changes.remove("action.yml")
      end
      # update the branch with the new yaml file and create a repository action for it
      update_action_yml_file(user: repo.owner, repo: repo, name: "Here is my new name in a new yaml",
        color: "green", description: "My new description aprt 2", icon: "My new icon v2", path: "action.yaml")
      yaml_repo_action = create(:repository_action, repository: repo, path: "action.yaml")
      current_action_at_root = repo.action_at_root
      assert_equal yaml_repo_action, current_action_at_root
      assert_equal 2, repo.actions.count
    end
  end


end

class RepositoryActionsPermissionsTest < GitHub::TestCase
  context "#highest_level_allowlist" do
    test "returns the business allowlist for a business owned repo" do
      repo = create(:repository, :enterprise_linked_org_owned)
      business = repo.organization.business

      repo_allowlist = create(:actions_policy_allowlist, entity: repo)
      business_allowlist = create(:actions_policy_allowlist, entity: business)

      assert_equal business_allowlist, repo.highest_level_allowlist
    end

    test "returns the organization allowlist when the business allowlist does not exist" do
      repo = create(:repository, :enterprise_linked_org_owned)
      org = repo.organization
      business = repo.organization.business

      repo_allowlist = create(:actions_policy_allowlist, entity: repo)
      org_allowlist = create(:actions_policy_allowlist, entity: org)

      assert_equal org_allowlist, repo.highest_level_allowlist
    end

    test "defaults to the repo allowlist for when no other lists exist" do
      repo = create(:repository, :enterprise_linked_org_owned)

      repo_allowlist = create(:actions_policy_allowlist, entity: repo)

      assert_equal repo_allowlist, repo.highest_level_allowlist
    end

    if GitHub.enterprise?
      test "returns the Global Business allowlist for a user owned repo" do
        repo = create(:repository)
        global_business = create(:global_business)

        repo_allowlist = create(:actions_policy_allowlist, entity: repo)
        global_business_allowlist = create(:actions_policy_allowlist, entity: global_business)

        assert_equal global_business_allowlist, repo.highest_level_allowlist
      end
    else
      test "returns the user allowlist for a user owned repo" do
        repo = create(:repository)
        repo_allowlist = create(:actions_policy_allowlist, entity: repo)

        assert_equal repo_allowlist, repo.highest_level_allowlist
      end
    end
  end

  context "#lowest_level_allowlist" do
    test "returns the repository allowlist for a business owned repo" do
      repo = create(:repository, :enterprise_linked_org_owned)
      business = repo.organization.business

      repo_allowlist = create(:actions_policy_allowlist, entity: repo)
      business_allowlist = create(:actions_policy_allowlist, entity: business)

      assert_equal repo_allowlist, repo.lowest_level_allowlist
    end

    test "defaults to the repo allowlist for when no other lists exist" do
      repo = create(:repository, :enterprise_linked_org_owned)

      repo_allowlist = create(:actions_policy_allowlist, entity: repo)

      assert_equal repo_allowlist, repo.lowest_level_allowlist
    end

    test "returns the business allowlist when the repository and org lists do not exist" do
      repo = create(:repository, :enterprise_linked_org_owned)
      business = repo.organization.business

      business_allowlist = create(:actions_policy_allowlist, entity: business)

      assert_equal business_allowlist, repo.lowest_level_allowlist
    end

    test "returns the org allowlist when the repository list does not exist" do
      repo = create(:repository, :enterprise_linked_org_owned)
      org = repo.organization

      org_allowlist = create(:actions_policy_allowlist, entity: org)

      assert_equal org_allowlist, repo.lowest_level_allowlist
    end

    if GitHub.enterprise?
      test "returns the Global Business allowlist for a user owned repo when the user list does not exist" do
        repo = create(:repository)
        global_business = create(:global_business)
        global_business_allowlist = create(:actions_policy_allowlist, entity: global_business)

        assert_equal global_business_allowlist, repo.lowest_level_allowlist
      end

      test "returns the user allowlist for a user owned repo when the Global Business allowlist does not exist" do
        repo = create(:repository)
        repo_allowlist = create(:actions_policy_allowlist, entity: repo)

        assert_equal repo_allowlist, repo.lowest_level_allowlist
      end
    else
      test "returns the user allowlist for a user owned repo" do
        repo = create(:repository)
        repo_allowlist = create(:actions_policy_allowlist, entity: repo)

        assert_equal repo_allowlist, repo.lowest_level_allowlist
      end
    end
  end

  context "Default workflow permissions" do
    test "workflow write permissions are set to read for user owned repositories" do
      user = create :user
      result = Repository.handle_creation(user, user.display_login, { name: "empty-create-test" })
      repo = result.repository

      if GitHub.flipper[:actions_default_workflow_permissions_new_repos].enabled?
        assert repo.actions_default_workflow_permissions_read_only?
      else
        refute repo.actions_default_workflow_permissions_read_only?
      end
    end

    test "workflow write permissions are set to inherit/write for organization owned repositories" do
      org_admin = create(:user, login: "org-admin")
      org = create(:organization, admin: org_admin, plan: "diamond")
      org.set_default_workflow_permissions("write", org_admin)

      repo = create :repository, owner: org

      refute repo.actions_default_workflow_permissions_read_only?
    end

    test "workflow PR approval permissions are set to disallow for user owned repositories", skip_with_all_emus: true do
      user = create :user
      result = Repository.handle_creation(user, user.display_login, { name: "empty-create-test" })
      repo = result.repository

      if GitHub.flipper[:actions_default_workflow_permissions_new_repos].enabled?
        refute repo.actions_workflow_permission_can_approve_pr?
      else
        assert repo.actions_workflow_permission_can_approve_pr?
      end
    end

    test "workflow PR approval permissions are set to inherit/allow for organization owned repositories" do
      org_admin = create(:user, login: "org-admin")
      org = create(:organization, admin: org_admin, plan: "diamond")
      org.set_actions_workflow_permission_can_approve_pr(true, org_admin)

      repo = create :repository, owner: org

      assert repo.actions_workflow_permission_can_approve_pr?
    end
  end

  context "#show_actions?" do
    test "true if actions disabled but actions setup is pending" do
      GitHub.stubs(:actions_enabled?).returns(false)
      GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(true)

      user = create(:user)
      repo = create(:private_repository, owner: user)

      repo.disable_actions(actor: user)

      # Double-check staged data
      assert repo.actions_disabled?

      assert repo.show_actions?
    end

    test "false if actions disabled and actions setup is not pending" do
      GitHub.stubs(:actions_enabled?).returns(false)
      GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(false)

      user = create(:user)
      repo = create(:private_repository, owner: user)

      repo.disable_actions(actor: user)

      # Double-check staged data
      assert repo.actions_disabled?

      refute repo.show_actions?(include_pending_setup: false)
    end

    if GitHub.enterprise?
      test "false even if actions are enabled on a repository" do
        user = create(:user)
        repo = create(:private_repository, owner: user)

        repo.enable_actions(actor: user)

        # Double-check staged data
        assert repo.actions_enabled?

        refute repo.show_actions?(include_pending_setup: false)
      end

      test "true if actions are disabled on the repo but not by the owner and there is at least one required workflow" do
        org_admin = create(:user, login: "org-admin")
        org       = create(:organization, admin: org_admin)
        org_repo  = create(:repository, owner: org)
        org_repo2 = create(:repository, owner: org)

        # Stubbing a required workflow by ensuring the imposer_repository_id is not null
        create(
          :workflow,
          repository: org_repo,
          name: "Lint",
          path: ".github/workflows/lint_super.yml",
          imposer_repository_id: org_repo2.id
        )

        org_repo.disable_actions(actor: org_admin)

        # Double-check staged data
        assert org_repo.actions_disabled?

        assert org_repo.show_actions?
      end
    else # non-enterprise, dotcom tests only
      test "false if actions are disabled on a repository" do
        user = create(:user)
        repo = create(:private_repository, owner: user)

        repo.disable_actions(actor: user)

        # Double-check staged data
        refute repo.actions_enabled?

        refute repo.show_actions?
      end

      test "true if actions are enabled on a repository" do
        user = create(:user)
        repo = create(:private_repository, owner: user)

        repo.enable_actions(actor: user)

        # Double-check staged data
        assert repo.actions_enabled?

        assert repo.show_actions?
      end

      test "true if actions are disabled on the repo but not by the owner and there is at least one required workflow" do
        org_admin = create(:user, login: "org-admin")
        org       = create(:organization, admin: org_admin)
        org_repo  = create(:repository, owner: org)
        org_repo2 = create(:repository, owner: org)

        # Stubbing a required workflow by ensuring the imposer_repository_id is not null
        create(
          :workflow,
          repository: org_repo,
          name: "Lint",
          path: ".github/workflows/lint_super.yml",
          imposer_repository_id: org_repo2.id
        )

        org_repo.disable_actions(actor: org_admin)

        # Double-check staged data
        assert org_repo.actions_disabled?

        assert org_repo.show_actions?
      end

      test "false if repo is an advisory workspace and the root repo has actions disabled" do
        user      = create(:user)
        repo      = create(:private_repository, owner: user)
        advisory  = create(:repository_advisory, :with_workspace, repository: repo, author: user)
        workspace = advisory.workspace_repository

        repo.disable_actions(actor: user)
        enable_feature_flag(:maintainer_love_advisory_workspaces_can_use_actions, repo)

        # Double-check staged data
        refute repo.actions_enabled?
        assert workspace.actions_enabled?

        refute workspace.show_actions?
      end

      test "true if repo is an advisory workspace and the root repo has actions enabled" do
        user      = create(:user)
        repo      = create(:private_repository, owner: user)
        advisory  = create(:repository_advisory, :with_workspace, repository: repo, author: user)
        workspace = advisory.workspace_repository

        repo.enable_actions(actor: user)
        enable_feature_flag(:maintainer_love_advisory_workspaces_can_use_actions, repo)
        workspace.disable_actions(actor: user)

        # Double-check staged data
        assert repo.actions_enabled?
        refute workspace.actions_enabled?

        assert workspace.show_actions?
      end

      test "false if repo is an advisory workspace and the root repo has actions enabled but does not have maintainer_love_advisory_workspaces_can_use_actions feature enabled" do
        user      = create(:user)
        repo      = create(:private_repository, owner: user)
        advisory  = create(:repository_advisory, :with_workspace, repository: repo, author: user)
        workspace = advisory.workspace_repository

        repo.enable_actions(actor: user)
        disable_feature_flag(:maintainer_love_advisory_workspaces_can_use_actions, repo)
        workspace.enable_actions(actor: user)

        # Double-check staged data
        assert repo.actions_enabled?
        assert workspace.actions_enabled?

        refute workspace.show_actions?
      end
    end
  end
end

class AbilitiesTest < GitHub::TestCase
  fixtures do
    @action_repo = create(:repository)
  end

  context "#can_emit_actions_audit_logs?" do
    unless GitHub.enterprise?
      test "can emit events when actions is enabled and on business plus plan" do
        GitHub.stubs(:actions_enabled?).returns(true)
        action_repo = create(:repository, :enterprise_linked_org_owned)

        assert action_repo.can_emit_actions_audit_logs?
      end

      test "cannot emit events when actions is enabled but not on an allowed plan", skip_with_all_emus: true do
        GitHub.stubs(:actions_enabled?).returns(true)
        action_repo = create(:repository)

        refute action_repo.can_emit_actions_audit_logs?
      end
    end

    if GitHub.enterprise?
      test "can emit events when actions is enabled and on enterprise" do
        GitHub.stubs(:actions_enabled?).returns(true)
        org = create(:organization, plan: "enterprise")
        action_repo = create(:repository, organization: org)

        assert action_repo.can_emit_actions_audit_logs?
      end
    end

    test "cannot emit events when actions is not enabled" do
      GitHub.stubs(:actions_enabled?).returns(false)
      action_repo = create(:repository)

      refute action_repo.can_emit_actions_audit_logs?
    end
  end
end

module RepositoryPlanSharedTest
  extend ActiveSupport::Concern

  included do
    test "plan" do
      GitHub.stubs(:actions_enabled?).returns(true)
      assert @action_repo.can_use_environments?
      assert @action_repo.can_use_environments_api?
      refute @action_repo.can_use_deployment_branch_gates? unless GitHub.enterprise? # GitHub enterprise can have deploy branch gates
      assert @action_repo.can_use_deployment_protected_branch?
    end
  end
end

class RepositoryUseTeamPlanTest < GitHub::TestCase
  skip_with_all_emus

  include RepositoryPlanSharedTest

  fixtures do
    @user = create(:organization, plan: "business")
    @action_repo = create(:private_repository, owner: @user)
  end
end

class RepositoryUseProPlanTest < GitHub::TestCase
  skip_with_all_emus

  include RepositoryPlanSharedTest

  fixtures do
    @user = create(:user, plan: "pro")
    @action_repo = create(:private_repository, owner: @user)
  end
end
