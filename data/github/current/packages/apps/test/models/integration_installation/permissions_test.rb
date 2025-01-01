# typed: true
# frozen_string_literal: true

require "test_helper"

#
# NOTE: Target specific test cases (e.g. for Business, User, Org targets) are in
#
#        test/models/integration_installation/permission_target_test.rb
#

class IntegrationInstallation::PermissionsTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner

    @admin     = create(:user, login: "org-admin")
    @org       = create(:organization, admin: @admin)
    @rando     = create(:user, login: "rando")
    @noora     = create(:user, login: "noora")
    @business  = create(:business, owners: [@admin])

    @app_owner   = create(:user, login: "app-owner")
    @integration = create(:integration, owner: @app_owner)

    @installation = make_integration_installation(target: @org, integration: @integration, permissions: { "metadata" => :read })

    @repo_with_admin = create(:repository, :minimal, owner: @org)
    @repo_with_admin.add_member(@noora, action: :admin)

    @repo_with_admin2 = create(:repository, :minimal, owner: @org)
    @repo_with_admin2.add_member(@noora, action: :admin)

    @repo_admin_integration  = create(:integration, owner: @app_owner)
    @repo_admin_installation = make_integration_installation(integration: @repo_admin_integration, repository: @repo_with_admin, permissions: { "metadata" => :read })
  end

  def setup
    GitHub.flipper[:repo_subset_limit_for_installations].disable
  end

  context "ACTION :admin" do
    test "is permitted when target is adminable_by? actor" do
      assert @org.adminable_by?(@admin)

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @admin, action: :admin)

      assert_predicate result, :permitted?
    end

    test "is not permitted when target is adminable_by? actor" do
      refute @org.adminable_by?(@rando)

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @rando, action: :admin)

      refute_predicate result, :permitted?
      assert_equal result.reason, :not_adminable_by
    end
  end

  context "ACTION :update_permissions" do
    test "is permitted when the (User) target is adminable_by? actor" do
      assert @admin.adminable_by?(@admin)

      @integration.update(default_permissions: { "metadata" => :read })
      version = @integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor:        @admin,
        action:       :update_permissions,
        version:      version,
      )

      assert_predicate result, :permitted?
    end

    test "is not permitted when the (User) target is not adminable_by? actor" do
      installation = make_integration_installation(target: @admin, integration: @integration)

      rando = create(:user)
      refute @admin.adminable_by?(rando)

      @integration.update(default_permissions: { "metadata" => :read })
      version = @integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: installation,
        actor:        rando,
        action:       :update_permissions,
        version:      version,
      )

      refute_predicate result, :permitted?
      assert_equal :target_not_organization, result.reason
    end

    test "is permitted when the (Organization) target is adminable_by? actor" do
      assert @org.adminable_by?(@admin)

      @integration.update(default_permissions: { "metadata" => :read })
      @integration.reload

      version = @integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor:        @admin,
        action:       :update_permissions,
        version:      version,
      )

      assert_predicate result, :permitted?
    end

    test "only org admin's can update an installation if there aren't any permissions" do
      refute @org.adminable_by?(@noora)

      @integration.update(default_permissions: {})
      @integration.reload

      version = @integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor:        @noora,
        action:       :update_permissions,
        version:      version,
      )

      refute_predicate result, :permitted?
      assert_equal :not_adminable_by, result.reason
    end

    test "only org admin's can update an installation with new organization permissions" do
      refute @org.adminable_by?(@noora)

      @integration.update(default_permissions: { "members" => :read })
      @integration.reload

      version = @integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor:        @noora,
        action:       :update_permissions,
        version:      version,
      )

      refute_predicate result, :permitted?
      assert_equal :requires_org_permissions, result.reason
    end

    test "only org admin's can update an installation with upgraded organization permissions" do
      integration = create(:integration, owner: @app_owner)
      installation = make_integration_installation(target: @org, integration: integration, permissions: { "members" => :read })

      refute @org.adminable_by?(@noora)

      integration.update(default_permissions: { "members" => :write })
      integration.reload

      version = integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: installation,
        actor:        @noora,
        action:       :update_permissions,
        version:      version,
      )

      refute_predicate result, :permitted?
      assert_equal :requires_org_permissions, result.reason
    end

    test "requires a non admin actor to be able to admin all of the installation's repositories" do
      refute @org.adminable_by?(@noora)

      repo = create(:repository, :minimal, owner: @org)
      refute repo.adminable_by?(@noora)

      @integration.update(default_permissions: { "metadata" => :read })
      @integration.reload

      version = @integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor:        @noora,
        action:       :update_permissions,
        version:      version,
      )

      refute_predicate result, :permitted?
      assert_equal result.reason, :not_admin_on_subset
    end

    test "does not allow 'administration' => :write to be set by non target admins" do
      refute @org.adminable_by?(@noora)

      repo = create(:repository, :minimal, owner: @org)
      refute repo.adminable_by?(@noora)

      @repo_admin_integration.update(default_permissions: { "metadata" => :read, "administration" => :write })
      @repo_admin_integration.reload

      version = @repo_admin_integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor:        @noora,
        action:       :update_permissions,
        version:      version,
      )

      refute_predicate result, :permitted?
      assert_equal :not_adminable_by, result.reason
    end

    test "does not allow upgrading 'administration' => :read to :write non target admins" do
      refute @org.adminable_by?(@noora)

      repo = create(:repository, :minimal, owner: @org)
      refute repo.adminable_by?(@noora)

      repo_admin_integration  = create(:integration, owner: @app_owner, default_permissions: { "metadata" => :read, "administration" => :read })
      repo_admin_installation = make_integration_installation(integration: repo_admin_integration, repository: @repo_with_admin)

      repo_admin_integration.update(default_permissions: { "metadata" => :read, "administration" => :write })
      repo_admin_integration.reload

      version = repo_admin_integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: repo_admin_installation,
        actor:        @noora,
        action:       :update_permissions,
        version:      version,
      )

      refute_predicate result, :permitted?
      assert_equal :not_adminable_by, result.reason
    end

    test "allows a noora to accept an update with 'administration' => :write as a permission if it was already set" do
      refute @org.adminable_by?(@noora)

      repo = create(:repository, :minimal, owner: @org)
      refute repo.adminable_by?(@noora)

      repo_admin_integration  = create(:integration, owner: @app_owner, default_permissions: { "metadata" => :read, "administration" => :write })
      repo_admin_installation = make_integration_installation(integration: repo_admin_integration, repository: @repo_with_admin)

      repo_admin_integration.update(default_permissions: { "metadata" => :read, "administration" => :write, "issues" => :write })
      repo_admin_integration.reload

      version = repo_admin_integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: repo_admin_installation,
        actor:        @noora,
        action:       :update_permissions,
        version:      version,
      )

      assert_predicate result, :permitted?
    end

    test "all added subject_types must be apart of Repository::Resources.subject_types" do
      refute @org.adminable_by?(@noora)

      repo = create(:repository, :minimal, owner: @org)
      refute repo.adminable_by?(@noora)

      @repo_admin_integration.update(default_permissions: { "metadata" => :read, "emails" => :read })
      @repo_admin_integration.reload

      version = @repo_admin_integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor:        @noora,
        action:       :update_permissions,
        version:      version,
      )

      refute_predicate result, :permitted?
      assert_equal :not_adminable_by, result.reason
    end

    test "is permitted when the actor can admin all of the installation's on the target" do
      refute @org.adminable_by?(@noora)

      repo = create(:repository, :minimal, owner: @org)
      refute repo.adminable_by?(@noora)

      @repo_admin_integration.update(default_permissions: { "metadata" => :read })
      @repo_admin_integration.reload

      version = @repo_admin_integration.latest_version

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor:        @noora,
        action:       :update_permissions,
        version:      version,
      )

      assert_predicate result, :permitted?
    end
  end

  context "ACTION :can_view_installation" do
    test "is permitted when the actor is the target" do
      installation = make_integration_installation(integration: @integration, target: @admin)
      result = IntegrationInstallation::Permissions.check(installation: installation, actor: @admin, action: :view, target: @admin)

      assert_predicate result, :permitted?
      assert_equal :is_admin, result.reason
    end

    test "is permitted when the actor can admin the target" do
      assert @org.adminable_by?(@admin), "expected #{@org} to be able to admin #{@admin}"

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @admin, action: :view, target: @org)

      assert_predicate result, :permitted?
      assert_equal :is_admin, result.reason
    end

    test "is permitted for org members" do
      org_member = create(:user)
      @org.add_member(org_member, action: :read)

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: org_member, action: :view, target: @org)

      assert_predicate result, :permitted?
      assert_equal :organization_member, result.reason
    end

    test "is permitted for org repository admins (non-org owner repo admin)" do
      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @noora, action: :view, target: @org)

      assert_predicate result, :permitted?
      assert_equal :outside_collaborator, result.reason
    end

    test "is permitted for non admin org repository outside collaborators" do
      org_repo = create(:repository, :minimal, owner: @org)
      collaborator = create(:user)
      org_repo.add_member(collaborator, action: :read)

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: collaborator, action: :view, target: @org)

      assert_predicate result, :permitted?
      assert_equal :outside_collaborator, result.reason
    end

    test "is not permitted if the actor is not apart of the org in anyway" do
      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @rando, action: :view, target: @org)

      refute_predicate result, :permitted?
      assert_equal :not_part_of_organization, result.reason
    end
  end

  context "ACTION :install_all_repositories" do
    test "is permitted when target is adminable_by? actor" do
      assert @org.adminable_by?(@admin)

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @admin, action: :admin)

      assert_predicate result, :permitted?
    end

    test "is not permitted when target is not adminable_by? actor" do
      refute @org.adminable_by?(@rando)

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @rando, action: :install_all_repositories)

      refute_predicate result, :permitted?
      assert_equal result.reason, :all_repositories
    end

    test "is not permitted if the actor has no verified email and app requires OAuth on install", skip_enterprise: true do
      assert @admin.adminable_by?(@admin)
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      @admin.require_email_verification!
      @admin.emails.verified.each(&:unverify!)

      @repo_admin_integration.update(application_callback_urls_attributes: [{ url: "https://example.com" }], request_oauth_on_install: true)
      @repo_admin_integration.reload

      repo = create(:repository, :minimal, owner: @org)
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :install_all_repositories
      )

      refute_predicate result, :permitted?
      assert_equal :missing_verified_email, result.reason
    end

    test "is permitted if the actor has no verified email within Enterprise and app requires OAuth on install", enterprise_only: true do
      assert @admin.adminable_by?(@admin)
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      @admin.require_email_verification!
      @admin.emails.verified.each(&:unverify!)

      @repo_admin_integration.update(application_callback_urls_attributes: [{ url: "https://example.com" }], request_oauth_on_install: true)
      @repo_admin_integration.reload

      repo = create(:repository, :minimal, owner: @org)
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :install_all_repositories
      )

      assert_predicate result, :permitted?
    end
  end

  context "ACTION :add_repositories" do
    test "requires repositories" do
      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @admin, action: :add_repositories)

      refute_predicate result, :permitted?
      assert_equal result.reason, :no_repositories_submitted
    end

    test "is not permitted if any of the repositories do not belong to the target" do
      rando_repo = create(:repository, :minimal, owner: create(:user))

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor: @admin,
        action: :add_repositories,
        repositories: [rando_repo],
      )

      refute_predicate result, :permitted?
      assert_equal result.reason, :not_owned_by_target
    end

    test "is permitted when target can_admin?" do
      assert @org.adminable_by?(@admin)

      repo = create(:repository, :minimal, owner: @org)
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :add_repositories,
        repositories: [repo],
      )

      assert_predicate result, :permitted?
      assert_equal result.reason, :is_admin
    end

    test "is permitted when the actor is a Bot, all repositories are owned by the target and installation on target check is skipped" do
      @integration.bot.installation = @installation

      repo_one = create(:repository, :minimal, owner: @org)
      repo_two = create(:repository, :minimal, owner: @org)

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor: @integration.bot,
        action: :add_repositories,
        repositories: [repo_one, repo_two],
        skip_installed_on_target_check: true,
      )

      assert_predicate result, :permitted?
      assert_equal result.reason, :is_app_actor
    end

    test "is not permitted when the actor is a Bot and the repositories belong to different targets" do
      @integration.bot.installation = @installation

      rando = create(:organization)
      repo_one = create(:repository, :minimal, owner: @org)
      repo_two = create(:repository, :minimal, owner: rando)

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor: @integration.bot,
        action: :add_repositories,
        repositories: [repo_one, repo_two],
        skip_installed_on_target_check: true,
      )

      refute_predicate result, :permitted?
      assert_equal result.reason, :not_owned_by_target
    end

    test "is not permitted when the repository is already installed" do
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @noora,
        action: :add_repositories,
        repositories: [@repo_with_admin],
      )

      refute_predicate result, :permitted?
      assert_equal result.reason, :already_installed
    end

    test "is permitted when the repository is already installed and the skip check is provided" do
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @noora,
        action: :add_repositories,
        repositories: [@repo_with_admin],
        skip_installed_on_target_check: true
      )

      assert_predicate result, :permitted?
    end

    test "is permitted when the app requires org permissions" do
      @repo_admin_installation.stubs(:permissions).returns({ Organization::Resources.subject_types.first => :write })

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @noora,
        action: :add_repositories,
        repositories: [@repo_with_admin2],
      )

      assert_predicate result, :permitted?
    end

    test "is permitted when target can admin all repos" do
      repo_with_admin2 = create(:repository, :minimal, owner: @org)
      repo_with_admin2.add_member(@noora, action: :admin)

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @noora,
        action: :add_repositories,
        repositories: [repo_with_admin2],
      )

      assert_predicate result, :permitted?
      assert_equal result.reason, :admin_on_selected_repos
    end

    test "it emits repositories size metric" do
      assert @org.adminable_by?(@admin)

      repo = create(:repository, :minimal, owner: @org)
      IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :add_repositories,
        repositories: [repo],
      )

      assert_dogstats_distribution 1, "integration_installation.permissions.repositories.size", tag: { action: :add_repositories }
    end

    test "is not permitted when target cannot admin all repos" do
      repo = create(:repository, :minimal, owner: @org)

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @noora,
        action: :add_repositories,
        repositories: [repo],
      )

      refute_predicate result, :permitted?
      assert_equal result.reason, :not_admin_on_subset
    end

    test "does not allow workspace advisory repository to be added by default" do
      repository = create(:repository, :minimal, owner: @org)
      author     = @admin

      GitHub.context.push(actor_id: author.id)

      advisory1 = create(:repository_advisory, repository: repository, author: author)
      workspace_repo1 = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory1, author).tap(&:save!)

      advisory2 = create(:repository_advisory, repository: repository, author: author)
      workspace_repo2 = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory2, author).tap(&:save!)

      result =
        Integration::Permissions.stub_const(:BATCH_SIZE, 1) do
          IntegrationInstallation::Permissions.check(
            installation: @repo_admin_installation,
            actor: @admin,
            action: :add_repositories,
            repositories: [workspace_repo1, workspace_repo2],
          )
        end

      refute_predicate result, :permitted?
      assert_equal :advisory_workspace_repo_included, result.reason
    end

    test "allows workspace advisory repos to be added if the app has the capability" do
      repository = create(:repository, :minimal, owner: @org)
      author     = @admin
      advisory   = create(:repository_advisory, repository: repository, author: author)

      GitHub.context.push(actor_id: author.id)
      workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, author).tap(&:save!)

      integration  = create_privileged_app_with_capabilities(
        permissions: { "metadata" => :read },
        capabilities: { can_install_on_security_advisory_repos: true },
        options: { owner: @app_owner },
      )

      installation = make_integration_installation(
        integration: integration,
        repository: @repo_with_admin,
        permissions: { "metadata" => :read },
      )

      result = IntegrationInstallation::Permissions.check(
        installation: installation,
        actor: @admin,
        action: :add_repositories,
        repositories: [workspace_repo],
      )

      assert_predicate result, :permitted?
    end

    test "is not permitted when any of the repositories are pending transfer" do
      assert @org.adminable_by?(@admin)

      repo = create(:repository, :minimal, owner: @org)
      RepositoryOrchestration.transfer_type.create(repository: repo).update(state: :running)

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :add_repositories,
        repositories: [repo],
      )

      refute_predicate result, :permitted?
      assert_equal :transfer_in_progress, result.reason
    end

    test "is not permitted if the number of repositories goes over the allowed limit" do
      GitHub.flipper[:repo_subset_limit_for_installations].enable(@repo_admin_installation.target)

      repo = create(:repository, :minimal, owner: @org)
      repo2 = create(:repository, :minimal, owner: @org)

      Integration::InstallationService.stub_const(:DEFAULT_MAX_REPOS, 1) do
        result = IntegrationInstallation::Permissions.check(
          installation: @repo_admin_installation,
          actor: @admin,
          action: :add_repositories,
          repositories: [repo, repo2],
        )

        refute_predicate result, :permitted?
        assert_equal :too_many_repositories_to_add, result.reason
      end
    end

    test "is not permitted if the actor has no verified email and app requires OAuth on install", skip_enterprise: true do
      assert @admin.adminable_by?(@admin)
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      @admin.require_email_verification!
      @admin.emails.verified.each(&:unverify!)

      @repo_admin_integration.update(application_callback_urls_attributes: [{ url: "https://example.com" }], request_oauth_on_install: true)
      @repo_admin_integration.reload

      repo = create(:repository, :minimal, owner: @org)
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :add_repositories,
        repositories: [repo],
      )

      refute_predicate result, :permitted?
      assert_equal :missing_verified_email, result.reason
    end

    test "is permitted if the actor has no verified email within Enterprise and app requires OAuth on install", enterprise_only: true do
      assert @admin.adminable_by?(@admin)
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      @admin.require_email_verification!
      @admin.emails.verified.each(&:unverify!)

      @repo_admin_integration.update(application_callback_urls_attributes: [{ url: "https://example.com" }], request_oauth_on_install: true)
      @repo_admin_integration.reload

      repo = create(:repository, :minimal, owner: @org)
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :add_repositories,
        repositories: [repo],
      )

      assert_predicate result, :permitted?
    end
  end

  context "ACTION :add_repositories_from_api" do
    test "permitted when the installation is installed on the target with admin:write permission on at least one repository" do
      org_repo = create(:private_repository, :minimal, owner: @org)

      installation = make_integration_installation(repository: org_repo, permissions: { "administration" => :write })
      new_repo = create(:private_repository, :minimal, owner: @org)

      result = IntegrationInstallation::Permissions.check(
        installation: installation,
        actor: installation,
        action: :add_repositories_from_api,
        repositories: [new_repo],
      )

      assert_predicate result, :permitted?
      assert_equal :self_install, result.reason
    end

    test "permitted when the actor is a Bot and all repositories are owned by the target" do
      repo_one = create(:repository, :minimal, owner: @org)
      repo_two = create(:repository, :minimal, owner: @org)
      repo_three = create(:repository, :minimal, owner: @org)

      integration = create(:integration, default_permissions: { "metadata" => :read })
      installation = make_integration_installation(target: @org, repositories: [repo_one])
      integration.bot.installation = installation

      result = IntegrationInstallation::Permissions.check(
        installation: installation, # Does not have repository admin permission
        actor: integration.bot,
        action: :add_repositories_from_api,
        repositories: [repo_two, repo_three],
      )

      assert_predicate result, :permitted?
      assert_equal :is_app_actor, result.reason
    end

    test "not permitted when the actor is a Bot but not all repositories are owned by the target" do
      repo_one = create(:repository, :minimal, owner: @org)
      repo_two = create(:repository, :minimal, owner: @org)
      rando_repo = create(:repository, :minimal, owner: create(:organization))

      integration = create(:integration, default_permissions: { "metadata" => :read })
      installation = make_integration_installation(target: @org, repositories: [repo_one])
      integration.bot.installation = installation

      result = IntegrationInstallation::Permissions.check(
        installation: installation, # Does not have repository admin permission
        actor: integration.bot,
        action: :add_repositories_from_api,
        repositories: [repo_two, rando_repo],
      )

      refute_predicate result, :permitted?
      assert_equal :not_owned_by_target, result.reason
    end

    test "it emits repositories size metric" do
      assert @org.adminable_by?(@admin)

      repo = create(:repository, :minimal, owner: @org)
      IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :add_repositories_from_api,
        repositories: [repo],
      )

      assert_dogstats_distribution 1, "integration_installation.permissions.repositories.size", tags: { action: :add_repositories_from_api }
    end
  end

  context "ACTION :remove_repositories" do
    test "requires repositories" do
      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @admin, action: :remove_repositories)

      refute_predicate result, :permitted?
      assert_equal result.reason, :no_repositories_submitted
    end

    test "is not permitted if any of the repositories do not belong to the target" do
      rando_repo = create(:repository, :minimal, owner: create(:user))

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor: @admin,
        action: :remove_repositories,
        repositories: [rando_repo],
      )

      refute_predicate result, :permitted?
      assert_equal result.reason, :not_owned_by_target
    end

    test "is not permitted when the list includes repositories not installed" do
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @noora,
        action: :remove_repositories,
        repositories: [@repo_with_admin2],
      )

      refute_predicate result, :permitted?
      assert_equal result.reason, :not_installed
    end

    test "is permitted when target can_admin?" do
      assert @org.adminable_by?(@admin)

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor: @admin,
        action: :remove_repositories,
        repositories: [@repo_with_admin],
      )

      assert_predicate result, :permitted?
      assert_equal result.reason, :is_admin
    end

    test "it emits repositories size metric" do
      assert @org.adminable_by?(@admin)

      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor: @admin,
        action: :remove_repositories,
        repositories: [@repo_with_admin],
      )

      assert_dogstats_distribution 1, "integration_installation.permissions.repositories.size", tags: { action: :remove_repositories }
    end

    test "is permitted when the app requires org permissions" do
      @repo_admin_installation.stubs(:permissions).returns({ Organization::Resources.subject_types.first => :write })

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @noora,
        action: :remove_repositories,
        repositories: [@repo_with_admin],
      )

      assert_predicate result, :permitted?
    end

    test "is permitted when target can admin all repos" do
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @noora,
        action: :remove_repositories,
        repositories: [@repo_with_admin],
      )

      assert_predicate result, :permitted?
    end

    test "is not permitted when target cannot admin all repos" do
      repo = create(:repository, :minimal, owner: @org)
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :remove_repositories,
        repositories: [repo],
      )

      refute_predicate result, :permitted?
    end

    test "is not permitted if the number of repositories goes over the allowed limit" do
      GitHub.flipper[:repo_subset_limit_for_installations].enable(@repo_admin_installation.target)

      repo  = create(:repository, :minimal, owner: @org)
      repo2 = create(:repository, :minimal, owner: @org)
      repo3 = create(:repository, :minimal, owner: @org)

      installation = make_integration_installation(repositories: [repo, repo2, repo3], permissions: { "metadata" => :read })

      Integration::InstallationService.stub_const(:DEFAULT_MAX_REPOS, 1) do
        result = IntegrationInstallation::Permissions.check(
          installation: installation,
          actor: installation.target.admins.first,
          action: :remove_repositories,
          repositories: [repo, repo2],
        )

        refute_predicate result, :permitted?
        assert_equal :too_many_repositories_to_remove, result.reason
      end
    end
  end

  context "ACTION :uninstall" do
    test "is permitted when actor can_admin" do
      assert @org.adminable_by?(@admin)

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @admin, action: :uninstall)

      assert_predicate result, :permitted?
    end

    test "is not permitted when the integration requires organization installation" do
      refute @org.adminable_by?(@noora)

      @installation.stubs(:permissions).returns({ Organization::Resources.subject_types.first => :write })

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @noora, action: :uninstall)

      refute_predicate result, :permitted?
      assert_equal result.reason, :requires_org_permissions
    end

    test "is permitted if the number of repositories goes over the allowed limit" do
      repo  = create(:repository, :minimal, owner: @org)
      repo2 = create(:repository, :minimal, owner: @org)

      installation = make_integration_installation(repositories: [@repo_with_admin, @repo_with_admin2], permissions: { "metadata" => :read })
      GitHub.flipper[:repo_subset_limit_for_installations].enable(installation.target)

      Integration::InstallationService.stub_const(:DEFAULT_MAX_REPOS, 1) do
        result = IntegrationInstallation::Permissions.check(
          installation: installation,
          actor: @noora,
          action: :uninstall,
        )

        assert_predicate result, :permitted?
      end
    end
  end

  context "ACTION :auto_upgrade" do
    test "is not permitted if the version is not present" do
      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: nil, action: :auto_upgrade)

      refute_predicate result, :permitted?
      assert_equal :missing_version, result.reason
    end

    test "is not permitted if the version integration is not the installation's integration" do
      version = create(:integration_version, default_permissions: { "metadata" => :read })
      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: nil, action: :auto_upgrade, version: version)

      refute_predicate result, :permitted?
      assert_equal :incorrect_version, result.reason
    end

    test "is permitted if the new version default_permissions are empty?" do
      version = create(:integration_version, integration: @integration)
      assert_empty version.default_permissions

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: nil, action: :auto_upgrade, version: version)
      assert_predicate result, :permitted?
    end

    test "is permitted if the integration is configured correctly as an internal App" do
      integration  = create_privileged_app_with_capabilities(capabilities: { auto_upgrade_permissions: true })

      installation = make_integration_installation(integration: integration, target: @org)
      version      = create(:integration_version, integration: integration, default_permissions: { "contents" => :write })

      result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
      assert_predicate result, :permitted?
    end

    test "is permitted if the integration is used for GitHub Connect" do
      enterprise_installation = create :enterprise_installation
      integration, secret = enterprise_installation.create_github_app

      installation = make_integration_installation(integration: integration, target: @org)
      version      = create(:integration_version, integration: integration, default_permissions: { "contents" => :write })

      result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
      assert_predicate result, :permitted?
    end
  end

  context "ACTION :suspend" do
    test "can suspend if the target is the actor" do
      installation = make_integration_installation(target: @admin)

      result = IntegrationInstallation::Permissions.check(installation: installation, actor: @admin, action: :suspend)
      assert_predicate result, :permitted?
    end

    test "can suspend if the target is an admin" do
      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @admin, action: :suspend)
      assert_predicate result, :permitted?
    end

    test "cannnot suspend if the installation is already suspended" do
      @installation.suspend!(user: @admin); @installation.reload

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @admin, action: :suspend)

      refute_predicate result, :permitted?
      assert_equal :already_suspended, result.reason
    end

    test "staff can override a user suspension", skip_enterprise: true do
      @installation.suspend!(user: @admin); @installation.reload

      setup_staff_user

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: User.staff_user, action: :suspend)
      assert_predicate result, :permitted?
    end
  end

  context "ACTION :unsuspend" do
    test "can unsuspend if the target is the actor" do
      installation = make_integration_installation(target: @admin)

      result = IntegrationInstallation::Permissions.check(installation: installation, actor: @admin, action: :unsuspend)
      assert_predicate result, :permitted?
    end

    test "can unsuspend if the target is an admin" do
      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @admin, action: :unsuspend)
      assert_predicate result, :permitted?
    end

    test "cannot unsuspend a staff suspension", skip_enterprise: true do
      setup_staff_user
      @installation.suspend!(user: User.staff_user, staff_actor: true)

      result = IntegrationInstallation::Permissions.check(installation: @installation, actor: @admin, action: :unsuspend)

      refute_predicate result, :permitted?
      assert_equal :suspended_by_staff, result.reason
    end
  end

  context "ACTION :can_configure_access_to" do
    test "requires the installation have repo permissions" do
      installation = make_integration_installation(target: @org)

      result = IntegrationInstallation::Permissions.check(
        installation: installation,
        actor: @admin,
        action: :configure_access_to_repository,
        repository: @repo_with_admin
      )

      refute_predicate result, :permitted?
      assert_equal :no_access_to_repositories, result.reason
    end

    test "repository must belong to the target" do
      repo = create(:repository, :minimal, owner: @admin)

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :configure_access_to_repository,
        repository: repo
      )

      refute_predicate result, :permitted?
      assert_equal :not_owned_by_target, result.reason
    end

    test "repository must not be part of an advisory workspace" do
      repository = create(:repository, :minimal, owner: @org)
      author     = @admin

      GitHub.context.push(actor_id: author.id)

      advisory1 = create(:repository_advisory, repository: repository, author: author)
      workspace_repo1 = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory1, author).tap(&:save!)

      result =
        IntegrationInstallation::Permissions.check(
          installation: @repo_admin_installation,
          actor: @app_owner,
          action: :configure_access_to_repository,
          repository: workspace_repo1
        )

      refute_predicate result, :permitted?
      assert_equal :advisory_workspace_repo_included, result.reason
    end

    test "is permitted if the actor admins the target" do
      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :configure_access_to_repository,
        repository: @repo_with_admin
      )

      assert_predicate result, :permitted?
      assert_equal :is_admin, result.reason
    end

    test "does not blow up if the installation permissions cache is nil" do
      @repo_admin_installation.clear_cached_permissions

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @admin,
        action: :configure_access_to_repository,
        repository: @repo_with_admin
      )

      assert_predicate result, :permitted?
      assert_equal :is_admin, result.reason
    end

    test "is not permitted for non admins unless that target is an organization" do
      repo = create(:repository, :minimal, owner: @admin)
      repo.add_member(@noora, action: :admin)

      installation = make_integration_installation(repository: repo, permissions: { "metadata" => :read })

      result = IntegrationInstallation::Permissions.check(
        installation: installation,
        actor: @noora,
        action: :configure_access_to_repository,
        repository: repo
      )

      refute_predicate result, :permitted?
      assert_equal :target_not_organization, result.reason
    end

    test "is not permitted by non org admins if installed on all repositories" do
      result = IntegrationInstallation::Permissions.check(
        installation: @installation,
        actor: @noora,
        action: :configure_access_to_repository,
        repository: @repo_with_admin
      )

      refute_predicate result, :permitted?
      assert_equal :installed_on_all_repositories, result.reason
    end

    test "org members are permitted if they can see the repository" do
      member = create(:user)
      @org.add_member(member)

      assert @repo_with_admin.readable_by?(member)
      assert_nil Authorization.service.direct_ability_between(actor: member, subject: @repo_with_admin)

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: member,
        action: :configure_access_to_repository,
        repository: @repo_with_admin
      )

      assert_predicate result, :permitted?
      assert_equal :organization_member, result.reason
    end

    test "org members are not permitted if they cannot see the repository" do
      @org.update_default_repository_permission(:none, actor: @admin)

      member = create(:user)
      @org.add_member(member)

      private_repo = create(:private_repository, :minimal, owner: @org)
      refute private_repo.readable_by?(member)

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: member,
        action: :configure_access_to_repository,
        repository: private_repo
      )

      refute_predicate result, :permitted?
      assert_equal :repository_not_accessible, result.reason
    end

    test "outside collaborators are forbidden if the target does not allow access" do
      @org.disallow_third_party_access_requests_from_outside_collaborators(actor: @admin)
      assert_predicate @org, :denies_third_party_access_requests_from_outside_collaborators?

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @noora,
        action: :configure_access_to_repository,
        repository: @repo_with_admin
      )

      refute_predicate result, :permitted?
      assert_equal :installation_requests_disabled, result.reason
    end

    test "outside collaborators are permitted if they have direct access to the repository" do
      assert_predicate @org, :allows_third_party_access_requests_from_outside_collaborators?

      refute_nil Authorization.service.direct_ability_between(actor: @noora, subject: @repo_with_admin)

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: @noora,
        action: :configure_access_to_repository,
        repository: @repo_with_admin
      )

      assert_predicate result, :permitted?
      assert_equal :outside_collaborator, result.reason
    end

    test "unaffiliated users are not permitted if they do not have direct access" do
      rando = create(:user)

      assert_predicate @org, :allows_third_party_access_requests_from_outside_collaborators?

      assert_nil Authorization.service.direct_ability_between(actor: rando, subject: @repo_with_admin)

      result = IntegrationInstallation::Permissions.check(
        installation: @repo_admin_installation,
        actor: rando,
        action: :configure_access_to_repository,
        repository: @repo_with_admin
      )

      refute_predicate result, :permitted?
      assert_equal :not_part_of_organization, result.reason
    end
  end

  #
  # NOTE: Target specific test cases are in test/models/integration_installation/permission_target_test.rb
  #
end
