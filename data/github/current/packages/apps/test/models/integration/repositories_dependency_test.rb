# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::RepositoriesDependencyTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @integration = create(:integration, default_permissions: { "metadata" => :read })

    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin)

    @org_member = create(:user)
    @org.add_member(@org_member)

    @private_repo = create(:private_repository, :minimal, owner: @org)
    @public_repo  = create(:repository, :minimal, owner: @org)

    @org_member_repo_admin = create(:user)
    @org.add_member(@org_member_repo_admin)
    @private_repo.add_member(@org_member_repo_admin, action: :admin)

    @repo_admin = create(:user)
    @private_repo.add_member(@repo_admin, action: :admin)

    @user  = create(:user)
    @rando = create(:user)
    @user_repo = create(:repository, :minimal, owner: @user)
  end

  context "accessible_repository_ids" do
    context "with current_integration_installation" do
      test "returns nothing if the installation does not belong to the integration" do
        installation = make_integration_installation(target: @org)

        options = {
          current_integration_installation: installation,
          repository_ids: [@private_repo.id],
        }

        refute_equal @integration.id, installation.integration_id
        assert_empty @integration.accessible_repository_ids(**options)
        assert_dogstats_distribution(1, "integration.accessible_repository_ids.count")
      end

      test "returns nothing if the installation is suspended" do
        installation = make_integration_installation(integration: @integration, target: @org)
        installation.suspend!; installation.reload

        options = {
          current_integration_installation: installation,
          repository_ids: [@private_repo.id],
        }

        assert_empty @integration.accessible_repository_ids(**options)
      end

      test "returns nothing if the installation does not have any of the requested permissions" do
        installation   = make_integration_installation(integration: @integration, target: @org)
        repository_ids = [@private_repo.id]

        options = {
          current_integration_installation: installation,
          repository_ids: repository_ids,
          permissions: ["issues"],
        }

        refute_includes @integration.default_permissions.keys, "issues"
        assert_empty @integration.accessible_repository_ids(**options)
      end

      test "returns what the installation has direct access to" do
        installation = make_integration_installation(integration: @integration, repository: @public_repo)

        options = {
          current_integration_installation: installation,
          repository_ids: [@public_repo.id, @private_repo.id],
        }

        assert_same_elements [@public_repo.id], @integration.accessible_repository_ids(**options)
      end
    end

    context "as a global app" do
      test "does not return repository IDs if the permission requested has not been granted" do
        integration    = create_privileged_app_with_capabilities(capabilities: { installed_globally: true })
        repository_ids = [@public_repo.id, @private_repo.id]

        refute_includes integration.default_permissions.keys, "issues"

        options = {
          current_integration_installation: nil,
          repository_ids: repository_ids,
          permissions: ["issues"],
        }

        assert_empty integration.accessible_repository_ids(**options)
      end

      test "returns all repository IDs given" do
        integration    = create_privileged_app_with_capabilities(capabilities: { installed_globally: true })
        repository_ids = [@public_repo.id, @private_repo.id]

        options = {
          current_integration_installation: nil,
          repository_ids: repository_ids,
        }

        assert_same_elements repository_ids, integration.accessible_repository_ids(**options)
      end
    end

    test "does not list repositories where the app does not have permission" do
      user_repository = create(:private_repository, :minimal, owner: @org_admin)

      make_integration_installation(integration: @integration, target: @org)
      make_integration_installation(integration: @integration, repository: user_repository, permissions: { "contents" => :read })

      expected_repository_ids = [user_repository.id]

      options = {
        current_integration_installation: nil,
        repository_ids: [@public_repo.id, @private_repo.id, user_repository.id],
        permissions: ["contents"],
      }

      assert_same_elements expected_repository_ids, @integration.accessible_repository_ids(**options)
    end

    test "does not list repositories that belong to a suspended installation" do
      user_repository = create(:private_repository, :minimal, owner: @org_admin)

      make_integration_installation(integration: @integration, repository: @private_repo)

      suspended_installation = make_integration_installation(integration: @integration, repository: user_repository)
      suspended_installation.suspend!

      expected_repository_ids = [@private_repo.id]

      options = {
        current_integration_installation: nil,
        repository_ids: [@public_repo.id, @private_repo.id, user_repository.id],
      }

      assert_same_elements expected_repository_ids, @integration.accessible_repository_ids(**options)
    end

    test "returns only the repository IDs the integration has direct access to" do
      user_repository = create(:private_repository, :minimal, owner: @org_admin)

      make_integration_installation(integration: @integration, repository: @private_repo)
      make_integration_installation(integration: @integration, repository: user_repository)

      expected_repository_ids = [@private_repo.id, user_repository.id]

      options = {
        current_integration_installation: nil,
        repository_ids: [@public_repo.id, @private_repo.id, user_repository.id],
      }

      assert_same_elements expected_repository_ids, @integration.accessible_repository_ids(**options)
    end
  end

  context "#accessible_repository_ids_by_owner" do
    context "with current_integration_installation" do
      test "returns nothing if the installation does not belong to the integration" do
        installation = make_integration_installation(target: @org)

        options = {
          current_integration_installation: installation,
          owner_and_repo_ids: { @private_repo.owner_id => [@private_repo.id] },
        }

        refute_equal @integration.id, installation.integration_id
        assert_empty @integration.accessible_repository_ids_by_owner(**options)
      end

      test "returns nothing if the installation is suspended" do
        installation = make_integration_installation(integration: @integration, target: @org)
        installation.suspend!; installation.reload

        options = {
          current_integration_installation: installation,
          owner_and_repo_ids: { @private_repo.owner_id => [@private_repo.id] },
        }

        assert_empty @integration.accessible_repository_ids_by_owner(**options)
      end

      test "returns nothing if the installation does not have any of the requested permissions" do
        installation   = make_integration_installation(integration: @integration, target: @org)
        repository_ids = [@private_repo.id]

        options = {
          current_integration_installation: installation,
          owner_and_repo_ids: { @private_repo.owner_id => [@private_repo.id] },
          resource: "issues",
        }

        refute_includes @integration.default_permissions.keys, "issues"
        assert_empty @integration.accessible_repository_ids_by_owner(**options)
      end

      test "returns what the installation has direct access to" do
        installation = make_integration_installation(integration: @integration, repository: @public_repo)

        options = {
          current_integration_installation: installation,
          owner_and_repo_ids: { @org.id => [@public_repo.id, @private_repo.id] },
        }

        assert_same_elements [@public_repo.id], @integration.accessible_repository_ids_by_owner(**options)
      end
    end

    context "as a global app" do
      test "does not return repository IDs if the permission requested has not been granted" do
        integration = create_privileged_app_with_capabilities(capabilities: { installed_globally: true })
        owner_and_repo_ids = { @org.id => [@public_repo.id, @private_repo.id] }

        refute_includes integration.default_permissions.keys, "issues"

        options = {
          current_integration_installation: nil,
          owner_and_repo_ids:,
          resource: "issues",
        }

        assert_empty integration.accessible_repository_ids_by_owner(**options)
      end

      test "returns all repository IDs given" do
        integration = create_privileged_app_with_capabilities(capabilities: { installed_globally: true })
        owner_and_repo_ids = { @org.id => [@public_repo.id, @private_repo.id] }

        options = {
          current_integration_installation: nil,
          owner_and_repo_ids:,
        }

        assert_same_elements [@public_repo.id, @private_repo.id], integration.accessible_repository_ids_by_owner(**options)
      end
    end

    test "does not list repositories where the app does not have permission" do
      user_repository = create(:private_repository, :minimal, owner: @org_admin)

      make_integration_installation(integration: @integration, target: @org)
      make_integration_installation(integration: @integration, repository: user_repository, permissions: { "contents" => :read })

      expected_repository_ids = [user_repository.id]

      options = {
        current_integration_installation: nil,
        owner_and_repo_ids: {
          @org.id => [@public_repo.id, @private_repo.id],
          user_repository.owner_id => [user_repository.id],
        },
        resource: "contents",
      }

      assert_same_elements expected_repository_ids, @integration.accessible_repository_ids_by_owner(**options)
    end

    test "does not list repositories that belong to a suspended installation" do
      user_repository = create(:private_repository, :minimal, owner: @org_admin)

      make_integration_installation(integration: @integration, repository: @private_repo)

      suspended_installation = make_integration_installation(integration: @integration, repository: user_repository)
      suspended_installation.suspend!

      expected_repository_ids = [@private_repo.id]

      options = {
        current_integration_installation: nil,
        owner_and_repo_ids: {
          @org.id => [@public_repo.id, @private_repo.id],
          user_repository.owner_id => [user_repository.id],
        },
      }

      assert_same_elements expected_repository_ids, @integration.accessible_repository_ids_by_owner(**options)
    end

    test "returns only the repository IDs the integration has direct access to" do
      user_repository = create(:private_repository, :minimal, owner: @org_admin)

      make_integration_installation(integration: @integration, repository: @private_repo)
      make_integration_installation(integration: @integration, repository: user_repository)

      expected_repository_ids = [@private_repo.id, user_repository.id]

      options = {
        current_integration_installation: nil,
        owner_and_repo_ids: {
          @org.id => [@public_repo.id, @private_repo.id],
          user_repository.owner_id => [user_repository.id],
        },
      }

      assert_same_elements expected_repository_ids, @integration.accessible_repository_ids_by_owner(**options)
    end
  end

  context "installable_repository_ids_on_by" do
    test "returns none if user target is not user actor" do
      repository_ids = @integration.installable_repository_ids_on_by(target: @user, actor: @rando)

      assert_predicate repository_ids, :empty?
    end

    test "returns all user owned repos if user target is user actor" do
      repository_ids = @integration.installable_repository_ids_on_by(target: @user, actor: @user)

      assert_equal @user.repository_ids, repository_ids
    end

    test "filters advisory workspace repositories for a user actor listing their own repositories" do
      GitHub.context.push(actor_id: @user.id)

      advisory1 = create(:repository_advisory, repository: @user_repo, author: @user)
      advisory2 = create(:repository_advisory, repository: @user_repo, author: @user)

      workspace_repo1 = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory1, @user).tap(&:save!)
      workspace_repo2 = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory2, @user).tap(&:save!)

      repository_ids =
        Integration::RepositoriesDependency.stub_const(:BATCH_SIZE, 2) do
          @integration.installable_repository_ids_on_by(target: @user, actor: @user)
        end

      refute_includes repository_ids, workspace_repo1.id
      refute_includes repository_ids, workspace_repo2.id
    end

    test "returns all org repos for org admin" do
      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)

      assert_equal @org.repository_ids, repository_ids
    end

    test "filters advisory workspace repositories for a org admin actor listing their org's repositories" do
      GitHub.context.push(actor_id: @org_admin.id)
      advisory       = create(:repository_advisory, repository: @public_repo, author: @org_admin)
      workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, @org_admin).tap(&:save!)

      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @admin)

      refute_includes repository_ids, workspace_repo.id
    end

    test "returns only repositories that are not installed if installation is not installed on target" do
      installed_repo = create(:repository, :minimal, owner: @org, name: "installed-repo")

      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)
      assert_equal @org.repository_ids, repository_ids

      @integration.install_on(@org,
                             repositories: [installed_repo],
                             installer: @org_admin,
                             entry_point: :test_case)

      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)

      assert_same_elements [@public_repo.id, @private_repo.id], repository_ids
    end

    test "does not return an advisory workspace repo even if it is not installed" do
      repo_to_be_installed = create(:repository, :minimal, owner: @org, name: "installed-repo")

      GitHub.context.push(actor_id: @org_admin.id)
      advisory = create(:repository_advisory, repository: @public_repo, author: @org_admin)
      workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, @org_admin).tap(&:save!)

      # ensure the at the workspace repo is available to the installer
      assert_includes @org.repositories, workspace_repo
      assert workspace_repo.adminable_by?(@org_admin)

      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)
      assert_same_elements [@public_repo.id, @private_repo.id, repo_to_be_installed.id], repository_ids

      make_integration_installation(integration: @integration, repository: repo_to_be_installed)
      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)

      assert_same_elements [@public_repo.id, @private_repo.id], repository_ids
    end

    test "returns all installable repositories for installations that are installed on the target" do
      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)
      assert_equal @org.repository_ids, repository_ids

      make_integration_installation(integration: @integration, target: @org)
      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)

      assert_same_elements [@public_repo.id, @private_repo.id], repository_ids
    end

    test "does not return an advisory workspace repo even if it is apart of the target" do
      GitHub.context.push(actor_id: @org_admin.id)
      advisory       = create(:repository_advisory, repository: @public_repo, author: @org_admin)
      workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, @org_admin).tap(&:save!)

      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)
      assert_same_elements @org.repositories.where.not(id: workspace_repo.id).ids, repository_ids

      make_integration_installation(integration: @integration, target: @org)
      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)

      assert_same_elements [@public_repo.id, @private_repo.id], repository_ids
    end

    test "returns all installable/installed repositories" do
      installed_repo = create(:repository, :minimal, owner: @org, name: "installed-repo")

      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)
      assert_equal @org.repository_ids, repository_ids

      make_integration_installation(integration: @integration, repository: installed_repo)
      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin, exclude_installed: false)

      assert_same_elements [@public_repo.id, @private_repo.id, installed_repo.id], repository_ids
    end

    test "does not return an advisory workspace repo event if it is an 'installable' repository" do
      GitHub.context.push(actor_id: @org_admin.id)
      advisory       = create(:repository_advisory, repository: @public_repo, author: @org_admin)
      workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, @org_admin).tap(&:save!)

      installed_repo = create(:repository, :minimal, owner: @org, name: "installed-repo")

      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)
      assert_same_elements @org.repositories.where.not(id: workspace_repo.id).ids, repository_ids

      make_integration_installation(integration: @integration, repository: installed_repo)
      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin, exclude_installed: false)

      assert_same_elements [@public_repo.id, @private_repo.id, installed_repo.id], repository_ids
    end

    test "returns none for org members who are not repo admins" do
      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_member)

      assert_predicate repository_ids, :empty?
    end

    test "returns none for rando" do
      repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @rando)

      assert_predicate repository_ids, :empty?
    end

    context "repo admin app management" do
      test "returns repositories actor can admin for non-org-owner org member who can admin repo" do
        repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_member_repo_admin)

        assert_equal [@private_repo.id], repository_ids
      end

      test "returns repositories actor can admin for outside collaborator admins as actors" do
        repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @repo_admin)

        assert_equal [@private_repo.id], repository_ids
      end

      test "returns only repositories that are not installed when not installable on all repositories" do
        installed_repo = create(:repository, :minimal, owner: @org, name: "installed-repo")

        repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_admin)
        assert_equal @org.repository_ids, repository_ids

        @integration.install_on(@org,
                               repositories: [installed_repo],
                               installer: @org_admin,
                               entry_point: :test_case)

        repository_ids = @integration.installable_repository_ids_on_by(target: @org, actor: @org_member_repo_admin)

        assert_same_elements [@private_repo.id], repository_ids
      end
    end
  end

  context "requestable_repository_ids_on_by" do
    test "returns none if user target is not user actor" do
      repository_ids = @integration.requestable_repository_ids_on_by(target: @user, actor: @rando)

      assert_predicate repository_ids, :empty?
    end

    test "returns none if user target is user actor" do
      repository_ids = @integration.requestable_repository_ids_on_by(target: @user, actor: @user)

      assert_predicate repository_ids, :empty?
    end

    test "returns none for org admins" do
      repository_ids = @integration.requestable_repository_ids_on_by(target: @org, actor: @org_admin)

      assert_predicate repository_ids, :empty?
    end

    context "Repo admin app management" do
      test "returns readable repos for org members" do
        repository_ids = @integration.requestable_repository_ids_on_by(target: @org, actor: @org_member)

        assert_same_elements [@private_repo.id, @public_repo.id], repository_ids
      end

      test "returns readable repos for org members that admin cannot install on" do
        repository_ids = @integration.requestable_repository_ids_on_by(target: @org, actor: @org_member_repo_admin)

        assert_same_elements [@public_repo.id], repository_ids
      end

      test "returns only uninstalled repos" do
        repository_ids = @integration.requestable_repository_ids_on_by(target: @org, actor: @org_member)

        assert_same_elements [@public_repo.id, @private_repo.id], repository_ids

        @integration.install_on(@org,
                                repositories: [@private_repo],
                                installer: @org_admin,
                                entry_point: :test_case)

        repository_ids = @integration.requestable_repository_ids_on_by(target: @org, actor: @org_member_repo_admin)

        assert_same_elements [@public_repo.id], repository_ids
      end

      test "returns all requested/requestable repositories" do
        repository_ids = @integration.requestable_repository_ids_on_by(target: @org, actor: @org_member)

        assert_same_elements [@public_repo.id, @private_repo.id], repository_ids

        @integration.install_on(@org,
                                repositories: [@private_repo],
                                installer: @org_admin,
                                entry_point: :test_case)

        repository_ids = @integration.requestable_repository_ids_on_by(target: @org, actor: @org_member_repo_admin, exclude_requested: false)

        assert_same_elements [@private_repo.id, @public_repo.id], repository_ids
      end

      test "returns direct access to private repos for outside collaborators" do
        private_repo2 = create(:private_repository, :minimal, owner: @org)
        private_repo2.add_member(@repo_admin, action: :write)

        repository_ids = @integration.requestable_repository_ids_on_by(target: @org, actor: @repo_admin)
        assert_same_elements [private_repo2.id], repository_ids
      end

      test "does not return internal repositories for org members", skip_if_feature_enabled: :requestable_repository_ids_on_by_with_internal_repos do
        business = create :business

        org = create :organization, business: business
        owner = org.admins.first

        org.update_default_repository_permission :none, actor: owner

        integration = create :integration, owner: org

        org_member = create :user
        org.add_member org_member

        internal_repo = create(:internal_repository, owner: org)
        private_repo = create(:private_repository, owner: org)

        repository_ids = integration.requestable_repository_ids_on_by(target: org, actor: org_member)

        assert_empty repository_ids
      end

      test "returns internal repositories for org members", skip_if_feature_disabled: :requestable_repository_ids_on_by_with_internal_repos do
        business = create :business

        org = create :organization, business: business
        owner = org.admins.first

        org.update_default_repository_permission :none, actor: owner

        integration = create :integration, owner: org

        org_member = create :user
        org.add_member org_member

        internal_repo = create(:internal_repository, owner: org)
        private_repo = create(:private_repository, owner: org)

        repository_ids = integration.requestable_repository_ids_on_by(target: org, actor: org_member)

        assert_same_elements [internal_repo.id], repository_ids
      end
    end
  end
end
