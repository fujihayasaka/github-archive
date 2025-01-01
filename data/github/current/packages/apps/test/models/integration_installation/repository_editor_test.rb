# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class IntegrationInstallation::RepositoryEditorTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    make_trusted_oauth_apps_owner

    @admin      = create(:user, login: "that-org-admin")
    @org_member = create(:user, login: "that-org-member")
    @repo_admin = create(:user, login: "that-org-repo-admin")

    @org = create(:organization, admin: @admin)
    @org.add_member(@org_member, action: :write)
    @org.add_member(@repo_admin)

    @org_repo1 = create(:repository, :minimal, owner: @org)
    @org_repo2 = create(:repository, :minimal, owner: @org)

    @team = create(:team, organization: @org)
    @team.add_member(@repo_admin)
    @team.add_repository(@org_repo1, :admin)
    @team.add_repository(@org_repo2, :admin)

    @org_installation = make_integration_installation(repository: @org_repo1, permissions: { "metadata" => :read })
    @repo_integration = @org_installation.integration
  end

  test "returns a failed result if the action is invalid" do
    result = IntegrationInstallation::RepositoryEditor.perform(@org_installation, action: :foo, repositories: [@org_repo2], editor: @org_member, entry_point: :test_case)

    refute_predicate result, :success?
    assert_equal "Invalid action", result.error
  end

  test "updates installation's updated_at timestamp", skip_if_feature_enabled: :cached_fgp_permissions do
    previous_updated_at = @org_installation.updated_at

    assert_equal @org_installation.permissions, { "metadata" => :read }
    # explicitly cache the permissions, to verify they are cleared after the update
    @org_installation.get_cached_permissions
    assert_equal @org_installation.permissions_cache, { "metadata" => "read" }

    Timecop.travel(5.minutes.from_now) do
      result = IntegrationInstallation::RepositoryEditor.perform(@org_installation, action: :add, repositories: [@org_repo2], editor: @admin, entry_point: :test_case)
      new_updated_at = @org_installation.reload.updated_at

      assert_predicate result, :success?
      assert_operator previous_updated_at, :<, new_updated_at

      assert_equal @org_installation.permissions, { "metadata" => :read }
      # ensure the cached permissions are cleared
      assert_nil @org_installation.permissions_cache
    end
  end

  context "ACTION :add" do
    test "returns an error if the action is not permitted" do
      errored_result = IntegrationInstallation::Permissions::Result.new(@org_member, @org, :add, false, reason: :stubbed_result)
      IntegrationInstallation::Permissions.any_instance.stubs(:check).returns(errored_result)

      result = IntegrationInstallation::RepositoryEditor.perform(@org_installation, action: :add, repositories: [@org_repo2], editor: @admin, entry_point: :test_case)

      refute_predicate result, :success?
      assert_equal "You do not have permission to modify this app on #{@org.display_login}. Please contact an Organization Owner.", result.error
    end

    test "add a repository to an installation" do
      result = IntegrationInstallation::RepositoryEditor.perform(@org_installation, action: :add, repositories: [@org_repo2], editor: @admin, entry_point: :test_case)

      assert_predicate result, :success?
      assert_includes @org_installation.reload.repositories, @org_repo2
    end

    test "overwrites permissions granted if app has internal capability :static_installation_repository_permissions" do
      integration = create(:codespaces_integration)
      org_installation = make_integration_installation(integration: integration, repository: @org_repo1)
      result = IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :add, repositories: [@org_repo2], editor: @admin, entry_point: :test_case)

      assert_predicate result, :success?
      assert_includes org_installation.reload.repositories, @org_repo2

      expected_permissions = Apps::Privileged.property(:static_installation_repository_permissions, app: integration)
      unexpected_permissions = integration.latest_version.permissions_of_type(Repository).reject { |resource, _| expected_permissions.key?(resource) }

      expected_permissions.each_pair do |resource, action|
        subject = @org_repo2.resources.public_send(resource.to_sym)
        assert_actor_and_subject_granted_in_permissions_table actor: org_installation, subject: subject, action: action
      end

      unexpected_permissions.each_pair do |resource, action|
        subject = @org_repo2.resources.public_send(resource.to_sym)
        refute_actor_and_subject_granted_in_permissions_table actor: org_installation, subject: subject, action: action
      end
    end

    test "is instrumented" do
      org_installation = make_integration_installation(repository: @org_repo1, permissions: { "metadata" => :read })
      integration = org_installation.integration

      events = subscribe "integration_installation.repositories_added"
      IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :add, repositories: [@org_repo2], editor: @repo_admin, entry_point: :test_case)

      expected_payload = {}.tap do |payload|
        payload[:installation_id]          = org_installation.id
        payload[:name]                     = integration.name
        payload[:slug]                     = integration.slug
        payload[:repository_selection]     = "selected"
        payload[:requester_id]             = nil

        payload[:actor]                    = @repo_admin.login
        payload[:actor_id]                 = @repo_admin.id
        payload[:repositories_added]       = [@org_repo2.id]
        payload[:repositories_added_names] = [@org_repo2.full_name]
        payload[:application_client_id]    = integration.key
        payload[:integration]              = integration.name
        payload[:integration_id]           = integration.id
        payload[:app]                      = integration.name
        payload[:app_id]                   = integration.id
        payload[:org]                      = @org.to_s
        payload[:org_id]                   = @org.id
      end

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload, event.payload
    end

    test "returns an error if repo owner is not the installation target" do
      # mimics a GHES race condition with repo transfer and installation edit
      # https://github.com/github/ecosystem-apps/issues/4363
      # this vulnerability does not exist on Dotcom
      GitHub.stubs(:repository_transfer_requests_enabled?).returns(false)
      installation = make_integration_installation(repositories: @org_repo1, permissions: { "metadata" => :read })
      repo = create(:repository)
      # at initial check, repo has correct owner.
      # editor confirms after the action if repo has been transferred to a different owner.
      return_values = [@org.id, repo.owner.id]
      repo.stub :owner_id, proc { return_values.shift } do
        result = IntegrationInstallation::RepositoryEditor.perform(installation, action: :add, repositories: [repo], editor: @admin, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_includes result.error, "Repositories must be owned by #{@org.display_login}."
        refute_includes installation.repositories, repo
        refute_granted_in_permissions_table(
          actor_id:     installation.id,
          actor_type:   "IntegrationInstallation",
          subject_id:   repo.id,
          subject_type: "Repository/metadata",
        )
      end
    end
  end

  context "ACTION :add_from_api" do
    test "is instrumented properly when an installation is the actor" do
      org_installation = make_integration_installation(repository: @org_repo1, permissions: { "metadata" => :read, "administration" => :write })
      integration = org_installation.integration

      events = subscribe "integration_installation.repositories_added"
      IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :add_from_api, repositories: [@org_repo2], editor: org_installation, entry_point: :test_case)

      expected_payload = {}.tap do |payload|
        payload[:installation_id]          = org_installation.id
        payload[:name]                     = integration.name
        payload[:slug]                     = integration.slug
        payload[:repository_selection]     = "selected"
        payload[:requester_id]             = nil

        payload[:actor]                    = org_installation.bot.display_login
        payload[:actor_id]                 = org_installation.bot.id
        payload[:repositories_added]       = [@org_repo2.id]
        payload[:repositories_added_names] = [@org_repo2.full_name]
        payload[:application_client_id]    = integration.key
        payload[:integration]              = integration.name
        payload[:integration_id]           = integration.id
        payload[:app]                      = integration.name
        payload[:app_id]                   = integration.id
        payload[:org]                      = @org.to_s
        payload[:org_id]                   = @org.id
      end

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload, event.payload
    end
  end

  context "ACTION :remove" do
    test "returns an error if the action is not permitted" do
      errored_result = IntegrationInstallation::Permissions::Result.new(@org_member, @org, :remove, false, reason: :stubbed_result)
      IntegrationInstallation::Permissions.any_instance.stubs(:check).returns(errored_result)

      result = IntegrationInstallation::RepositoryEditor.perform(@org_installation, action: :remove, repositories: [@org_repo2], editor: @admin, entry_point: :test_case)

      refute_predicate result, :success?
      assert_equal "You do not have permission to modify this app on #{@org.display_login}. Please contact an Organization Owner.", result.error
    end

    test "removes a repository from an installation" do
      org_installation = make_integration_installation(repositories: [@org_repo1, @org_repo2], permissions: { "metadata" => :read })
      result = IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :remove, repositories: [@org_repo2], editor: @admin, entry_point: :test_case)

      assert_predicate result, :success?
      refute_includes org_installation.reload.repositories, @org_repo2
    end

    test "uninstalls the app if all repos are removed" do
      Hook.stubs(:delivers_in_test?).returns(true)

      org_installation = make_integration_installation(repositories: [@org_repo1, @org_repo2], permissions: { "metadata" => :read })
      result = IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :remove, repositories: [@org_repo1, @org_repo2], editor: @admin, entry_point: :test_case)

      assert_predicate result, :success?
      assert_nil IntegrationInstallation.find_by(id: org_installation.id)
    end

    test "does not automatically uninstall the app when :auto_uninstall is set to false" do
      integration = create_privileged_app_with_capabilities(capabilities: { auto_uninstall: false })
      org_installation = make_integration_installation(integration: integration, repositories: [@org_repo1, @org_repo2])

      result = IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :remove, repositories: [@org_repo1, @org_repo2], editor: @admin, entry_point: :test_case)
      assert_predicate result, :success?

      refute_nil IntegrationInstallation.find_by(id: org_installation.id)
      assert_empty org_installation.reload.repository_ids
    end

    test "is instrumented" do
      org_installation = make_integration_installation(repositories: [@org_repo1, @org_repo2], permissions: { "metadata" => :read })
      integration      = org_installation.integration

      events = subscribe "integration_installation.repositories_removed"
      IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :remove, repositories: [@org_repo2], editor: @repo_admin, entry_point: :test_case)

      expected_payload = {}.tap do |payload|
        payload[:installation_id]            = org_installation.id
        payload[:name]                       = integration.name
        payload[:slug]                       = integration.slug
        payload[:repository_selection]       = "selected"

        payload[:actor]                      = @repo_admin.login
        payload[:actor_id]                   = @repo_admin.id
        payload[:repositories_removed]       = [@org_repo2.id]
        payload[:repositories_removed_names] = [@org_repo2.full_name]
        payload[:application_client_id]      = integration.key
        payload[:integration]                = integration.name
        payload[:integration_id]             = integration.id
        payload[:app]                        = integration.name
        payload[:app_id]                     = integration.id
        payload[:org]                        = @org.to_s
        payload[:org_id]                     = @org.id
      end

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end

    test "queues the SyncScopedIntegrationInstallationsJob" do
      org_installation = make_integration_installation(repositories: [@org_repo1, @org_repo2], permissions: { "metadata" => :read })

      assert_enqueued_with(job: SyncScopedIntegrationInstallationsJob, args: [org_installation, action: :repositories_removed, repository_ids: [@org_repo2.id], entry_point: :test_case]) do
        IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :remove, repositories: [@org_repo2], editor: @admin, entry_point: :test_case)
      end
    end
  end

  context "ACTION :update" do
    test "returns an error if the integration is installed on all repos" do
      # not expected to encounter this
      errored_result = IntegrationInstallation::Permissions::Result.new(@org_member, @org, :manage, false, reason: :stubbed_result)
      IntegrationInstallation::Permissions.any_instance.stubs(:check).returns(errored_result)

      org_installation = make_integration_installation(target: @org, repositories: [], permissions: { "metadata" => :read })
      assert_predicate org_installation, :installed_on_all_repositories?

      result = IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :update, repositories: [@org_repo2], editor: @repo_admin, entry_point: :test_case)

      refute_predicate result, :success?
      assert_equal "You do not have permission to modify this app on #{@org.display_login}. Please contact an Organization Owner.", result.error
    end

    test "returns an error if the action is not permitted" do
      errored_result = IntegrationInstallation::Permissions::Result.new(@org_member, @org, :manage, false, reason: :stubbed_result)
      IntegrationInstallation::Permissions.any_instance.stubs(:check).returns(errored_result)

      result = IntegrationInstallation::RepositoryEditor.perform(@org_installation, action: :update, repositories: [@org_repo2], editor: @repo_admin, entry_point: :test_case)

      refute_predicate result, :success?
      assert_equal "You do not have permission to modify this app on #{@org.display_login}. Please contact an Organization Owner.", result.error
    end

    test "add a repository to an installation" do
      result = IntegrationInstallation::RepositoryEditor.perform(@org_installation, action: :update, repositories: [@org_repo1, @org_repo2], editor: @repo_admin, entry_point: :test_case)

      assert_predicate result, :success?, result.error
      @org_installation.reload
      assert_includes @org_installation.repositories, @org_repo2
      assert_includes @org_installation.repositories, @org_repo1
    end

    test "instruments when a repository is added" do
      events = subscribe "integration_installation.repositories_added"
      IntegrationInstallation::RepositoryEditor.perform(@org_installation, action: :update, repositories: [@org_repo1, @org_repo2], editor: @repo_admin, entry_point: :test_case)

      expected_payload = {}.tap do |payload|
        payload[:installation_id]          = @org_installation.id
        payload[:name]                     = @repo_integration.name
        payload[:slug]                     = @repo_integration.slug
        payload[:repository_selection]     = "selected"
        payload[:requester_id]             = nil

        payload[:actor]                    = @repo_admin.login
        payload[:actor_id]                 = @repo_admin.id
        payload[:repositories_added]       = [@org_repo2.id]
        payload[:repositories_added_names] = [@org_repo2.full_name]
        payload[:application_client_id]    = @repo_integration.key
        payload[:integration]              = @repo_integration.name
        payload[:integration_id]           = @repo_integration.id
        payload[:app]                      = @repo_integration.name
        payload[:app_id]                   = @repo_integration.id
        payload[:org]                      = @org.to_s
        payload[:org_id]                   = @org.id
      end

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end

    test "remove a repository from an installation" do
      org_installation = make_integration_installation(repositories: [@org_repo1, @org_repo2], permissions: { "metadata" => :read })
      result = IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :update, repositories: [@org_repo1], editor: @repo_admin, entry_point: :test_case)

      assert_predicate result, :success?, result.error
      org_installation.reload
      refute_includes org_installation.repositories, @org_repo2
      assert_includes org_installation.repositories, @org_repo1
    end

    test "removes protected branch permissions when the associated repository is uninstalled" do
      protected_branch = create(:protected_branch, repository: @org_repo2)
      org_installation = make_integration_installation(repositories: [@org_repo1, @org_repo2], permissions: { "metadata" => :read })

      subject = protected_branch.resources.contents
      action  = :write

      Permissions::Service.grant_app_permission(actor: org_installation, subject: subject, action: action, entry_point: :test_case)

      assert_granted_in_permissions_table(
        actor_id:     org_installation.id,
        actor_type:   "IntegrationInstallation",
        subject_id:   protected_branch.id,
        subject_type: "ProtectedBranch/contents",
      )

      result = IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :update, repositories: [@org_repo1], editor: @repo_admin, entry_point: :test_case)
      assert_predicate result, :success?, result.error

      refute_granted_in_permissions_table(
        actor_id:     org_installation.id,
        actor_type:   "IntegrationInstallation",
        subject_id:   protected_branch.id,
        subject_type: "ProtectedBranch/contents",
      )
    end

    test "queues the SyncScopedIntegrationInstallationsJob when a repository is removed" do
      org_installation = make_integration_installation(repositories: [@org_repo1, @org_repo2], permissions: { "metadata" => :read })

      assert_enqueued_with(job: SyncScopedIntegrationInstallationsJob, args: [org_installation, action: :repositories_removed, repository_ids: [@org_repo2.id], entry_point: :test_case]) do
        IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :update, repositories: [@org_repo1], editor: @repo_admin, entry_point: :test_case)
      end
    end

    test "instruments when a repository is removed" do
      org_installation = make_integration_installation(repositories: [@org_repo1, @org_repo2], permissions: { "metadata" => :read })
      integration = org_installation.integration

      events = subscribe "integration_installation.repositories_removed"
      IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :update, repositories: [@org_repo1], editor: @repo_admin, entry_point: :test_case)

      expected_payload = {}.tap do |payload|
        payload[:installation_id]            = org_installation.id
        payload[:name]                       = integration.name
        payload[:slug]                       = integration.slug
        payload[:repository_selection]       = "selected"

        payload[:actor]                      = @repo_admin.login
        payload[:actor_id]                   = @repo_admin.id
        payload[:repositories_removed]       = [@org_repo2.id]
        payload[:repositories_removed_names] = [@org_repo2.full_name]
        payload[:application_client_id]      = integration.key
        payload[:integration]                = integration.name
        payload[:integration_id]             = integration.id
        payload[:app]                        = integration.name
        payload[:app_id]                     = integration.id
        payload[:org]                        = @org.to_s
        payload[:org_id]                     = @org.id
      end

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload, event.payload
    end

    test "skips after_updated_callbacks if skip_callbacks is true" do
      org_installation = make_integration_installation(repositories: [@org_repo1, @org_repo2], permissions: { "metadata" => :read })

      events = subscribe "integration_installation.repositories_removed"

      assert_enqueued_jobs 0, only: UpdateIntegrationInstallationRateLimitJob, queue: "update_integration_installation_rate_limit" do
        IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :update, repositories: [@org_repo1], editor: @repo_admin, skip_callbacks: true, entry_point: :test_case)
        refute event = events.pop, "unexpected instrumentation"
      end
    end

    test "add a repository removing only existing repository from installation" do
      result = IntegrationInstallation::RepositoryEditor.perform(@org_installation, action: :update, repositories: [@org_repo2], editor: @repo_admin, entry_point: :test_case)

      assert_predicate result, :success?, result.error
      @org_installation.reload
      assert_includes @org_installation.repositories, @org_repo2
      refute_includes @org_installation.repositories, @org_repo1
    end

    test "remove installation when last repository is removed" do
      result = IntegrationInstallation::RepositoryEditor.perform(@org_installation, action: :update, repositories: [], editor: @repo_admin, entry_point: :test_case)

      assert_predicate result, :success?, result.error
      assert_nil IntegrationInstallation.find_by(id: @org_installation.id)
    end

    test "remove accessible repositories leaving inaccessible repositories installed" do
      inaccessible_org_repo = create(:repository, :minimal, owner: @org)

      org_installation = make_integration_installation(repositories: [inaccessible_org_repo, @org_repo1], permissions: { "metadata" => :read })
      result = IntegrationInstallation::RepositoryEditor.perform(org_installation, action: :update, repositories: [], editor: @repo_admin, entry_point: :test_case)

      assert_predicate result, :success?, result.error
      org_installation.reload
      refute_includes org_installation.repositories, @org_repo1
      assert_includes org_installation.repositories, inaccessible_org_repo
    end

    test "avoids partially loaded repo exceptions", skip_if_feature_disabled: :fully_load_removable_repositories_for_installation do
      org_installation = make_integration_installation(repository: @org_repo1, permissions: { "metadata" => :read })
      integration = org_installation.integration

      # This is a bit of a hack to reproduce an scenario closer to what we see in:
      # https://github.com/github/ecosystem-apps/issues/6686
      Authorization.service
        .expects(:most_capable_collaborator_abilities_from_actor)
        .with(
          actor: @repo_admin,
          subject_type: Repository,
          subject_ids: [@org_repo2.id],
          min_action: :admin
        )
        .returns([])
        .once

      assert_nothing_raised do
        IntegrationInstallation::RepositoryEditor.perform(
          org_installation,
          action: :add,
          repositories: [@org_repo2],
          editor: @repo_admin,
          entry_point: :test_case
        )
      end
    end
  end
end
