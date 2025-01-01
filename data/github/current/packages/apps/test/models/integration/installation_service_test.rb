# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallationServiceTest < GitHub::TestCase
  fixtures do
    @integration = create :integration, default_permissions: { "metadata" => :read }
    @admin = create :user, login: "owner"
    @member = create :user, login: "member"
    @repo_admin = create :user, login: "repo-admin" # non-org owner repo admin

    @org = create :organization, login: "ACME", admin: @admin
    only = [RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
    perform_enqueued_jobs(only: only) { @org.update_default_repository_permission(:none, actor: @admin) }

    @org.add_member(@member)
    @org.add_member(@repo_admin)

    @adminable_repo = create :private_repository, :minimal, owner: @org
    @adminable_repo.add_member(@repo_admin, action: :admin)
    @readable_repo = create :repository, :minimal, owner: @org

    @readable_team = @org.teams.create name: "readables-team"
    @readable_team.add_member @member
    @readable_team.add_member @repo_admin
    @readable_team.add_repository @readable_repo, :read

    # @repo_admin can admin a repo, but is not an org owner
    @adminable_team = @org.teams.create name: "adminables-team"
    @adminable_team.add_member @repo_admin
    @adminable_team.add_repository @adminable_repo, :admin

    # explicitly unselected repositories
    @unselected_adminable_repo = create :private_repository, :minimal, owner: @org, name: "unselected-adminable-repo"
    @unselected_adminable_repo.add_member(@repo_admin, action: :admin)
    @unselected_readable_repo = create :private_repository, :minimal, owner: @org, name: "unselected-readable-repo"
    @readable_team.add_repository @unselected_readable_repo, :read
    @unselected_public_repo = create(:public_repository, :minimal, owner: @org, name: "unselected-public-repo")
  end

  setup do
    @admin_selected_service = Integration::InstallationService.new(
      integration: @integration,
      target: @org,
      actor: @admin,
      params: {
        install_target: "selected",
        repository_ids: [@adminable_repo.id, @readable_repo.id],
      },
      entry_point: :test_case,
    )

    @admin_all_service = Integration::InstallationService.new(
      integration: @integration,
      target: @org,
      actor: @admin,
      params: { install_target: "all" },
      entry_point: :test_case,
    )

    @member_selected_service = Integration::InstallationService.new(
      integration: @integration,
      target: @org,
      actor: @member,
      params: {
        install_target: "selected",
        # @member does not have access to @adminable_repo
        repository_ids: [@adminable_repo.id, @readable_repo.id],
      },
      entry_point: :test_case,
    )

    @member_all_service = Integration::InstallationService.new(
      integration: @integration,
      target: @org,
      actor: @member,
      params: { install_target: "all" },
      entry_point: :test_case,
    )

    @repo_admin_selected_service = Integration::InstallationService.new(
      integration: @integration,
      target: @org,
      actor: @repo_admin,
      params: {
        install_target: "selected",
        repository_ids: [@adminable_repo.id, @readable_repo.id],
      },
      entry_point: :test_case,
    )

    @repo_admin_all_service = Integration::InstallationService.new(
      integration: @integration,
      target: @org,
      actor: @repo_admin,
      params: { install_target: "all" },
      entry_point: :test_case,
    )
  end

  context "#installable_repositories" do
    test "is empty when install target is ALL" do
      assert_same_elements [], @admin_all_service.installable_repositories, "admin installing on ALL repos should be empty"
      assert_same_elements [], @member_all_service.installable_repositories, "member installing on ALL repos should be empty"
    end

    test "includes selected repositories when install target is SELECTED" do
      assert_same_elements [@adminable_repo, @readable_repo], @admin_selected_service.installable_repositories,
        "admin installing on SELECTED repos should match"
      assert_same_elements [], @member_selected_service.installable_repositories,
        "member installing on SELECTED repos should be empty (no admin permissions)"
    end

    test "excludes unselected repositories" do
      [
        @unselected_adminable_repo,
        @unselected_readable_repo,
        @unselected_public_repo,
      ].each do |unselected_repo|
        refute_includes @admin_selected_service.installable_repositories, unselected_repo,
          "admin installing on SELECTED repos should exclude unselected repo #{unselected_repo}"
      end

      [
        @unselected_adminable_repo,
        @unselected_readable_repo,
        @unselected_public_repo,
      ].each do |unselected_repo|
        refute_includes @member_selected_service.installable_repositories, unselected_repo,
          "member installing on SELECTED repos should exclude unselected repo #{unselected_repo}"
      end
    end

    test "includes adminable repositories for repo admin" do
      assert_same_elements [@adminable_repo], @repo_admin_selected_service.installable_repositories,
        "repo admin installing on SELECTED repos should include adminable repo #{@adminable_repo} when feature flag is enabled"
    end
  end

  context "#requestable_repositories" do
    test "is empty when install target is ALL" do
      assert_same_elements [], @admin_all_service.requestable_repositories, "admin requesting ALL repos should be empty"
      assert_same_elements [], @member_all_service.requestable_repositories, "member requesting ALL repos should be empty"
    end

    test "includes selected repositories when install target is SELECTED" do
      assert_same_elements [], @admin_selected_service.requestable_repositories,
        "admin requesting SELECTED repos should exclude installable repos"
      assert_same_elements [@readable_repo], @member_selected_service.requestable_repositories,
        "member requesting SELECTED repos should include readable repos"
    end

    test "excludes unselected repositories" do
      [
        @unselected_adminable_repo,
        @unselected_readable_repo,
        @unselected_public_repo,
      ].each do |unselected_repo|
        refute_includes @admin_selected_service.requestable_repositories, unselected_repo,
          "admin requesting SELECTED repos should exclude unselected repo #{unselected_repo}"
      end

      [
        @unselected_adminable_repo,
        @unselected_readable_repo,
        @unselected_public_repo,
      ].each do |unselected_repo|
        refute_includes @member_selected_service.requestable_repositories, unselected_repo,
          "member requesting SELECTED repos should exclude unselected repo #{unselected_repo}"
      end
    end

    test "excludes installable repositories" do
      refute_includes @admin_selected_service.requestable_repositories, @adminable_repo,
        "admin requesting SELECTED repos should exclude installable repo #{@adminable_repo}"

      refute_includes @repo_admin_selected_service.requestable_repositories, @adminable_repo,
        "repo admin requesting SELECTED repos should exclude installable repo #{@adminable_repo}"
    end

    test "includes adminable repositories when the requested permissions include repos administration" do
      integration = create :integration, default_permissions: { "metadata" => :read, "administration" => :write }
      admin_selected_service = Integration::InstallationService.new(
        integration: integration,
        target: @org,
        actor: @repo_admin,
        params: {
          install_target: "selected",
          repository_ids: [@adminable_repo.id],
        },
        entry_point: :test_case,
      )

      assert_includes admin_selected_service.requestable_repositories, @adminable_repo
    end
  end
end

class IntegrationInstallationServiceInstallingAnIntegrationTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @integration = create :integration
    @admin = create :user, login: "owner"
    @org   = create :organization, login: "ACME", admin: @admin
    @repo  = create :private_repository, :minimal, owner: @org
    @public_repo = create(:public_repository, :minimal, owner: @org)
  end

  context ".perform" do
    test "returns an installation for a valid installation" do
      params = {
        install_target: "selected",
        repository_ids: [@repo.id],
      }

      result = Integration::InstallationService.perform(
        integration: @integration,
        target: @org,
        actor: @admin,
        params: params,
        entry_point: :test_case,
      )
      assert_predicate result, :success?, result.error
      assert installation_result = result.installation_result, "installation result expected"
    end

    test "returns a failure when the app is requesting oauth and the actor must verify their email" do
      @integration.update(request_oauth_on_install: true, application_callback_urls_attributes: [{ url: "http://example.com/callback" }])
      assert_predicate @integration, :can_request_oauth_on_install?

      user = create(:user)
      user.expects(:must_verify_email?).returns(true)

      result = Integration::InstallationService.perform(
        integration: @integration,
        target: user,
        actor: user,
        params: { install_target: "all", repository_ids: [] },
        entry_point: :test_case,
      )

      assert_predicate result, :failed?
      assert_equal "You must have a verified email address in order to install this application", result.error
    end

    test "it's allowed when the app is not requesting oauth even if the actor must verify email" do
      user = create(:user)
      user.stubs(:must_verify_email?).returns(true)

      result = Integration::InstallationService.perform(
        integration: @integration,
        target: user,
        actor: user,
        params: { install_target: "all", repository_ids: [] },
        entry_point: :test_case,
      )

      assert_predicate result, :success?, result.error
    end

    test "returns a failure if a repository isn't owned by the owner given" do
      other_org = create :organization, admin: @admin
      other_org_repo = create :repository, :minimal, owner: other_org

      result = Integration::InstallationService.perform(
        integration: @integration,
        target: @org,
        actor: @admin,
        params: {
          install_target: "selected",
          repository_ids: [other_org_repo.id],
        },
        entry_point: :test_case,
      )

      assert_predicate result, :failed?
      assert_equal "Repositories must be owned by ACME", result.error
    end

    test "creates an IntegrationInstallation with the expected values set" do
      @integration.versions.create(
        default_permissions: { "contents" => :read, "statuses" => :write },
        default_events: %w(status),
      )

      params = {
        install_target: "selected",
        repository_ids: [@repo.id, @public_repo.id],
      }

      result = Integration::InstallationService.perform(
        integration: @integration,
        target: @org,
        actor: @admin,
        params: params,
        entry_point: :test_case,
      )

      assert_predicate result, :success?, result.error
      assert installation_result = result.installation_result
      assert_able installation_result.installation, :read, @repo.resources.contents
      assert_able installation_result.installation, :write, @repo.resources.statuses
      assert_able installation_result.installation, :read, @public_repo.resources.contents
      assert_able installation_result.installation, :write, @public_repo.resources.statuses
      assert_same_elements ["status"], installation_result.installation.events
    end

    test "edit an installation if installation is given" do
      integration  = create :integration, default_permissions: { "metadata" => :read }
      installation = integration.install_on(
        @org,
        installer: @admin,
        repositories: [@repo, @public_repo],
        entry_point: :test_case,
      ).installation

      params = {
        install_target: "selected",
        repository_ids: [@repo.id],
      }

      result = Integration::InstallationService.perform(
        integration: integration,
        installation: installation,
        target: @org,
        actor: @admin,
        params: params,
        entry_point: :test_case,
      )
      assert_predicate result, :success?, result.error
      assert installation_result = result.installation_result, "installation result expected"
      assert_equal [@repo], installation_result.installation.repositories, "should only contain one repo"
      assert_equal installation, installation_result.installation
    end

    test "max installable limit does not take into account currently installed repositories" do
      integration = create :integration, default_permissions: { "metadata" => :read }
      max_installable = 2

      installation = make_integration_installation(integration: integration, target: @org, repositories: [@repo])

      params = {
        install_target: "selected",
        repository_ids: [@repo.id, @public_repo.id],
      }

      result = Integration::InstallationService.perform(
        integration: integration,
        installation: installation,
        target: @org,
        actor: @admin,
        params: params,
        max_installable: max_installable,
        entry_point: :test_case,
      )
      assert_predicate result, :success?, result.error
      assert_predicate result.installation_result, :present?, "installation result expected"
      assert_equal max_installable, result.installation_result.installation.repositories.count, "should allow edits above the max installable limit"
    end

    test "instruments creation of the installation" do
      events = subscribe "integration_installation.create"

      params = {
        install_target: "selected",
        repository_ids: [@repo.id],
      }

      result = Integration::InstallationService.perform(
        integration: @integration,
        target: @org,
        actor: @admin,
        params: params,
        entry_point: :test_case,
      )
      assert_predicate result, :success?, result.error
      assert installation_result = result.installation_result, "installation result expected"

      expected_payload = {}.tap do |payload|
        payload[:installation_id]      = installation_result.installation.id
        payload[:installer_id]         = @admin.id
        payload[:requester_id]         = nil
        payload[:integration]          = @integration.name
        payload[:app]                  = @integration.name
        payload[:integration_id]       = @integration.id
        payload[:app_id]               = @integration.id
        payload[:name]                 = @integration.name
        payload[:slug]                 = @integration.slug
        payload[:org]                  = @org.to_s
        payload[:org_id]               = @org.id
        payload[:repository_selection] = "selected"
        payload[:repository_ids]       = [@repo.id] if GitHub.flipper[:instrument_installation_creation_with_repo_ids].enabled?
      end

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments updating the installation" do
      events = subscribe "integration_installation.repositories_added"

      integration  = create :integration, default_permissions: { "metadata" => :read }
      installation = integration.install_on(
        @org,
        installer: @admin,
        repositories: [@public_repo],
        entry_point: :test_case,
      ).installation

      params = {
        install_target: "selected",
        repository_ids: [@repo.id],
      }

      result = Integration::InstallationService.perform(
        integration: integration,
        installation: installation,
        target: @org,
        actor: @admin,
        params: params,
        entry_point: :test_case,
      )

      assert_predicate result, :success?, result.error
      assert installation_result = result.installation_result, "installation result expected"

      expected_payload = {}.tap do |payload|
        payload[:installation_id]            = installation_result.installation.id
        payload[:integration]                = integration.name
        payload[:app]                        = integration.name
        payload[:integration_id]             = integration.id
        payload[:app_id]                     = integration.id
        payload[:name]                       = integration.name
        payload[:slug]                       = integration.slug
        payload[:org]                        = @org.to_s
        payload[:org_id]                     = @org.id
        payload[:repository_selection]       = "selected"
        payload[:repositories_added]         = [@repo.id]
        payload[:repositories_added_names]   = [@repo.full_name]
        payload[:actor]                      = "owner"
        payload[:actor_id]                   = @admin.id
        payload[:requester_id]               = nil
      end

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end

    test "approves pending installation request" do
      events = subscribe "integration_installation_request.close"

      pending_request = create(
        :integration_installation_request,
        integration: @integration,
        target: @org,
        repositories: [@repo],
      )

      params = {
        install_target: "selected",
        repository_ids: [@repo.id, @public_repo.id],
      }

      result = Integration::InstallationService.perform(
        integration: @integration,
        target: @org,
        actor: @admin,
        params: params,
        pending_request: pending_request,
        entry_point: :test_case,
      )

      assert_predicate result, :success?, result.error
      assert installation_result = result.installation_result
      assert event = events.pop, "a integration_installation_request.reject event was expected"
      assert_equal :approved, event.payload[:reason]
    end

    # Prevent race condition where an app could request installation with one
    # set of permissions and update them when the user accepts the old
    # version:
    #
    # https://github.com/github/github/issues/90286
    test "creates an installation on a specific integration version" do
      expected_version = @integration.versions.create(
        default_permissions: { "contents" => :read },
      )

      latest_version = @integration.versions.create(
        default_permissions: { "contents" => :read, "statuses" => :write },
        default_events: %w(status),
      )

      params = {
        install_target: "selected",
        repository_ids: [@repo.id, @public_repo.id],
        version_id: expected_version.id,
      }

      result = Integration::InstallationService.perform(
        integration: @integration,
        target: @org,
        actor: @admin,
        params: params,
        entry_point: :test_case,
      )

      assert_predicate result, :success?, result.error
      assert installation_result = result.installation_result
      assert_able installation_result.installation, :read, @repo.resources.contents
      refute_able installation_result.installation, :write, @repo.resources.statuses
      assert_able installation_result.installation, :read, @public_repo.resources.contents
      refute_able installation_result.installation, :write, @public_repo.resources.statuses
      assert_predicate installation_result.installation.events, :none?
    end
  end
end

class IntegrationInstallationServiceRequestingInstallationOfAnIntegrationTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @admin = create :user, login: "owner"
    @member = create :user, login: "member"
    @org = create :organization, login: "ACME", admin: @admin
    only = [RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
    perform_enqueued_jobs(only: only) { @org.update_default_repository_permission(:none, actor: @admin) }
    @org.add_member(@member)
    @private_repo = create :private_repository, :minimal, owner: @org
    @public_repo = create(:public_repository, :minimal, owner: @org)

    @integration = create :integration, default_permissions: { "metadata" => :read }
    @integration_for_no_repos = create :integration, public: true, owner: @org, default_permissions: {}
  end

  setup do
    @service = Integration::InstallationService.new(
      integration: @integration,
      target: @org,
      actor: @member,
      params: {
        install_target: "selected",
        repository_ids: [@private_repo.id, @public_repo.id],
      },
      entry_point: :test_case,
    )

    @all_service = Integration::InstallationService.new(
      integration: @integration,
      target: @org,
      actor: @member,
      params: { install_target: "all" },
      entry_point: :test_case,
    )

    @none_service = Integration::InstallationService.new(
      integration: @integration_for_no_repos,
      target: @org,
      actor: @member,
      params: { install_target: "none" },
      entry_point: :test_case,
    )
  end

  context ".perform on selected repositories" do
    test "requests installation on requestable repository" do
      assert @public_repo.readable_by?(@member), "#{@member} should be able to read #{@public_repo}"

      result = T.let(nil, T.nilable(Integration::InstallationService::Result))
      assert_difference "IntegrationInstallationRequest.count" do
        result = @service.perform
        assert_predicate result, :success?, result.error
      end

      request = T.must(result).request_result

      assert_includes request.repositories, @public_repo
    end

    test "does not request installation on non-requestable repository" do
      refute @private_repo.readable_by?(@member), "#{@member} should not be able to read #{@private_repo}"

      result = T.let(nil, T.nilable(Integration::InstallationService::Result))
      assert_difference "IntegrationInstallationRequest.count" do
        result = @service.perform
        assert_predicate result, :success?, result.error
      end

      request = T.must(result).request_result

      refute_includes request.repositories, @private_repo
    end
  end

  context ".perform on all repositories" do
    test "requests installation on all repositories" do
      result = T.let(nil, T.nilable(Integration::InstallationService::Result))
      assert_difference "IntegrationInstallationRequest.count" do
        result = @all_service.perform
        assert_predicate result, :success?, result.error
      end

      request = T.must(result).request_result

      assert_empty request.repositories
      assert_predicate request, :request_all_repositories?
      refute_predicate request, :request_some_repositories?
      refute_predicate request, :request_no_repositories?
    end
  end

  context ".perform on no repositories" do
    test "requests installation on no repositories" do
      refute @integration_for_no_repos.repository_installation_required?(@org)

      result = T.let(nil, T.nilable(Integration::InstallationService::Result))
      assert_difference "IntegrationInstallationRequest.count" do
        result = @none_service.perform
        assert_predicate result, :success?, result.error
      end

      request = T.must(result).request_result

      assert_empty request.repositories
      refute_predicate request, :request_all_repositories?
      refute_predicate request, :request_some_repositories?
      assert_predicate request, :request_no_repositories?
    end
  end
end

class IntegrationInstallationServiceInstallingAndRequestingInstallationOfAnIntegrationTest < GitHub::TestCase
  fixtures do
    @integration = create :integration, default_permissions: { "metadata" => :read }
    @admin = create :user, login: "owner"
    @repo_admin = create :user, login: "repo-admin" # non-org owner repo admin
    @outside_collaborator = create :user, login: "outside-collaborator"
    @org = create :organization, login: "ACME", admin: @admin
    @org.add_member(@repo_admin)
    @adminable_repo = create :private_repository, :minimal, owner: @org, name: "Adminable"
    @adminable_repo.add_member(@repo_admin, action: :admin)
    @writable_repo = create :private_repository, :minimal, owner: @org
    @writable_repo.add_member(@outside_collaborator, action: :write)
    @public_repo = create(:public_repository, :minimal, owner: @org)
    @readable_repo = create :private_repository, :minimal, owner: @org, name: "Readable"
  end

  setup do
    @service = Integration::InstallationService.new(
      integration: @integration,
      target: @org,
      actor: @repo_admin,
      params: {
        install_target: "selected",
        repository_ids: [@adminable_repo.id, @readable_repo.id],
      },
      entry_point: :test_case,
    )
  end

  context ".perform on selected repositories" do
    test "installs on adminable repositories" do
      result = T.let(nil, T.nilable(Integration::InstallationService::Result))
      assert_difference "IntegrationInstallation.count" do
        result = @service.perform
        assert_predicate result, :success?, result.error
      end

      assert installation_result = T.must(result).installation_result, result
      assert installation = installation_result.installation, installation_result
      assert_includes installation.repositories, @adminable_repo
      refute_includes installation.repositories, @readable_repo
    end

    test "requests non-adminable repositories" do
      result = T.let(nil, T.nilable(Integration::InstallationService::Result))
      assert_difference "IntegrationInstallationRequest.count" do
        result = @service.perform
        assert_predicate result, :success?, result.error
      end

      result = T.must(result)

      assert request = result.request_result, result
      assert_includes request.repositories, @readable_repo
      refute_includes request.repositories, @adminable_repo
    end

    test "outside-collaborator cannot request public repositories" do
      assert_no_difference "IntegrationInstallationRequest.count" do
        result = Integration::InstallationService.new(
          integration: @integration,
          target: @org,
          actor: @outside_collaborator,
          params: {
            install_target: "selected",
            repository_ids: [@public_repo.id],
          },
          entry_point: :test_case,
        ).perform
        refute_predicate result, :success?, "public repository should not be requestable by outside collaborator"
      end
    end

    test "outside-collaborator can request accessible repository" do
      assert_difference "IntegrationInstallationRequest.count" do
        result = Integration::InstallationService.new(
          integration: @integration,
          target: @org,
          actor: @outside_collaborator,
          params: {
            install_target: "selected",
            repository_ids: [@writable_repo.id],
          },
          entry_point: :test_case,
        ).perform
        assert_predicate result, :success?, result.error
      end
    end

    test "repo-admin requests instead of installing when integration has non-repo permissions" do
      integration = create(:integration, default_permissions: { "members" => :read })
      assert_difference "IntegrationInstallationRequest.count" do
        result = Integration::InstallationService.new(
          integration: integration,
          target: @org,
          actor: @repo_admin,
          params: {
            install_target: "selected",
            repository_ids: [@adminable_repo.id],
          },
          entry_point: :test_case,
        ).perform
        assert_predicate result, :success?, result.error
        assert_includes result.request_result.repositories, @adminable_repo
      end
    end

    test "repo-admin editing existing installation leaves installed, requestable repo unchanged" do
      integration  = create :integration, default_permissions: { "metadata" => :read }
      installation = integration.install_on(
        @org,
        installer: @admin,
        repositories: [@adminable_repo, @readable_repo],
        entry_point: :test_case,
      ).installation

      result = T.let(nil, T.nilable(Integration::InstallationService::Result))
      assert_no_difference "IntegrationInstallationRequest.count" do
        result = Integration::InstallationService.new(
          integration: integration,
          installation: installation,
          editor: :repository_editor,
          target: @org,
          actor: @repo_admin,
          params: {
            install_target: "selected",
            repository_ids: [@adminable_repo, @readable_repo].map(&:id),
          },
          entry_point: :test_case,
        ).perform
        assert_predicate result, :success?, result.error
      end

      result = T.must(result)

      installation.reload
      assert_includes installation.repositories, @adminable_repo
      assert_includes installation.repositories, @readable_repo

      assert_nil result.request_result
      assert_predicate result.installation_result, :success?, result.error
    end

    test "returns an owner-required-error when a repo admin attemps to update an installation with admin-permissions" do
      # REF: https://github.com/github/ecosystem-apps/issues/535
      integration = create :integration, default_permissions: { "metadata" => :read, "administration" => :read }
      installation = integration.install_on(
        @org,
        installer: @admin,
        repositories: [@adminable_repo],
        entry_point: :test_case,
      ).installation
      assert_predicate installation, :persisted?

      result = Integration::InstallationService.perform(
        integration: integration,
        installation: installation,
        target: @org,
        actor: @repo_admin,
        params: { install_target: "selected" },
        editor: :repository_editor,
        entry_point: :test_case,
      )

      refute_predicate result, :success?
      expected_error = "This action must be performed by an organization owner"
      assert_equal expected_error, result.error
    end
  end

  context ".perform on all repositories" do
    test "requests all repositories and installs on adminable repos" do
      service = Integration::InstallationService.new(
        integration: @integration,
        target: @org,
        actor: @repo_admin,
        params: { install_target: "all" },
        entry_point: :test_case,
      )

      result = T.let(nil, T.nilable(Integration::InstallationService::Result))
      assert_difference "IntegrationInstallation.count" do
        assert_difference "IntegrationInstallationRequest.count" do
          result = service.perform
          assert_predicate result, :success?, result.error
        end
      end

      result = T.must(result)

      assert installation_result = result.installation_result, result
      assert installation = installation_result.installation, installation_result
      assert_includes installation.repositories, @adminable_repo
      refute_includes installation.repositories, @readable_repo

      assert request = result.request_result, result
      assert_predicate request, :request_all_repositories?
    end
  end

  test "rolls back the full transaction if either fails" do
    mocked_request = IntegrationInstallationRequest.new
    mocked_request.errors.add :base, "forced failure"

    expect = IntegrationInstallationRequest.expects(:create)
    expect.with do |given|
      given[:requester] == @repo_admin &&
      given[:target] == @org &&
      given[:integration] == @integration &&
      given[:repositories].include?(@readable_repo)
    end
    expect.returns(mocked_request)

    assert_no_difference "IntegrationInstallation.count" do
      assert_no_difference "IntegrationInstallationRequest.count" do
        result = @service.perform
        assert_predicate result, :failed?
      end
    end
  end
end
