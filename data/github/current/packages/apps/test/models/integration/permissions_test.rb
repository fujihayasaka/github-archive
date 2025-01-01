# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::PermissionsTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @admin = create(:user, login: "org-admin")
    @org   = create(:organization, admin: @admin)
    @rando = create(:user, login: "rando")

    @org_member = create(:user, login: "org-member")
    @org.add_member(@org_member)

    @app_owner   = create(:user, login: "app-owner")
    @integration = create(:integration, owner: @app_owner, default_permissions: { "metadata" => :read })

    @version = @integration.latest_version
  end

  def setup
    GitHub.flipper[:repo_subset_limit_for_installations].disable
  end

  def check(**kwargs)
    T.unsafe(Integration::Permissions).check(**kwargs)
  end

  test "requires an action" do
    assert_raises ArgumentError do
      T.unsafe(Integration::Permissions).check(integration: @integration, actor: @admin)
    end
  end

  test "requires a permitted action" do
    refute_includes Integration::Permissions::PERMITTED_ACTIONS, :foo
    result = check(integration: @integration, actor: @admin, action: :foo, target: @org, version: @version)

    refute_predicate result, :permitted?
    assert_equal :invalid_action, result.reason
  end

  context "ACTION :install" do
    test "not permitted if the app is not installable" do
      @integration.make_private
      refute @integration.reload.installable_on?(@org)

      result = check(integration: @integration, actor: @app_owner, action: :install, target: @org, version: @version)
      refute_predicate result, :permitted?
      assert_equal :not_installable_on, result.reason
    end

    test "not permitted if the app is suspended" do
      @integration.expects(:suspended?).twice.returns(true)
      refute @integration.installable_on?(@org), "integration should not be installable"

      result = check(integration: @integration, actor: @app_owner, action: :install, target: @org, version: @version)
      refute_predicate result, :permitted?
      assert_equal :suspended, result.reason
    end

    test "permitted if the app is private" do
      make_trusted_oauth_apps_owner
      create(:repository, :minimal, owner: @org)

      integration = create(:integration, owner: GitHub.trusted_oauth_apps_owner)
      integration.make_private
      assert integration.reload.installable_on?(@org)

      result = check(
        integration: integration, actor: @admin, action: :install,
        target: @org, version: integration.latest_version
      )

      assert_predicate result, :permitted?
    end

    test "permitted if the app is internal and used for GitHub Connect" do
      create(:repository, :minimal, owner: @org)

      enterprise_installation = create :enterprise_installation
      integration, secret = enterprise_installation.create_github_app
      assert integration.reload.installable_on?(@org)

      result = check(
        integration: integration, actor: @admin, action: :install,
        target: @org, version: integration.latest_version
      )

      assert_predicate result, :permitted?
    end

    if GitHub.spamminess_check_enabled?
      test "not permitted if the target is marked as spammy" do
        @org.update(spammy: true)

        assert @org.adminable_by?(@admin)
        result = check(integration: @integration, actor: @admin, action: :install, target: @org)
        refute_predicate result, :permitted?
        assert_equal :spammy_target, result.reason
      end

      test "not permitted if the actor installing the application is marked as spammy" do
        @admin.update(spammy: true)

        assert @org.adminable_by?(@admin)
        result = check(integration: @integration, actor: @admin, action: :install, target: @org)
        refute_predicate result, :permitted?
        assert_equal :spammy_actor, result.reason
      end
    end

    test "not permitted if the actor has no verified email and app requires OAuth on install", skip_enterprise: true do
      assert @admin.adminable_by?(@admin)
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      @admin.require_email_verification!

      @integration.update(application_callback_urls_attributes: [{ url: "http://example.com" }], request_oauth_on_install: true)
      @integration.reload

      result = check(integration: @integration, actor: @admin, action: :install, target: @admin)
      refute_predicate result, :permitted?
      assert_equal :missing_verified_email, result.reason
    end

    test "is permitted if the actor has no verified email within Enterprise and app requires OAuth on install", enterprise_only: true do
      assert @admin.adminable_by?(@admin)
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      @admin.require_email_verification!

      @integration.update(application_callback_urls_attributes: [{ url: "http://example.com" }], request_oauth_on_install: true)
      @integration.reload

      result = check(integration: @integration, actor: @admin, action: :install, target: @admin, version: @version)
      assert_predicate result, :permitted?
    end

    test "permitted if the actor can admin the User target" do
      assert @admin.adminable_by?(@admin)
      result = check(integration: @integration, actor: @admin, action: :install, target: @admin, version: @version)
      assert_predicate result, :permitted?
    end

    test "permitted if the actor can admin the Organization target" do
      assert @org.adminable_by?(@admin)
      result = check(integration: @integration, actor: @admin, action: :install, target: @org, version: @version)
      assert_predicate result, :permitted?
    end

    test "not permitted if the actor cannot admin the User target" do
      refute @admin.adminable_by?(@rando)

      result = check(integration: @integration, actor: @rando, action: :install, target: @admin, version: @version)
      refute_predicate result, :permitted?
      assert_equal :not_adminable, result.reason
    end

    test "not permitted if the app requires organization permissions and the actor can't admin the Organization target" do
      integration = create(:integration, default_permissions: { "members" => :read })

      refute @org.adminable_by?(@rando)

      result = check(
        integration: integration, actor: @rando, action: :install,
        target: @org, version: integration.latest_version
      )

      refute_predicate result, :permitted?
      assert_equal :requires_org_permissions, result.reason
    end

    test "not permitted if the app requires repo permissions that require an organization installation and the actor can't admin the Organization target" do
      integration = create(:integration, default_permissions: { "administration" => :read })

      refute @org.adminable_by?(@rando)

      result = check(integration: integration, actor: @rando, action: :install, target: @org, version: integration.latest_version)
      refute_predicate result, :permitted?
      assert_equal :requires_org_permissions, result.reason
    end

    test "non org admins aren't permitted to install permission-less apps" do
      member = create(:user)
      @org.add_member(member)

      integration = create(:integration)

      result = check(integration: integration, actor: member, action: :install, target: @org, version: integration.latest_version)

      refute_predicate result, :permitted?
      assert_equal :not_adminable, result.reason
    end

    test "not permitted if repository_selection :all is passed and the actor can't admin the Organization target" do
      refute @org.adminable_by?(@rando)

      result = check(integration: @integration, actor: @rando, action: :install, target: @org, repository_selection: Integration::Permissions::RepositorySelection::All, version: @integration.latest_version)
      refute_predicate result, :permitted?
      assert_equal :all_repositories, result.reason
    end

    test "not permitted if no repositories are supplied and the actor can't admin any org repos" do
      refute @org.adminable_by?(@rando)

      result = check(integration: @integration, actor: @rando, action: :install, target: @org, version: @version)
      refute_predicate result, :permitted?
      assert_equal :not_admin_on_any_repos, result.reason
    end

    test "not permitted if the repositories provided don't belong to the target" do
      repository = create(:repository, :minimal, owner: @rando)

      result = check(integration: @integration, actor: @org_member, action: :install, target: @org, version: @version, repository_selection: Integration::Permissions::RepositorySelection::Subset, repository_ids: [repository.id])
      refute_predicate result, :permitted?
      assert_equal :not_owned_by_target, result.reason
    end

    test "not permitted if the repositories aren't adminable by the actor" do
      repository = create(:repository, :minimal, owner: @org)
      refute repository.adminable_by?(@org_member)

      result = check(integration: @integration, actor: @org_member, action: :install, target: @org, version: @version, repository_selection: Integration::Permissions::RepositorySelection::Subset, repository_ids: [repository.id])
      refute_predicate result, :permitted?
      assert_equal :not_admin_on_subset, result.reason
    end

    test "permitted if the repositories are adminable by the actor" do
      repository = create(:repository, :minimal, owner: @org)
      repository.add_member(@org_member, action: :admin)

      assert repository.adminable_by?(@org_member)

      result = check(integration: @integration, actor: @org_member, action: :install, target: @org, version: @version, repository_selection: Integration::Permissions::RepositorySelection::Subset, repository_ids: [repository.id])
      assert_predicate result, :permitted?
    end

    test "it emits repository_ids size metrics" do
      repository = create(:repository, :minimal, owner: @org)
      repository.add_member(@org_member, action: :admin)

      assert repository.adminable_by?(@org_member)

      check(integration: @integration, actor: @org_member, action: :install, target: @org, version: @version, repository_selection: Integration::Permissions::RepositorySelection::Subset, repository_ids: [repository.id])
      assert_dogstats_distribution 1, "integration.permissions.repositories.size"
    end

    test "requires a version if organization permissions need to be checked" do
      repository = create(:repository, :minimal, owner: @org)
      repository.add_member(@org_member, action: :admin)

      assert repository.adminable_by?(@org_member)

      result = Integration::Permissions.check(integration: @integration, actor: @org_member, action: :install, target: @org)
      refute_predicate result, :permitted?
      assert_equal :missing_version, result.reason
    end

    test "requires a version that belongs to the integration" do
      version    = create(:integration).latest_version
      repository = create(:repository, :minimal, owner: @org)

      repository.add_member(@org_member, action: :admin)
      assert repository.adminable_by?(@org_member)

      result = check(integration: @integration, actor: @org_member, action: :install, target: @org, repository_ids: [repository.id], version: version)
      refute_predicate result, :permitted?
      assert_equal :invalid_version, result.reason
    end

    test "does not allow workspace advisory repository to be installed" do
      GitHub.flipper[:maintainer_love_advisory_workspaces_can_use_actions].disable
      repository = create(:repository, :minimal)
      author     = repository.owner
      advisory   = create(:repository_advisory, repository: repository, author: author)

      GitHub.context.push(actor_id: author.id)
      workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, author).tap(&:save!)

      result = check(
        integration: @integration, actor: author, action: :install, target: author,
        repository_selection: Integration::Permissions::RepositorySelection::Subset, repository_ids: [workspace_repo.id], version: @version
      )

      refute_predicate result, :permitted?
      assert_equal :advisory_workspace_repo_included, result.reason
    end

    test "not permitted if the number of repositories is over the limit" do
      GitHub.flipper[:repo_subset_limit_for_installations].enable(@org)

      repository = create(:repository, :minimal, owner: @org)
      repository.add_member(@org_member, action: :admin)

      repository2 = create(:repository, :minimal, owner: @org)
      repository2.add_member(@org_member, action: :admin)

      assert repository.adminable_by?(@org_member)

      Integration::InstallationService.stub_const(:DEFAULT_MAX_REPOS, 1) do
        result = check(integration: @integration, actor: @org_member, action: :install, target: @org, version: @version, repository_selection: Integration::Permissions::RepositorySelection::Subset, repository_ids: [repository.id, repository2.id])

        refute_predicate result, :permitted?
        assert_equal :too_many_repositories, result.reason
      end
    end

    test "not permitted if the target is transforming into an organization" do
      Organization.transform(@app_owner, @org_member)
      assert Organization.transforming?(@app_owner)

      result = check(
        integration: @integration,
        actor: @app_owner,
        action: :install,
        target: @app_owner,
        version: @version,
        repository_selection: Integration::Permissions::RepositorySelection::All,
      )

      refute_predicate result, :permitted?
      assert_equal :target_transforming_into_org, result.reason
    end

    test "not permitted if target is a business actor is a bot and feature flag is disabled" do
      GitHub.flipper[:enterprise_app_installation_management].disable
      org = create(:organization, admin: @admin)
      business = create(:business, owners: [@admin], organizations: [org])

      result = Integration::Permissions.check(integration: @integration, actor: @integration.bot, action: :install, target: business, version: @integration.latest_version)
      refute_predicate result, :permitted?
      assert_equal :missing_required_feature_flag, result.reason

      internal_integration = create_privileged_app_with_capabilities(
        capabilities: {
          installable_on_emus: true
        },
        permissions: { Business::Resources.subject_types.first => :read }
      )

      result = Integration::Permissions.check(integration: internal_integration, actor: internal_integration.bot, action: :install, target: business, version: internal_integration.latest_version)
      refute_predicate result, :permitted?
      assert_equal :missing_required_feature_flag, result.reason
    end

    test "not permitted if installing via app and org is not owned by an enterprise" do
      GitHub.flipper[:enterprise_app_installation_management].enable

      result = Integration::Permissions.check(integration: @integration, actor: @integration.bot, action: :install, target: @org, version: @integration.latest_version)
      refute_predicate result, :permitted?
      assert_equal :not_business_org, result.reason
    end

    test "permitted if installing via app and app requests oauth on install" do
      GitHub.flipper[:enterprise_app_installation_management].enable

      create(:application_callback_url, application: @integration, url: "http://example.com/callback")
      @integration.update(request_oauth_on_install: true)
      result = Integration::Permissions.check(integration: @integration, actor: @integration.bot, action: :install, target: @org, version: @integration.latest_version)
      refute_predicate result, :permitted?
      assert_equal :not_business_org, result.reason
    end

    test "not permitted if installing via app and app is not installed on enterprise" do
      GitHub.flipper[:enterprise_app_installation_management].enable
      org = create(:organization, admin: @admin)
      _business = create(:business, owners: [@admin], organizations: [org])

      result = Integration::Permissions.check(integration: @integration, actor: @integration.bot, action: :install, target: org.reload, version: @integration.latest_version)
      refute_predicate result, :permitted?
      assert_equal :not_installed_on_enterprise, result.reason
    end

    test "not permitted if installing via app and target does not own all repos" do
      GitHub.flipper[:enterprise_app_installation_management].enable
      org = create(:organization, admin: @admin)
      _business = create(:business, owners: [@admin], organizations: [org])

      result = Integration::Permissions.check(
        integration: @integration,
        actor: @integration.bot,
        action: :install,
        target: org,
        version: @integration.latest_version,
        repository_selection: Integration::Permissions::RepositorySelection::Subset,
        repository_ids: [create(:repository, owner: org).id, create(:repository).id]
      )
      refute_predicate result, :permitted?
      assert_equal :not_owned_by_target, result.reason
    end

    test "permitted if installing via app and repository_selection is all" do
      GitHub.flipper[:enterprise_app_installation_management].enable
      org = create(:organization, admin: @admin)
      _business = create(:business, owners: [@admin], organizations: [org])

      result = Integration::Permissions.check(
        integration: @integration,
        actor: @integration.bot,
        action: :install,
        target: org.reload,
        version: @integration.latest_version,
        repository_selection: Integration::Permissions::RepositorySelection::All
      )
      refute_predicate result, :permitted?
      assert_equal :not_installed_on_enterprise, result.reason
    end

    test "permitted if target is a business actor is a bot and feature flag is enabled" do
      GitHub.flipper[:enterprise_app_installation_management].enable
      org = create(:organization, admin: @admin)
      business = create(:business, owners: [@admin], organizations: [org])
      integration = create(:integration, default_permissions: { Business::Resources.subject_types.first => :read })

      result = Integration::Permissions.check(integration: integration, actor: integration.bot, action: :install, target: business, version: integration.latest_version)
      assert_predicate result, :permitted?

      internal_integration = create_privileged_app_with_capabilities(
        capabilities: {
          installable_on_emus: true
        },
        permissions: { Business::Resources.subject_types.first => :read }
      )

      result = Integration::Permissions.check(integration: internal_integration, actor: internal_integration.bot, action: :install, target: business, version: internal_integration.latest_version)
      assert_predicate result, :permitted?
    end
  end

  context "ACTION :request_installation" do
    test "not permitted if the target is not an Organization" do
      result = Integration::Permissions.check(integration: @integration, actor: @admin, action: :request_installation, target: @admin)

      refute_predicate result, :permitted?
      assert_equal :not_an_organization, result.reason
    end

    test "not permitted if the integration is not installable on the target" do
      other_organization = create(:organization, admin: @admin)

      private_integration = create(:integration, :private, owner: @admin)
      refute private_integration.installable_on?(other_organization)

      result = Integration::Permissions.check(
        integration: private_integration,
        actor:       @admin,
        action:      :request_installation,
        target:      other_organization,
      )

      refute_predicate result, :permitted?
      assert_equal :not_installable_on_target, result.reason
    end

    test "not permitted if the actor can admin the organization target" do
      result = Integration::Permissions.check(integration: @integration, actor: @admin, action: :request_installation, target: @org)

      refute_predicate result, :permitted?
      assert_equal :is_admin, result.reason
    end

    test "is permitted for org members" do
      org_member = create(:user)
      @org.add_member(org_member, action: :read)

      result = Integration::Permissions.check(integration: @integration, actor: org_member, action: :request_installation, target: @org)

      assert_predicate result, :permitted?
      assert_equal :organization_member, result.reason
    end

    test "is permitted for org repository admins (non-org owner repo admin)" do
      repo_admin = create(:user)
      org_repo = create(:repository, :minimal, owner: @org)
      org_repo.add_member(repo_admin, action: :admin)

      result = Integration::Permissions.check(integration: @integration, actor: repo_admin, action: :request_installation, target: @org)

      assert_predicate result, :permitted?
      assert_equal :outside_collaborator, result.reason
    end

    test "is permitted for non admin org repository outside collaborators" do
      org_repo = create(:repository, :minimal, owner: @org)
      collaborator = create(:user)
      org_repo.add_member(collaborator, action: :read)

      result = Integration::Permissions.check(integration: @integration, actor: collaborator, action: :request_installation, target: @org)

      assert_predicate result, :permitted?
      assert_equal :outside_collaborator, result.reason
    end

    test "is not permitted for non admin org repository outside collaborators if org disables requests" do
      org_repo = create(:repository, :minimal, owner: @org)
      collaborator = create(:user)
      org_repo.add_member(collaborator, action: :read)
      @org.disallow_third_party_access_requests_from_outside_collaborators(actor: collaborator)

      result = Integration::Permissions.check(integration: @integration, actor: collaborator, action: :request_installation, target: @org)

      refute_predicate result, :permitted?
      assert_equal :installation_requests_disabled, result.reason
    end

    test "is not permitted if the actor is not apart of the org in anyway" do
      result = Integration::Permissions.check(integration: @integration, actor: @rando, action: :request_installation, target: @org)

      refute_predicate result, :permitted?
      assert_equal :not_part_of_organization, result.reason
    end
  end
end

class Integration::EMUPermissionsTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration, default_permissions: { Business::Resources.subject_types.first => :read })
    @internal_integration = create_privileged_app_with_capabilities(
      capabilities: {
        installable_on_emus: true
      },
      permissions: { Business::Resources.subject_types.first => :read }
    )

    @emu = create :emu, :owner
    @business = @emu.enterprise_managed_business
    @org_with_business = create :organization, business: @business, admin: @emu
  end

  context "ACTION :install" do
    test "not permitted if target is EMU user and integration isn't internal" do
      result = Integration::Permissions.check(integration: @integration, actor: @emu, action: :install, target: @emu, version: @integration.latest_version)
      refute_predicate result, :permitted?
      assert_equal :not_installable_on, result.reason
    end

    test "permitted if target is EMU user and integration is internal" do
      result = Integration::Permissions.check(integration: @internal_integration, actor: @emu, action: :install, target: @emu, version: @internal_integration.latest_version)
      assert_predicate result, :permitted?
    end

    test "permitted if target is EMU org" do
      result = Integration::Permissions.check(integration: @integration, actor: @emu, action: :install, target: @org_with_business, version: @integration.latest_version)
      assert_predicate result, :permitted?

      result = Integration::Permissions.check(integration: @internal_integration, actor: @emu, action: :install, target: @org_with_business, version: @internal_integration.latest_version)
      assert_predicate result, :permitted?
    end

    test "permitted if target is EMU business" do
      result = Integration::Permissions.check(integration: @integration, actor: @emu, action: :install, target: @business, version: @integration.latest_version)
      assert_predicate result, :permitted?

      result = Integration::Permissions.check(integration: @internal_integration, actor: @emu, action: :install, target: @business, version: @internal_integration.latest_version)
      assert_predicate result, :permitted?
    end
  end
end unless GitHub.single_business_environment?
